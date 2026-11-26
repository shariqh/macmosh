#!/bin/bash
# Makes the app icon's files again from IconArt (look step 5a, issue 175). Run by hand, from anywhere, on a Mac
# with Xcode 26 or newer; build-app.sh and CI never run it. Commit what it changes.
#
#   scripts/make-icon.sh
#
# 1. The drawing script draws AppIcon.icon/Assets/m-light.png and m-dark.png and AppIcon-16.png.
# 2. actool compiles that copy of the Icon Composer document into Assets.car (the layered icon, light and dark,
#    for macOS 26 and newer) and an AppIcon.icns of every size (its light render).
# 3. iconutil unpacks that .icns into AppIcon.iconset, with the solid 16-pixel M as icon_16x16.png.
# It makes and checks everything in a new temporary work folder, then copies into App/, and names the folder at
# the end. Each copy into App/ is on a line of its own, after the last check, so a stop leaves App/ as it was.
set -euo pipefail
cd "$(dirname "$0")/.."
say() { echo "make-icon.sh: $*"; }
stop() { echo "make-icon.sh: FAILED: $*" >&2; exit 1; }
work=$(mktemp -d -t make-icon)

# actool reads Icon Composer documents from Xcode 26 on. When the selected Xcode is older, the newest
# /Applications/Xcode*.app of 26 or newer runs actool, through DEVELOPER_DIR.
selected=$(xcodebuild -version 2>/dev/null | sed -n '1s/^Xcode \([0-9][0-9.]*\).*/\1/p' || true)
if [ -n "$selected" ] && [ "${selected%%.*}" -ge 26 ]; then
    say "actool from Xcode $selected (the selected Xcode)"
else
    best=$(for xcode in /Applications/Xcode*.app; do
        found=$(plutil -extract CFBundleShortVersionString raw "$xcode/Contents/version.plist" 2>/dev/null) || continue
        if [ "${found%%.*}" -ge 26 ] 2>/dev/null; then echo "$found $xcode"; fi
    done | sort -t. -k1,1n -k2,2n | tail -n 1)
    [ -n "$best" ] || stop "no Xcode 26 or newer found (the selected one is ${selected:-none}); actool needs one."
    export DEVELOPER_DIR="${best#* }/Contents/Developer"
    say "actool from Xcode ${best%% *} (${best#* })"
fi

mkdir -p "$work/App"
cp -R App/AppIcon.icon "$work/App/"
swiftc -O -o "$work/draw-icon" scripts/draw-icon/main.swift Sources/MacMoshKit/Look/IconArt.swift
"$work/draw-icon" "$work"
mkdir -p "$work/out"
if ! xcrun actool "$work/App/AppIcon.icon" --compile "$work/out" --platform macosx --minimum-deployment-target 15.0 \
    --app-icon AppIcon --output-partial-info-plist "$work/partial.plist" --target-device mac \
    --standalone-icon-behavior all --errors --warnings --output-format human-readable-text > "$work/actool.txt" 2>&1; then
    cat "$work/actool.txt" >&2
    stop "actool could not compile the icon document (work folder $work)"
fi
# Given a document it cannot find, actool exits 0 and writes nothing.
[ -s "$work/out/Assets.car" ] && [ -s "$work/out/AppIcon.icns" ] || stop "actool wrote no Assets.car or AppIcon.icns ($work)"
for key in CFBundleIconFile CFBundleIconName; do
    named=$(plutil -extract "$key" raw "$work/partial.plist" 2>/dev/null) || named=""
    [ "$named" = AppIcon ] || stop "actool names $key ${named:-nothing}, App/Info.plist says AppIcon ($work)"
done
iconutil -c iconset -o "$work/AppIcon.iconset" "$work/out/AppIcon.icns"
sizes="16x16 16x16@2x 32x32 32x32@2x 128x128 128x128@2x 256x256 256x256@2x 512x512 512x512@2x"
for size in $sizes; do
    [ -f "$work/AppIcon.iconset/icon_$size.png" ] || stop "AppIcon.icns has no icon_$size.png ($work)"
done
for drawn in AppIcon.icon/Assets/m-light.png AppIcon.icon/Assets/m-dark.png AppIcon-16.png; do
    [ -s "$work/App/$drawn" ] || stop "the drawing script wrote no App/$drawn ($work)"
done

# Every check passed: now the copies into App/.
cp "$work/App/AppIcon-16.png" "$work/AppIcon.iconset/icon_16x16.png"
mkdir -p App/AppIcon.iconset
cp "$work/App/AppIcon.icon/Assets/m-light.png" App/AppIcon.icon/Assets/m-light.png
cp "$work/App/AppIcon.icon/Assets/m-dark.png" App/AppIcon.icon/Assets/m-dark.png
cp "$work/App/AppIcon-16.png" App/AppIcon-16.png
for size in $sizes; do
    cp "$work/AppIcon.iconset/icon_$size.png" "App/AppIcon.iconset/icon_$size.png"
done
cp "$work/out/Assets.car" App/Assets.car
say "wrote App/Assets.car, App/AppIcon.iconset (ten pictures) and the drawing script's three; work folder $work"
