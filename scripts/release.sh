#!/bin/bash
# Makes a copy of MacMosh that a stranger can download and open without a warning (issue #36).
#
#   scripts/release.sh <version>               on a clean main that equals origin/main: builds and signs the app
#                                              with scripts/build-app.sh --into dist/release/<version>, checks it,
#                                              sends it to Apple's notary service, staples the ticket, asks
#                                              Gatekeeper, makes MacMosh-<version>.zip and its .sha256, checks the
#                                              copy unpacked from that zip, and prints the tag, draft-release and
#                                              cask text for the owner to approve
#   scripts/release.sh --rehearsal <version>   the same build and checks on any branch, into
#                                              dist/rehearsal/<version>, up to the zip for Apple; sends nothing
#
# It publishes nothing: it never tags, never pushes, never makes a release and never touches the tap. It never
# signs anything itself (scripts/build-app.sh does), never stores a credential, and never deletes: an old
# rehearsal folder and its own temporary folder go to the Trash.
#
# It reads MACMOSH_SIGN_IDENTITY (the signing certificate's name, for scripts/build-app.sh) and
# MACMOSH_NOTARY_PROFILE (the keychain profile notarytool reads), and never prints the first. What names the
# certificate's owner stays in files under dist/, which git ignores. The owner's runbook is docs/releasing.md.
#
# Exit codes: 0 for a finished release or rehearsal, 1 for a refusal or a failed check, 2 for a usage error.
set -euo pipefail

usage() {
    echo "usage: scripts/release.sh [--rehearsal] <version>" >&2
    exit 2
}

# Before anything is built.
refuse() {
    echo "release.sh: refused: $1" >&2
    exit 1
}

# After the build has started.
stop() {
    echo "release.sh: stopped: $1" >&2
    exit 1
}

rehearsal=0
case "$#" in
    1)
        wanted=$1
        ;;
    2)
        [ "$1" = --rehearsal ] || usage
        rehearsal=1
        wanted=$2
        ;;
    *) usage ;;
esac
case "$wanted" in
    "" | -*) usage ;;
esac

cd "$(dirname "$0")/.."

# 1 and 2: the version is read with build-app.sh's own line.
version=$(sed -n 's/^ *public static let version = "\([0-9][0-9.]*\)".*/\1/p' Sources/MacMoshKit/MacMoshKit.swift 2>/dev/null || true)
if [ -z "$version" ]; then
    refuse "could not read the app's version from Sources/MacMoshKit/MacMoshKit.swift."
fi
if [ "$wanted" != "$version" ]; then
    refuse "$wanted is not the app's version; Sources/MacMoshKit/MacMoshKit.swift says $version."
fi

# 3 and 4: the settings.
if [ -z "${MACMOSH_SIGN_IDENTITY:-}" ]; then
    refuse "MACMOSH_SIGN_IDENTITY is empty, and a release is never signed ad hoc."
fi
if [ "$rehearsal" -eq 0 ] && [ -z "${MACMOSH_NOTARY_PROFILE:-}" ]; then
    refuse "MACMOSH_NOTARY_PROFILE is empty; set it to the profile name you saved with notarytool store-credentials."
fi

# 5: a clean checkout, for a rehearsal too.
if ! changes=$(git status --porcelain) || [ -n "$changes" ]; then
    refuse "the checkout has changes that are not committed."
fi

# 6 to 11: only a release needs these. --no-tags keeps origin's tags out of the local check, so 9 and 10 each say
# where the tag is.
if [ "$rehearsal" -eq 0 ]; then
    if ! branch=$(git symbolic-ref --quiet --short HEAD); then
        refuse "the checkout is on a detached HEAD, not main."
    fi
    if [ "$branch" != main ]; then
        refuse "the checkout is on $branch, not main."
    fi
    if ! git fetch --quiet --no-tags origin >/dev/null 2>&1; then
        refuse "could not fetch origin to compare main with it."
    fi
    here=$(git rev-parse HEAD)
    there=$(git rev-parse --quiet --verify refs/remotes/origin/main || true)
    if [ "$here" != "$there" ]; then
        refuse "main here is not the same commit as origin/main."
    fi
    if git rev-parse --quiet --verify "refs/tags/v$version" >/dev/null; then
        refuse "the tag v$version already exists here."
    fi
    asked=0
    git ls-remote --exit-code --tags origin "refs/tags/v$version" >/dev/null 2>&1 || asked=$?
    if [ "$asked" -eq 0 ]; then
        refuse "the tag v$version already exists on origin."
    elif [ "$asked" -ne 2 ]; then
        refuse "could not ask origin whether the tag v$version exists."
    fi
    if [ -e "dist/release/$version" ]; then
        refuse "dist/release/$version already exists; move it to the Trash to build this version again."
    fi
fi

out="dist/release/$version"
if [ "$rehearsal" -eq 1 ]; then
    out="dist/rehearsal/$version"
fi
app="$out/MacMosh.app"

# The build. A rehearsal's last folder goes to the Trash first, under a name of its own.
if [ "$rehearsal" -eq 1 ] && [ -e "$out" ]; then
    mkdir -p "$HOME/.Trash"
    last="$HOME/.Trash/rehearsal-$version-$(date +%Y%m%d-%H%M%S)"
    n=1
    while [ -e "$last" ]; do
        last="$HOME/.Trash/rehearsal-$version-$(date +%Y%m%d-%H%M%S)-$n"
        n=$((n + 1))
    done
    mv "$out" "$last"
    echo "release.sh: the last rehearsal of $version is in the Trash"
fi
echo "release.sh: building MacMosh $version into $out"
if ! scripts/build-app.sh --into "$out"; then
    stop "scripts/build-app.sh failed; its own message is above."
fi

# The checks before anything is sent. codesign's and spctl's longer answers name the certificate's owner, so they
# go to files in $out (which git ignores); the terminal gets only the verdict.
if ! codesign --verify --deep --strict --verbose=2 "$app"; then
    stop "the signature of $app did not verify (codesign --verify --deep --strict)."
fi
plutil -convert xml1 -o "$out/entitlements-expected.xml" App/MacMosh.entitlements
for item in app command; do
    if [ "$item" = app ]; then
        path=$app
        name=MacMosh.app
    else
        path="$app/Contents/Helpers/macmosh"
        name=Contents/Helpers/macmosh
    fi
    codesign --display --entitlements - --xml "$path" > "$out/entitlements-$item.plist" 2>/dev/null || true
    if ! plutil -convert xml1 -o "$out/entitlements-$item.xml" "$out/entitlements-$item.plist" >/dev/null 2>&1 ||
        ! cmp -s "$out/entitlements-$item.xml" "$out/entitlements-expected.xml"; then
        stop "the entitlements on $name are not exactly those of App/MacMosh.entitlements."
    fi
    codesign --display --verbose=2 "$path" > "$out/signature-$item.txt" 2>&1 || true
    # A basic regular expression, in which ( is a plain character.
    if ! grep -q '^CodeDirectory .*flags=0x[0-9a-f]*([^)]*runtime' "$out/signature-$item.txt"; then
        stop "$name does not have the hardened runtime switched on."
    fi
    if ! grep -q '^Timestamp=' "$out/signature-$item.txt"; then
        stop "$name has no secure timestamp."
    fi
done
for name in Contents/MacOS/MacMosh Contents/Helpers/macmosh; do
    archs=$(lipo -archs "$app/$name" 2>/dev/null || true)
    if [ "$archs" != arm64 ]; then
        stop "$name is built for $archs; the first release is for Apple silicon (arm64) only."
    fi
    # The match is never printed: it would show a folder name from the Mac that built it.
    if LC_ALL=C grep -qaF /Users/ "$app/$name"; then
        stop "$name contains a folder path from the Mac that built it (the text /Users/)."
    fi
    if LC_ALL=C grep -qaF MACMOSH_SAMPLE_MENU "$app/$name"; then
        stop "$name contains MACMOSH_SAMPLE_MENU, so it is not a release build."
    fi
done
found=$(plutil -extract CFBundleShortVersionString raw -o - "$app/Contents/Info.plist" 2>/dev/null || true)
if [ "$found" != "$version" ]; then
    stop "MacMosh.app says version $found, not $version."
fi
echo "release.sh: checks passed: signature, entitlements, hardened runtime, timestamp, arm64 only, no /Users/, no sample menu, version $version"

# The zip for Apple: notarytool takes a zip, and ditto keeps the bundle's signature intact in it.
ditto -c -k --keepParent "$app" "$out/for-notary.zip"

if [ "$rehearsal" -eq 1 ]; then
    finished="release.sh: rehearsal finished. Nothing was sent to Apple's notary service, and nothing in $out is a release."
    echo "$finished" > "$out/REHEARSAL.txt"
    echo "$finished"
    exit 0
fi

stop "sending to Apple is not written yet."
