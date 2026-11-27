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

# Sending. notarytool's exit code for an Invalid answer or a timeout is not documented, so the script reads its
# documented normal output instead: the first "id:" line and the last "status:" line.
echo "release.sh: sending for-notary.zip to Apple's notary service; it usually answers within 5 to 15 minutes, and this waits up to 30"
xcrun notarytool submit "$out/for-notary.zip" --keychain-profile "$MACMOSH_NOTARY_PROFILE" --wait --timeout 30m --no-progress \
    > "$out/notary-submit.txt" 2>&1 || true
id=$(awk '/^ *id: / { print $2; exit }' "$out/notary-submit.txt")
status=$(awk '/^ *status: / { sub(/^ *status: /, ""); sub(/[ \t\r]+$/, ""); answer = $0 } END { print answer }' "$out/notary-submit.txt")
if [ -z "$id" ]; then
    cat "$out/notary-submit.txt" >&2
    stop "notarytool could not send for-notary.zip to Apple; what it said is in $out/notary-submit.txt."
fi
if [ -z "$status" ] || [ "$status" = "In Progress" ]; then
    stop "Apple had not finished after 30 minutes; submission $id goes on without this script. Ask later with: xcrun notarytool info $id --keychain-profile \"\$MACMOSH_NOTARY_PROFILE\""
fi

# Apple's log is kept and its issues shown even when the answer is Accepted.
if ! xcrun notarytool log "$id" --keychain-profile "$MACMOSH_NOTARY_PROFILE" "$out/notary-log.json"; then
    stop "could not download Apple's notary log for submission $id, so nothing was stapled."
fi
issues=$(plutil -extract issues raw -o - "$out/notary-log.json" 2>/dev/null || true)
case "$issues" in
    "" | *[!0-9]*) issues=0 ;;
esac
if [ "$issues" -eq 0 ]; then
    echo "release.sh: Apple's notary log lists no issues."
else
    echo "release.sh: Apple's notary log lists $issues issue(s):"
    i=0
    while [ "$i" -lt "$issues" ]; do
        severity=$(plutil -extract "issues.$i.severity" raw -o - "$out/notary-log.json" 2>/dev/null || true)
        where=$(plutil -extract "issues.$i.path" raw -o - "$out/notary-log.json" 2>/dev/null || true)
        message=$(plutil -extract "issues.$i.message" raw -o - "$out/notary-log.json" 2>/dev/null || true)
        echo "  $severity: $where: $message"
        i=$((i + 1))
    done
fi
if [ "$status" != Accepted ]; then
    stop "Apple's answer is $status, not Accepted, so nothing was stapled; the whole log is in $out/notary-log.json."
fi
echo "release.sh: Apple accepted submission $id"

# Stapling: a zip cannot carry the ticket, so it goes on the app, and the zip people download is made afterwards.
if ! xcrun stapler staple "$app"; then
    stop "xcrun stapler could not staple the ticket to $app."
fi
if ! xcrun stapler validate "$app"; then
    stop "the ticket stapled to $app did not validate."
fi

# Gatekeeper, the check a Mac makes when a downloaded app first opens. Its answer names the certificate's owner.
if ! spctl --assess --type execute -vv "$app" > "$out/gatekeeper.txt" 2>&1; then
    source=$(grep -m 1 '^source=' "$out/gatekeeper.txt" || true)
    stop "Gatekeeper did not accept $app ($source); its whole answer is in $out/gatekeeper.txt."
fi
echo "release.sh: Gatekeeper: accepted ($(grep -m 1 '^source=' "$out/gatekeeper.txt" || true))"

# The zip people download, made from the stapled app.
zip_name="MacMosh-$version.zip"
ditto -c -k --keepParent "$app" "$out/$zip_name"

# The same checks on a copy unpacked from that zip, in a folder of its own that goes to the Trash at the end. The
# template is given in full: mktemp -t would use the per-user temporary folder before TMPDIR.
base=${TMPDIR:-/tmp}
check=$(mktemp -d "${base%/}/macmosh-release.XXXXXXXX")
tidy() {
    if [ -n "${check:-}" ] && [ -d "$check" ]; then
        mkdir -p "$HOME/.Trash" || true
        mv "$check" "$HOME/.Trash/" || true
    fi
}
trap tidy EXIT
copy="$check/MacMosh.app"
verdict=""
if ! ditto -x -k "$out/$zip_name" "$check" || ! codesign --verify --deep --strict --verbose=2 "$copy"; then
    verdict="did not verify"
elif ! xcrun stapler validate "$copy"; then
    verdict="has no valid ticket"
elif ! spctl --assess --type execute -vv "$copy" > "$out/gatekeeper-download.txt" 2>&1; then
    verdict="was not accepted by Gatekeeper ($(grep -m 1 '^source=' "$out/gatekeeper-download.txt" || true))"
fi
if [ -n "$verdict" ]; then
    mv "$out/$zip_name" "$out/NOT-FOR-RELEASE-$zip_name"
    stop "the copy unpacked from $zip_name $verdict, so the zip is renamed NOT-FOR-RELEASE-$zip_name and has no checksum."
fi

# The checksum, in shasum's own format, as the cask's sha256 wants it.
(cd "$out" && shasum -a 256 "$zip_name") > "$out/$zip_name.sha256"
sha=$(awk '{ print $1; exit }' "$out/$zip_name.sha256")
commit=$(git rev-parse HEAD)

# Printed, never run: the owner says yes first.
printf '%s\n' "release.sh: done. MacMosh $version is notarized, stapled and checked."
printf '%s\n' "  zip:      $out/$zip_name"
printf '%s\n' "  checksum: $out/$zip_name.sha256 (SHA-256 $sha)"
printf '%s\n' "release.sh: nothing was tagged, pushed or published. After the owner says yes, these make the tag and a draft release:"
printf '%s\n' "  git tag -a v$version -m \"MacMosh $version\" $commit"
printf '%s\n' "  git push origin v$version"
printf '%s\n' "  gh release create v$version $out/$zip_name $out/$zip_name.sha256 --draft --verify-tag --title \"MacMosh $version, first public preview\" --generate-notes"
printf '%s\n' "release.sh: the cask for the tap (Casks/macmosh.rb, issue #37):"
printf '%s\n' "cask \"macmosh\" do"
printf '%s\n' "  version \"$version\""
printf '%s\n' "  sha256 \"$sha\""
printf '%s\n' "  url \"https://github.com/shariqh/macmosh/releases/download/v#{version}/MacMosh-#{version}.zip\""
printf '%s\n' "  name \"MacMosh\""
printf '%s\n' "  desc \"Menu bar app for mosh and tmux sessions on another Mac\""
printf '%s\n' "  homepage \"https://github.com/shariqh/macmosh\""
printf '%s\n' "  depends_on arch: :arm64"
printf '%s\n' "  depends_on macos: :sequoia"
printf '%s\n' "  depends_on formula: \"mosh\""
printf '%s\n' "  app \"MacMosh.app\""
printf '%s\n' "  binary \"#{appdir}/MacMosh.app/Contents/Helpers/macmosh\""
printf '%s\n' "end"
