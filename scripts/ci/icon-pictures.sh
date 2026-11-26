#!/bin/bash
# CI only (.github/workflows/icon-pictures.yml; look step 5a, issue 175): checks the icon files in the debug app and
# draws the app's icon as the system gives it (scripts/ci/icontool.swift), then reveals the app in Finder and takes a
# picture of the screen. It opens Finder: never run it on your own Mac. It needs scripts/build-app.sh --debug and the
# built dist/debug/icontool first.
#
#   ICON_OUT=<folder> scripts/ci/icon-pictures.sh <light|dark|darkstyle>
#
# The workflow runs it once per macOS version in light, then after it has switched the runner to dark, each with
# its own ICON_OUT. On macOS 26 it may run a third time, "darkstyle", after the workflow's one try at the Dark icon
# style (the workflow sets it, never this script, which changes no setting). Every name carries the mode after the
# version: "macos26", "macos26-dark", "macos26-darkstyle".
#
# What it leaves in ICON_OUT:
#   pictures/<os>-icon-sheet-1x.png and -2x.png   icontool's sheet at 1 and 2 pixels per point: the icon in a light
#                                                 row, a dark row and the .icns's own row, at 16 to 256 points
#   pictures/<os>-finder.png and -finder-later.png the screen with the app revealed in Finder, 3 and 15 seconds on
#   pictures/<os>-styles-sheet.png                (light only) the icon document drawn by Apple's ictool in its six
#                                                 renditions: Default, ClearLight, TintedLight on white above,
#                                                 Dark, ClearDark, TintedDark on charcoal below
#   <os>-styles/<rendition>.png                   (light only) ictool's six renders, 512 pixels
#   <os>-icns/AppIcon.iconset                     the app's AppIcon.icns, unpacked
#   <os>-assetutil.json                           assetutil --info of the app's Assets.car
#   icon.log                                      every step and icontool's output
#   results.tsv                                   one line per check: <check> PASS|FAIL|NOT-SHOWN <detail>
#
# The app carries the layered icon (look step 5a, round 2): the committed App/Assets.car and an AppIcon.icns.
# Checks:
#   the app has its icon files          Assets.car and AppIcon.icns in Contents/Resources, not empty, and the
#                                       Assets.car is the repository's App/Assets.car byte for byte
#   Info.plist names the icon           CFBundleIconFile and CFBundleIconName both read AppIcon
#   Assets.car holds a light and a dark icon   assetutil --info lists an IconImageStack for NSAppearanceNameAqua
#                                       and one for NSAppearanceNameDarkAqua. NOT-SHOWN when this runner has no
#                                       assetutil, when it fails, or when it lists no IconImageStack at all (an
#                                       assetutil too old to know them); FAIL when it lists stacks but not both
#   the .icns holds a 16-pixel picture  icon_16x16.png is 16 wide
#   the icon sheet was drawn            icontool exits 0 at 1x and 2x and both files exist
#   Finder shows the app                a picture was taken; NOT-SHOWN when not, never FAIL
#   the styles sheet was drawn          (light only) ictool from the selected Xcode or an /Applications/Xcode_26*.app
#                                       rendered all six and icontool drew the sheet; NOT-SHOWN when no ictool
#                                       is found or none renders, FAIL only when icontool cannot draw six renders
#   the system draws the dark M in the Dark icon style   (darkstyle only) the unlit tile icontool reads in the
#                                       system's icon, drawn under aqua, is dark (luminance under 0.35); NOT-SHOWN
#                                       otherwise, with the readings and what the workflow tried
# In every mode the log says which M the system's icon shows under each drawing appearance (icontool's "tile"
# lines). It exits 1 when any check is FAIL, and never on how a picture looks: a person reads the pictures.
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
OUT=${ICON_OUT:?set ICON_OUT to the folder for pictures and logs}
APP=${ICON_APP:-$root/dist/debug/MacMosh.app}
TOOL=${ICON_TOOL:-$root/dist/debug/icontool}
appearance=${1:-}
case "$appearance" in
    light | dark | darkstyle) ;;
    *)
        echo "usage: ICON_OUT=<folder> scripts/ci/icon-pictures.sh <light|dark|darkstyle>" >&2
        exit 2
        ;;
esac
LOG="$OUT/icon.log"
RESULTS="$OUT/results.tsv"
mkdir -p "$OUT/pictures"
: > "$LOG"
: > "$RESULTS"
os="macos$(sw_vers -productVersion | cut -d. -f1)"
[ "$appearance" = light ] || os="$os-$appearance"
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

say "$os: $(sw_vers -productVersion), mode $appearance, AppleInterfaceStyle $(defaults read -g AppleInterfaceStyle 2>/dev/null || echo unset), AppleIconAppearanceTheme $(defaults read -g AppleIconAppearanceTheme 2>/dev/null || echo unset)"
resources="$APP/Contents/Resources"

# 1. The app has its icon files.
if [ -s "$resources/Assets.car" ] && [ -s "$resources/AppIcon.icns" ]; then
    if cmp -s "$resources/Assets.car" "$root/App/Assets.car"; then
        result "the app has its icon files" PASS "Assets.car (the repository's App/Assets.car) and AppIcon.icns in Contents/Resources"
    else
        result "the app has its icon files" FAIL "Contents/Resources/Assets.car is not the repository's App/Assets.car"
    fi
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
if [ "$icon_file" = AppIcon ] && [ "$icon_name" = AppIcon ]; then
    result "Info.plist names the icon" PASS "CFBundleIconFile and CFBundleIconName read AppIcon"
else
    result "Info.plist names the icon" FAIL "CFBundleIconFile reads ${icon_file:-nothing}, CFBundleIconName reads ${icon_name:-nothing}"
fi

# 3. Assets.car holds a light and a dark icon. assetutil writes one JSON object per asset, opened and closed at a
# depth of two spaces, with its own keys at four; an object's "Appearance" and "AssetType" are read in either order
# and judged when it closes. The stacks' own layers sit deeper and are not read.
check="Assets.car holds a light and a dark icon"
info="$OUT/$os-assetutil.json"
if ! command -v assetutil >/dev/null 2>&1; then
    result "$check" NOT-SHOWN "this runner has no assetutil"
elif ! lim 60 assetutil --info "$resources/Assets.car" > "$info" 2>&1; then
    result "$check" NOT-SHOWN "assetutil --info could not read it: $(head -c 300 "$info" | tr '\n' ' ')"
else
    stacks=$(awk '/^  \{/ { appearance = ""; stack = 0 }
        /^    "Appearance" : / { appearance = $3; gsub(/[",]/, "", appearance) }
        /^    "AssetType" : "IconImageStack"/ { stack = 1 }
        /^  \}/ { if (stack) print (appearance == "" ? "no-appearance" : appearance); stack = 0 }' "$info" | sort | tr '\n' ' ')
    say "assetutil lists icon stacks for: ${stacks:-nothing}"
    if [ -z "$stacks" ]; then
        result "$check" NOT-SHOWN "assetutil read it ($(grep -c '"AssetType"' "$info") assets) but lists no IconImageStack ($(grep -c '"AssetType" : "Unknown"' "$info") of type Unknown); $(grep -m1 '"DumpToolVersion"' "$info" | tr -d ' ,')"
    elif [[ " $stacks" == *" NSAppearanceNameAqua "* && " $stacks" == *" NSAppearanceNameDarkAqua "* ]]; then
        result "$check" PASS "IconImageStack for: $stacks(in $os-assetutil.json)"
    else
        result "$check" FAIL "IconImageStack only for: $stacks(in $os-assetutil.json)"
    fi
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
# Which M the system's icon shows: icontool's "tile" lines, from the 1x run (the 2x run reads the same images).
# The light M's unlit tiles are near white and the dark M's near #34322F, so 0.35 splits them. A sample that is not
# opaque (icontool prints "transparent") is no reading: it missed the icon.
which_m() {
    local line
    line=$(grep -m1 "^tile $1 #" "$LOG") || { echo "no reading"; return; }
    awk -v l="$line" 'BEGIN { split(l, f, " "); printf "%s, the %s M", f[3], (f[4] < 0.35 ? "dark" : "light") }'
}
say "reading: the system's icon drawn under aqua shows $(which_m light); under darkAqua $(which_m dark)"

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

# 7. The styles sheet (light only): the icon document drawn by Apple's ictool, which ships inside Xcode's Icon
# Composer from Xcode 26 on, in the six renditions its --help lists. The selected Xcode first, then each
# /Applications/Xcode_26*.app in reverse name order, each by its real path and once; the first whose ictool renders
# Default is used.
if [ "$appearance" = light ]; then
    check="the styles sheet was drawn"
    renditions="Default Dark ClearLight ClearDark TintedLight TintedDark"
    styles="$OUT/$os-styles"
    mkdir -p "$styles"
    ictool=""
    tried=""
    candidates=$( (xcode-select -p 2>/dev/null | sed 's|/Contents/Developer$||'; find /Applications -maxdepth 1 -name 'Xcode_26*.app' | sort -t_ -k2 -r) | while read -r xcode; do (cd -P "$xcode" 2>/dev/null && pwd); done | awk '!seen[$0]++')
    while IFS= read -r xcode; do
        [ -n "$xcode" ] || continue
        tool="$xcode/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"
        if [ ! -x "$tool" ]; then
            tried="$tried $(basename "$xcode") (no ictool);"
            continue
        fi
        say "ictool from $xcode: $(lim 20 "$tool" --version 2>&1 | tr -d '\n ' | head -c 120)"
        if lim 60 "$tool" "$root/App/AppIcon.icon" --export-image --output-file "$styles/Default.png" --platform macOS \
            --rendition Default --width 256 --height 256 --scale 2 >> "$LOG" 2>&1 && [ -s "$styles/Default.png" ]; then
            ictool="$tool"
            say "ictool used: $tool"
            break
        fi
        tried="$tried $(basename "$xcode") (ictool did not render Default);"
    done <<< "$candidates"
    if [ -z "$ictool" ]; then
        result "$check" NOT-SHOWN "no ictool rendered the document; tried:${tried:- no Xcode found}"
    else
        rendered=1
        for rendition in $renditions; do
            [ "$rendition" = Default ] && continue
            if lim 60 "$ictool" "$root/App/AppIcon.icon" --export-image --output-file "$styles/$rendition.png" \
                --platform macOS --rendition "$rendition" --width 256 --height 256 --scale 2 >> "$LOG" 2>&1 \
                && [ -s "$styles/$rendition.png" ]; then
                rendered=$((rendered + 1))
            else
                say "ictool did not render $rendition"
            fi
        done
        sheet="$OUT/pictures/$os-styles-sheet.png"
        if [ "$rendered" -ne 6 ]; then
            result "$check" NOT-SHOWN "ictool ($ictool) rendered $rendered of 6; icon.log has what it said"
        elif lim 60 "$TOOL" --styles "$sheet" 1 "$styles/Default.png" "$styles/Dark.png" "$styles/ClearLight.png" \
            "$styles/ClearDark.png" "$styles/TintedLight.png" "$styles/TintedDark.png" >> "$LOG" 2>&1 && [ -f "$sheet" ]; then
            result "$check" PASS "$os-styles-sheet.png, from ictool in ${ictool%%/Contents/Applications/*}"
        else
            result "$check" FAIL "ictool rendered all six, but icontool could not draw the sheet; icon.log has what it said"
        fi
    fi
fi

# 8. The Dark icon style (darkstyle only): the workflow has set it, by a guessed name, and read it back. Did the
# system's icon follow? icontool's reading under aqua says which M it drew.
if [ "$appearance" = darkstyle ]; then
    check="the system draws the dark M in the Dark icon style"
    reading=$(which_m light)
    if [[ "$reading" == *"the dark M" ]]; then
        result "$check" PASS "under aqua the system's icon shows $reading ($os-icon-sheet-2x.png)"
    else
        result "$check" NOT-SHOWN "under aqua the system's icon shows $reading, under darkAqua $(which_m dark); tried: AppleIconAppearanceTheme (a guessed name) reads $(defaults read -g AppleIconAppearanceTheme 2>/dev/null || echo unset)"
    fi
fi

say "done: $failures failed"
[ "$failures" -eq 0 ]
