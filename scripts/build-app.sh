#!/bin/bash
# Builds dist/MacMosh.app: the menu-bar app and, beside it, the macmosh command.
#
#   scripts/build-app.sh            signs with the certificate named in MACMOSH_SIGN_IDENTITY,
#                                   or ad hoc when that variable is unset or empty
#   scripts/build-app.sh --adhoc    signs ad hoc whatever the variable says
#   scripts/build-app.sh --debug    a debug build in dist/debug/MacMosh.app, signed ad hoc, for CI's
#                                   pictures of the menu (.github/workflows/menu-pictures.yml). Only a
#                                   debug build can show a sample menu (MACMOSH_SAMPLE_MENU).
#   scripts/build-app.sh --into dist/release/0.1.0
#                                   builds and signs as the first line does, into that folder; scripts/release.sh
#                                   uses it. --adhoc may go with it, --debug may not.
#
# The app's icon is the committed App/Assets.car (the layered icon, light and dark) and App/AppIcon.iconset
# (the light M), packed into AppIcon.icns with iconutil (block A, below). No Xcode is needed for it:
# scripts/make-icon.sh makes both again by hand, and this script never runs it.
#
# The certificate's name comes only from that environment variable. It is never written to a
# file, a log or this script's output.
set -euo pipefail

cd "$(dirname "$0")/.."
root=$(pwd -P)

usage() {
    echo "usage: scripts/build-app.sh [--adhoc | --debug] [--into <folder under dist/>]" >&2
    exit 2
}

# Every word is read before anything else runs, so a refusal builds nothing and writes nothing.
adhoc=0
config=release
into=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --adhoc) adhoc=1 ;;
        --debug)
            adhoc=1
            config=debug
            ;;
        --into)
            if [ "$#" -lt 2 ] || [ -z "$2" ]; then
                usage
            fi
            into=$2
            shift
            ;;
        *) usage ;;
    esac
    shift
done
if [ -n "$into" ]; then
    [ "$config" = release ] || usage
    case "$into" in
        dist/?*) ;;
        *)
            echo "build-app.sh: FAILED: --into takes a folder under dist/, such as dist/release/0.1.0" >&2
            exit 2
            ;;
    esac
    # A `.` or `..` part, or an empty one (`dist//`), could name dist/ itself or a folder outside it.
    case "/$into/" in
        */../* | */./* | *//?*)
            echo "build-app.sh: FAILED: --into takes a folder under dist/, such as dist/release/0.1.0" >&2
            exit 2
            ;;
    esac
fi
if [ -z "${MACMOSH_SIGN_IDENTITY:-}" ]; then
    adhoc=1
fi

app="dist/MacMosh.app"
if [ "$config" = debug ]; then
    app="dist/debug/MacMosh.app"
fi
if [ -n "$into" ]; then
    app="$into/MacMosh.app"
fi
entitlements="App/MacMosh.entitlements"

# The version is read from the source, the same constant that `macmosh --version` prints.
version=$(sed -n 's/^ *public static let version = "\([0-9][0-9.]*\)".*/\1/p' Sources/MacMoshKit/MacMoshKit.swift)
if [ -z "$version" ]; then
    echo "build-app.sh: FAILED: could not read the version from Sources/MacMoshKit/MacMoshKit.swift" >&2
    exit 1
fi

# Block A: the icon (design section 8.2; look step 5a, round 2), checked and packed in a work folder before
# anything is built and before the app folder is replaced, so a stop here leaves dist/ as it was.
#
# App/Assets.car is the compile of the Icon Composer document App/AppIcon.icon, made by hand with
# scripts/make-icon.sh and committed: the light and dark M for macOS 26 and newer. The build does not compile
# it, because on CI's macOS 15 image Xcode 26's asset compiler crashed in each build (pull request 176).
# App/AppIcon.iconset is that compile's light render, with the solid 16-pixel M (App/AppIcon-16.png) as
# icon_16x16.png; packed into AppIcon.icns, it is the loose icon CFBundleIconFile names (design 8.2). On CI's macOS
# 15 and 26 runners the system's 16-point icon showed Assets.car's tiles, not this solid M (pull request 176).
if [ ! -s App/Assets.car ]; then
    echo "build-app.sh: FAILED: App/Assets.car is missing or empty; make it again with scripts/make-icon.sh" >&2
    exit 1
fi
iconset=App/AppIcon.iconset
for picture in icon_16x16.png icon_16x16@2x.png icon_32x32.png icon_32x32@2x.png icon_128x128.png \
    icon_128x128@2x.png icon_256x256.png icon_256x256@2x.png icon_512x512.png icon_512x512@2x.png; do
    if [ ! -f "$iconset/$picture" ]; then
        echo "build-app.sh: FAILED: $iconset has no $picture" >&2
        exit 1
    fi
done
work=$(mktemp -d -t build-app-icon)
if ! iconutil -c icns -o "$work/AppIcon.icns" "$iconset" >&2 || [ ! -s "$work/AppIcon.icns" ]; then
    echo "build-app.sh: FAILED: iconutil could not make AppIcon.icns from App/AppIcon.iconset (work folder $work)" >&2
    exit 1
fi
echo "build-app.sh: icon: App/Assets.car is there, and AppIcon.icns was made from $iconset"

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

# Issue 189: a release build keeps debugging entries that name every source and object file by its full path on
# the Mac that built it, so both programs carried the builder's folder names. strip -S takes those entries out
# (man strip: "Remove the debugging symbol table entries (those created by the -g option to cc(1) and other
# compilers)"); the ordinary symbols stay, so a crash report still names functions. Stripping changes the file,
# so it comes after the comparisons above and before signing. The search then reads the file's bytes (grep -a),
# for the home folders' parent and for this checkout's own folder; the match is never printed. `strings -a` piped
# into grep found none of these paths on 26 November 2026, so nothing here relies on strings.
# CI's pictures use the debug build as it is: it is never shipped.
if [ "$config" = release ]; then
    for file in "$app/Contents/MacOS/MacMosh" "$app/Contents/Helpers/macmosh"; do
        places=$({ LC_ALL=C grep -aoF "$root" "$file" || true; } | wc -l | tr -d ' ')
        strip -S -no_code_signature_warning "$file"
        for needle in "/Users/" "$root"; do
            if LC_ALL=C grep -qaF "$needle" "$file"; then
                echo "build-app.sh: FAILED: the release build $file still holds a folder path from the Mac that built it" >&2
                exit 1
            fi
        done
        echo "build-app.sh: stripped $file: $places places named this checkout's folder before, none after"
    done
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
cp App/Assets.car "$app/Contents/Resources/"
cp "$work/AppIcon.icns" "$app/Contents/Resources/"
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
