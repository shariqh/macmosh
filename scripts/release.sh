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

# Task 3: the build and the checks before sending.
exit 0
