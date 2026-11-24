#!/bin/bash
# Builds dist/MacMosh.app: the menu-bar app and, beside it, the macmosh command.
#
#   scripts/build-app.sh            signs with the certificate named in MACMOSH_SIGN_IDENTITY,
#                                   or ad hoc when that variable is unset or empty
#   scripts/build-app.sh --adhoc    signs ad hoc whatever the variable says
#   scripts/build-app.sh --debug    a debug build in dist/debug/MacMosh.app, signed ad hoc, for CI's
#                                   pictures of the menu (.github/workflows/menu-pictures.yml). Only a
#                                   debug build can show a sample menu (MACMOSH_SAMPLE_MENU).
#
# The certificate's name comes only from that environment variable. It is never written to a
# file, a log or this script's output.
set -euo pipefail

cd "$(dirname "$0")/.."

adhoc=0
config=release
case "${1:-}" in
    "") ;;
    --adhoc) adhoc=1 ;;
    --debug)
        adhoc=1
        config=debug
        ;;
    *)
        echo "usage: scripts/build-app.sh [--adhoc | --debug]" >&2
        exit 2
        ;;
esac
if [ -z "${MACMOSH_SIGN_IDENTITY:-}" ]; then
    adhoc=1
fi

app="dist/MacMosh.app"
if [ "$config" = debug ]; then
    app="dist/debug/MacMosh.app"
fi
entitlements="App/MacMosh.entitlements"

# The version is read from the source, the same constant that `macmosh --version` prints.
version=$(sed -n 's/^ *public static let version = "\([0-9][0-9.]*\)".*/\1/p' Sources/MacMoshKit/MacMoshKit.swift)
if [ -z "$version" ]; then
    echo "build-app.sh: FAILED: could not read the version from Sources/MacMoshKit/MacMoshKit.swift" >&2
    exit 1
fi

echo "build-app.sh: swift build -c $config (version $version)"
swift build -c "$config" --product MacMoshApp
swift build -c "$config" --product macmosh
bin=$(swift build -c "$config" --show-bin-path)

echo "build-app.sh: making $app"
rm -rf "$app"
# The command goes in Contents/Helpers, not beside the app: `MacMosh` and `macmosh` are the same
# file name on a case-insensitive volume (macOS's default), and one would overwrite the other.
mkdir -p "$app/Contents/MacOS" "$app/Contents/Helpers"
cp "$bin/MacMoshApp" "$app/Contents/MacOS/MacMosh"
cp "$bin/macmosh" "$app/Contents/Helpers/macmosh"
cp App/Info.plist "$app/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$version" "$app/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$version" "$app/Contents/Info.plist"
plutil -lint "$app/Contents/Info.plist" >/dev/null

# The two must be two different files, and the app must be the one built from the MacMoshApp product.
if [ "$app/Contents/MacOS/MacMosh" -ef "$app/Contents/Helpers/macmosh" ]; then
    echo "build-app.sh: FAILED: the app and the command ended up as one file" >&2
    exit 1
fi
if ! cmp -s "$bin/MacMoshApp" "$app/Contents/MacOS/MacMosh"; then
    echo "build-app.sh: FAILED: Contents/MacOS/MacMosh is not the MacMoshApp build" >&2
    exit 1
fi
if ! cmp -s "$bin/macmosh" "$app/Contents/Helpers/macmosh"; then
    echo "build-app.sh: FAILED: Contents/Helpers/macmosh is not the macmosh build" >&2
    exit 1
fi

# The sample menus CI takes pictures of are compiled into debug builds only (#if DEBUG in
# Sources/MacMoshKit/Menu/SampleMenu.swift and the app). A release app must not even contain the name
# of the variable that picks one; a debug app must, which shows that this search finds it.
sample_variable=MACMOSH_SAMPLE_MENU
if [ "$config" = release ]; then
    for file in "$app/Contents/MacOS/MacMosh" "$app/Contents/Helpers/macmosh"; do
        if grep -qaF "$sample_variable" "$file"; then
            echo "build-app.sh: FAILED: the release build $file contains $sample_variable: sample menus must stay in debug builds" >&2
            exit 1
        fi
    done
    echo "build-app.sh: no sample menu in the release build ($sample_variable is not in either binary)"
elif ! grep -qaF "$sample_variable" "$app/Contents/MacOS/MacMosh"; then
    echo "build-app.sh: FAILED: the debug app does not contain $sample_variable, so the release check proves nothing" >&2
    exit 1
fi

# The inner command is signed first, then the app around it.
if [ "$adhoc" -eq 1 ]; then
    echo "build-app.sh: signing ad hoc. macOS will ask for the app's permissions again after every rebuild."
    sign=(codesign --force --options runtime --entitlements "$entitlements" --sign -)
    how="ad hoc"
else
    echo "build-app.sh: signing with the Developer ID certificate"
    sign=(codesign --force --options runtime --timestamp --entitlements "$entitlements"
          --sign "$MACMOSH_SIGN_IDENTITY")
    how="signed"
fi
"${sign[@]}" "$app/Contents/Helpers/macmosh"
"${sign[@]}" "$app"

codesign --verify --deep --strict --verbose=2 "$app"
echo "build-app.sh: built $app ($how)"
