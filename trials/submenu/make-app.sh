#!/bin/bash
# Builds trials/submenu/dist/SubmenuTrial.app (menu-bar only, ad hoc signed) and dist/trialtool.
# Trimmed from scripts/build-app.sh: no version, no helper command, no entitlements.
set -euo pipefail

cd "$(dirname "$0")"

swift build -c release
bin=$(swift build -c release --show-bin-path)

app="dist/SubmenuTrial.app"
mkdir -p dist
if [ -e "$app" ]; then
    mv "$app" "dist/old-$(date +%s).app"
fi
mkdir -p "$app/Contents/MacOS"
cp "$bin/SubmenuTrial" "$app/Contents/MacOS/SubmenuTrial"
cp "$bin/trialtool" dist/trialtool

plist="$app/Contents/Info.plist"
plutil -create xml1 "$plist"
plutil -insert CFBundleIdentifier -string "io.github.example.submenutrial" "$plist"
plutil -insert CFBundleName -string "SubmenuTrial" "$plist"
plutil -insert CFBundleExecutable -string "SubmenuTrial" "$plist"
plutil -insert CFBundlePackageType -string "APPL" "$plist"
plutil -insert CFBundleInfoDictionaryVersion -string "6.0" "$plist"
plutil -insert CFBundleShortVersionString -string "0.0.1" "$plist"
plutil -insert CFBundleVersion -string "1" "$plist"
plutil -insert LSMinimumSystemVersion -string "15.0" "$plist"
plutil -insert LSUIElement -bool true "$plist"
plutil -lint "$plist" >/dev/null

codesign --force --sign - dist/trialtool
codesign --force --sign - "$app"
codesign --verify --deep --strict --verbose=2 "$app"
echo "make-app.sh: built $app and dist/trialtool"
