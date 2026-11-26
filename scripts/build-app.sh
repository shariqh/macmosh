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
# The app's icon is compiled from the Icon Composer document App/AppIcon.icon with actool from Xcode 26
# or newer, which this script finds itself when the selected Xcode is older (block A, below).
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

# Block A: the icon (design section 8.2), made in a work folder before anything is built and before the
# app folder is replaced, so a stop here leaves dist/ as it was.
#
# 1. Pick the Xcode. actool reads Icon Composer documents from Xcode 26 on. When the selected Xcode is
#    older (CI's macOS 15 runner selects 16.4), the newest /Applications/Xcode*.app of 26 or newer runs
#    actool alone, through DEVELOPER_DIR (xcrun's manual: "When DEVELOPER_DIR is set, its value will be
#    used instead of the system-wide active developer directory.").
version_key() {
    local major minor patch
    IFS=. read -r major minor patch <<<"$1"
    echo $(( ${major:-0} * 10000 + ${minor:-0} * 100 + ${patch:-0} ))
}
selected=$(xcodebuild -version 2>/dev/null | sed -n '1s/^Xcode \([0-9][0-9.]*\).*/\1/p' || true)
developer_dir=""
if [ -n "$selected" ] && [ "${selected%%.*}" -ge 26 ]; then
    echo "build-app.sh: actool from Xcode $selected (the selected Xcode)"
else
    best=""
    best_key=0
    # Each Xcode by its real path: on CI's macOS 15 image, actool from Xcode 26.3 crashed when reached through
    # /Applications/Xcode_26.3.0.app, a second name for /Applications/Xcode_26.3.app, and worked through the real one.
    for xcode in /Applications/Xcode*.app; do
        real=$(cd -P "$xcode" && pwd) || continue
        [ -f "$real/Contents/version.plist" ] || continue
        found=$(plutil -extract CFBundleShortVersionString raw "$real/Contents/version.plist" 2>/dev/null || true)
        case "$found" in
            [0-9]*) ;;
            *) continue ;;
        esac
        [ "${found%%.*}" -ge 26 ] || continue
        key=$(version_key "$found")
        if [ "$key" -gt "$best_key" ]; then
            best="$found"
            best_key=$key
            developer_dir="$real/Contents/Developer"
        fi
    done
    if [ -z "$developer_dir" ]; then
        echo "build-app.sh: FAILED: no Xcode 26 or newer found (the selected one is ${selected:-none}); actool from Xcode 26 or newer compiles App/AppIcon.icon. Install one, or select it with xcode-select." >&2
        exit 1
    fi
    echo "build-app.sh: actool from Xcode $best (${developer_dir%/Contents/Developer})"
fi
# Runs a command with the chosen Xcode. An if, not an empty env array: /bin/bash 3.2 fails on an empty
# array under set -u.
with_xcode() {
    if [ -n "$developer_dir" ]; then
        DEVELOPER_DIR="$developer_dir" "$@"
    else
        "$@"
    fi
}

# 2. Compile, with absolute paths (actool reads relative ones from another folder).
#    --standalone-icon-behavior all puts every size in AppIcon.icns; actool's manual: "By default, a
#    small subset of sizes are included as loose files".
work=$(mktemp -d -t build-app-icon)
echo "build-app.sh: icon: actool compiles App/AppIcon.icon in $work"
if ! with_xcode xcrun actool "$PWD/App/AppIcon.icon" --compile "$work" --platform macosx --minimum-deployment-target 15.0 \
    --app-icon AppIcon --output-partial-info-plist "$work/partial.plist" --target-device mac \
    --standalone-icon-behavior all --errors --warnings --output-format human-readable-text > "$work/actool.txt" 2>&1; then
    echo "build-app.sh: FAILED: actool could not compile App/AppIcon.icon (work folder $work); what it said:" >&2
    cat "$work/actool.txt" >&2
    exit 1
fi

# 3. Check what it made: given a document path that does not exist, actool exits 0 and writes only an
#    empty partial plist.
if [ ! -f "$work/Assets.car" ] || [ ! -f "$work/AppIcon.icns" ]; then
    echo "build-app.sh: FAILED: actool wrote no Assets.car or AppIcon.icns from App/AppIcon.icon (work folder $work); what it said:" >&2
    cat "$work/actool.txt" >&2
    exit 1
fi
icon_key() {
    plutil -extract "$1" raw "$2" 2>/dev/null || true
}
made_file=$(icon_key CFBundleIconFile "$work/partial.plist")
made_name=$(icon_key CFBundleIconName "$work/partial.plist")
plist_file=$(icon_key CFBundleIconFile App/Info.plist)
plist_name=$(icon_key CFBundleIconName App/Info.plist)
if [ -z "$made_file" ] || [ "$made_file" != "$plist_file" ] || [ "$made_name" != "$plist_name" ]; then
    echo "build-app.sh: FAILED: actool names the icon ${made_file:-nothing}/${made_name:-nothing}, App/Info.plist names it ${plist_file:-nothing}/${plist_name:-nothing} (work folder $work)" >&2
    exit 1
fi

# 4. Swap in the solid M at 16 pixels (design 8.1): tiles would blur there. This reaches the loose
#    AppIcon.icns only; Assets.car's smallest icon picture is 32 pixels.
if ! iconutil -c iconset -o "$work/AppIcon.iconset" "$work/AppIcon.icns" >&2; then
    echo "build-app.sh: FAILED: iconutil could not unpack AppIcon.icns (work folder $work)" >&2
    exit 1
fi
if [ ! -f "$work/AppIcon.iconset/icon_16x16.png" ]; then
    echo "build-app.sh: FAILED: AppIcon.icns has no 16-pixel picture to replace (work folder $work)" >&2
    exit 1
fi
cp App/AppIcon-16.png "$work/AppIcon.iconset/icon_16x16.png"
if ! iconutil -c icns -o "$work/AppIcon.icns" "$work/AppIcon.iconset" >&2; then
    echo "build-app.sh: FAILED: iconutil could not pack AppIcon.icns with App/AppIcon-16.png (work folder $work)" >&2
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

# Block B: the icon goes in before signing, so the final verify covers it.
mkdir -p "$app/Contents/Resources"
cp "$work/Assets.car" "$work/AppIcon.icns" "$app/Contents/Resources/"
echo "build-app.sh: icon: Assets.car and AppIcon.icns in Contents/Resources"
rm -rf "$work"

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
