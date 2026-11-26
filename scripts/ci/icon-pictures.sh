#!/bin/bash
# CI only (.github/workflows/icon-pictures.yml; look step 5a, issue 175): checks the icon files in the debug app and
# draws the app's icon as the system gives it (scripts/ci/icontool.swift), then reveals the app in Finder and takes a
# picture of the screen. It opens Finder: never run it on your own Mac. It needs scripts/build-app.sh --debug and the
# built dist/debug/icontool first.
#
#   ICON_OUT=<folder> scripts/ci/icon-pictures.sh <light|dark>
#
# The workflow runs it twice per macOS version, once in light and once after it has switched the runner to dark,
# each with its own ICON_OUT. In dark every name carries "-dark" after the version ("macos15-dark").
#
# What it leaves in ICON_OUT:
#   pictures/<os>-icon-sheet-1x.png and -2x.png   icontool's sheet at 1 and 2 pixels per point: the icon in a light
#                                                 row, a dark row and the .icns's own row, at 16 to 256 points
#   pictures/<os>-finder.png and -finder-later.png the screen with the app revealed in Finder, 3 and 15 seconds on
#   <os>-icns/AppIcon.iconset                     the app's AppIcon.icns, unpacked
#   icon.log                                      every step and icontool's output
#   results.tsv                                   one line per check: <check> PASS|FAIL|NOT-SHOWN <detail>
#
# The app carries the fallback of design 8.3: a plain AppIcon.icns of the light M, with no Assets.car.
# Checks: the app has its icon files (AppIcon.icns in Contents/Resources and no Assets.car); Info.plist names the
# icon (CFBundleIconFile reads AppIcon and there is no CFBundleIconName); the app has no Assets.car and no
# CFBundleIconName (so the system has nothing but the .icns to draw); the .icns
# holds a 16-pixel picture (icon_16x16.png is 16 wide); the icon sheet was drawn (icontool exits 0 at 1x and 2x and
# both files exist); Finder shows the app (a picture was taken; NOT-SHOWN when not, never FAIL). It exits 1 when any
# check is FAIL, and never on how a picture looks: a person reads the pictures.
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
OUT=${ICON_OUT:?set ICON_OUT to the folder for pictures and logs}
APP=${ICON_APP:-$root/dist/debug/MacMosh.app}
TOOL=${ICON_TOOL:-$root/dist/debug/icontool}
appearance=${1:-}
case "$appearance" in
    light | dark) ;;
    *)
        echo "usage: ICON_OUT=<folder> scripts/ci/icon-pictures.sh <light|dark>" >&2
        exit 2
        ;;
esac
LOG="$OUT/icon.log"
RESULTS="$OUT/results.tsv"
mkdir -p "$OUT/pictures"
: > "$LOG"
: > "$RESULTS"
os="macos$(sw_vers -productVersion | cut -d. -f1)"
[ "$appearance" = dark ] && os="$os-dark"
failures=0

say() { printf '%s icon %s\n' "$(date '+%H:%M:%S')" "$*" | tee -a "$LOG"; }
# lim <seconds> <command...>: the command, stopped by SIGALRM after that many seconds.
lim() { perl -e 'alarm shift @ARGV; exec @ARGV or die "exec failed"' "$@"; }
# result <check> <PASS|FAIL|NOT-SHOWN> <detail>
result() {
    printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$RESULTS"
    say "RESULT $2 $1: $3"
    if [ "$2" = FAIL ]; then failures=$((failures + 1)); fi
}

say "$os: $(sw_vers -productVersion), appearance $appearance, AppleInterfaceStyle $(defaults read -g AppleInterfaceStyle 2>/dev/null || echo unset)"
resources="$APP/Contents/Resources"

# 1. The app has its icon files.
if [ -f "$resources/AppIcon.icns" ] && [ ! -e "$resources/Assets.car" ]; then
    result "the app has its icon files" PASS "AppIcon.icns in Contents/Resources, and no Assets.car"
else
    result "the app has its icon files" FAIL "Contents/Resources holds: $(find "$resources" -mindepth 1 -maxdepth 1 -exec basename {} \; 2>&1 | tr '\n' ' ')"
fi

# 2. Info.plist names the icon.
# A key's value, or nothing when the key is not there. On macOS 15 plutil prints "No value at that key path" on
# standard output when it fails, so its output counts only when it succeeds.
plist_key() {
    local value
    if value=$(plutil -extract "$1" raw "$APP/Contents/Info.plist" 2>/dev/null); then
        printf '%s' "$value"
    fi
}
icon_file=$(plist_key CFBundleIconFile)
icon_name=$(plist_key CFBundleIconName)
if [ "$icon_file" = AppIcon ] && [ -z "$icon_name" ]; then
    result "Info.plist names the icon" PASS "CFBundleIconFile reads AppIcon, and there is no CFBundleIconName"
else
    result "Info.plist names the icon" FAIL "CFBundleIconFile reads ${icon_file:-nothing}, CFBundleIconName reads ${icon_name:-nothing}"
fi

# 3. The app has no Assets.car and no CFBundleIconName.
car=absent
[ -e "$resources/Assets.car" ] && car=there
if [ "$car" = absent ] && [ -z "$icon_name" ]; then
    result "the app has no Assets.car and no CFBundleIconName" PASS "the system has only AppIcon.icns to draw"
else
    result "the app has no Assets.car and no CFBundleIconName" FAIL "Assets.car is $car, CFBundleIconName reads ${icon_name:-nothing}"
fi

# 4. The .icns holds a 16-pixel picture.
iconset="$OUT/$os-icns/AppIcon.iconset"
mkdir -p "$OUT/$os-icns"
if ! lim 60 iconutil -c iconset -o "$iconset" "$resources/AppIcon.icns" >> "$LOG" 2>&1; then
    result "the .icns holds a 16-pixel picture" FAIL "iconutil could not unpack AppIcon.icns"
else
    say "the .icns holds: $(find "$iconset" -name '*.png' -exec basename {} \; | sort | tr '\n' ' ')"
    small=$(sips -g pixelWidth "$iconset/icon_16x16.png" 2>/dev/null | sed -n 's/.*pixelWidth: //p')
    if [ "$small" = 16 ]; then
        result "the .icns holds a 16-pixel picture" PASS "icon_16x16.png is 16 wide; $(find "$iconset" -name '*.png' | wc -l | tr -d ' ') pictures"
    else
        result "the .icns holds a 16-pixel picture" FAIL "icon_16x16.png reads ${small:-nothing} wide"
    fi
fi

# 5. The icon sheet, at 1x and 2x.
drawn=0
for scale in 1 2; do
    sheet="$OUT/pictures/$os-icon-sheet-${scale}x.png"
    say "icontool at ${scale}x"
    if lim 60 "$TOOL" "$APP" "$sheet" "$scale" >> "$LOG" 2>&1 && [ -f "$sheet" ]; then
        drawn=$((drawn + 1))
    fi
done
if [ "$drawn" -eq 2 ]; then
    result "the icon sheet was drawn" PASS "$os-icon-sheet-1x.png and $os-icon-sheet-2x.png"
else
    result "the icon sheet was drawn" FAIL "icontool drew $drawn of the 2 sheets; icon.log has what it said"
fi

# 6. Finder shows the app: revealed, then a picture of the screen. What it shows is read by a person.
# Two pictures, 3 and 15 seconds after the reveal: Finder may still be loading its icons at the first.
finder="$OUT/pictures/$os-finder.png"
if lim 20 open -R "$APP" >> "$LOG" 2>&1; then
    sleep 3
    lim 20 screencapture -x "$finder" >> "$LOG" 2>&1
    sleep 12
    lim 20 screencapture -x "$OUT/pictures/$os-finder-later.png" >> "$LOG" 2>&1
fi
if [ -f "$finder" ] && [ -f "$OUT/pictures/$os-finder-later.png" ]; then
    result "Finder shows the app" PASS "$os-finder.png (3 seconds) and $os-finder-later.png (15 seconds) were taken"
else
    result "Finder shows the app" NOT-SHOWN "Finder could not reveal the app or the screen picture failed"
fi
# Close Finder's windows so the next run's picture shows its own. A failure here changes no result.
lim 15 osascript -e 'tell application "Finder" to close every window' >> "$LOG" 2>&1 || say "Finder's windows were not closed"

say "done: $failures failed"
[ "$failures" -eq 0 ]
