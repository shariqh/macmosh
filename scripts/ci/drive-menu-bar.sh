#!/bin/bash
# CI only (.github/workflows/menu-pictures.yml; look step 6, issue 183): starts the debug app with each sample
# (MACMOSH_SAMPLE_MENU), photographs the menu bar around its item, and reads with bartool whether the system
# recoloured the item's picture for the menu bar, as it recolours its own items beside it. On six-desks it also
# opens the item with a posted click (menutool) and photographs the open item. It moves the pointer and presses
# Escape: never run it on your own Mac. It needs scripts/build-app.sh --debug and dist/debug/menutool first, and
# builds bartool itself unless BAR_TOOL names one. It changes no setting: the workflow sets the appearance.
#
#   MENU_OUT=<folder> MENU_BAR_APPEARANCE=light|dark scripts/ci/drive-menu-bar.sh
#
# What it leaves in MENU_OUT:
#   pictures/<os>-<appearance>-menubar-<sample>.png        the menu bar from 120 points left of the item to 120 right
#   pictures/<os>-<appearance>-menubar-<sample>-zoom.png   the item and 80 points to its right, 8 pixels a pixel
#   pictures/<os>-<appearance>-menubar-six-desks-open.png  the same with the item open, and its -zoom.png
#   driver.log    every step, System Events' and bartool's answers
#   app-log.txt   the app's own log lines (MenuLog) for the whole run
#   results.tsv   one line per check: result, os, sample, check, detail (drive-menu.sh's format)
#
# The checks, per sample:
#   the app starts                    PASS: the "sample menu: <sample>" line within 25 s and the process alive; else FAIL
#   the log names the state           PASS: the state's log line within 20 s; else FAIL
#   the menu-bar item's spoken name   the item's AXDescription, AXTitle, AXHelp and AXRoleDescription, read as
#                                     attributes; PASS when AXTitle is expected_spoken's words, else FAIL. Today's
#                                     words are the AXTitle on both versions; the AXDescription is empty
#   the system recolours the mark     PASS: our item and the system's items to its right each have at least 8 ink
#                                     pixels, the farthest ink of each lies on the same side of its bar (both darker
#                                     or both lighter), and ours is at least 0.3 from its bar in luminance. FAIL when
#                                     both have ink and the sides differ (a black mark the system left black on a
#                                     dark bar); NOT-SHOWN otherwise. The detail gives both readings.
#   the mark shows on the open item   six-desks only. PASS: ours is at least 0.3 from the open item's own ground;
#                                     else DIFFERS
# The job fails only on a FAIL. The pictures are 1 pixel per point on the runners, so hollow and faint cells both
# read as grey there: no check here tells them apart, and a person reads the -zoom pictures.
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
OUT=${MENU_OUT:?set MENU_OUT to the folder for pictures and logs}
look=${MENU_BAR_APPEARANCE:?set MENU_BAR_APPEARANCE to light or dark}
case "$look" in light | dark) ;; *) echo "MENU_BAR_APPEARANCE must be light or dark" >&2; exit 2 ;; esac
APP=${MENU_APP:-$root/dist/debug/MacMosh.app}
TOOL=${MENU_TOOL:-$root/dist/debug/menutool}
AX="$here/menu-ax.applescript"
LOG="$OUT/driver.log"
RESULTS="$OUT/results.tsv"
mkdir -p "$OUT/pictures"
: > "$RESULTS"
os="macos$(sw_vers -productVersion | cut -d. -f1)"
failures=0
sample=""
app_pid=""
run_since=$(date '+%Y-%m-%d %H:%M:%S')

# The helpers below are drive-menu.sh's, copied so that neither shared driver changes.
now() { perl -MTime::HiRes=time -e 'printf "%.3f", time'; }
say() { printf '%s drv %s\n' "$(now)" "$*" | tee -a "$LOG"; }
# lim <seconds> <command...>: the command, stopped by SIGALRM after that many seconds.
lim() { perl -e 'alarm shift @ARGV; exec @ARGV or die "exec failed"' "$@"; }
# A moment for `log show --start`: lines from the second before this one on.
moment() { date -v-1S '+%Y-%m-%d %H:%M:%S'; }

# result <PASS|FAIL|DIFFERS|NOT-SHOWN> <check> <detail>
result() {
    printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$os" "$sample" "$2" "$3" >> "$RESULTS"
    say "RESULT $1 [$sample] $2: $3"
    if [ "$1" = FAIL ]; then failures=$((failures + 1)); fi
}

# applog <moment>: the app's log lines since then.
applog() {
    lim 40 /usr/bin/log show --start "$1" --style compact \
        --predicate 'subsystem == "io.github.shariqh.macmosh"' 2>/dev/null | grep -E '^[0-9]{4}-'
}

# wait_log <moment> <text> <seconds>: until the app's log since then has that text.
wait_log() {
    local deadline=$((SECONDS + $3))
    while [ "$SECONDS" -lt "$deadline" ]; do
        applog "$1" | grep -qF "$2" && return 0
        sleep 1
    done
    say "the app's log has no [$2] within $3 s"
    return 1
}

# The log line that names each sample's state (look step 6's table).
state_line() {
    case "$1" in
        six-desks) echo "menu refreshed: symbol=checkmark.circle" ;;
        sign-ins-off) echo "symbol=exclamationmark.circle" ;;
        waiting-for-login) echo "symbol=person.crop.circle.badge.questionmark" ;;
        locked) echo "symbol=lock.circle" ;;
        unreadable-list) echo "menu refreshed: the saved list can't be read" ;;
        cant-reach) echo "symbol=wifi.slash" ;;
        not-set-up) echo "symbol=wrench.and.screwdriver" ;;
        still-checking) echo "symbol=ellipsis.circle" ;;
        no-workhorses) echo "symbol=plus.circle" ;;
    esac
}

# The words the item must carry, per sample: MenuBarMark.spokenName of its symbol, today's words, which push 1 read
# as the item's AXTitle on macOS 15 and 26 (its AXDescription was empty).
expected_spoken() {
    case "$1" in
        six-desks) echo "Selected" ;;
        sign-ins-off) echo "Error" ;;
        waiting-for-login) echo "person.crop.circle.badge.questionmark" ;;
        locked) echo "Lock" ;;
        unreadable-list) echo "Warning" ;;
        cant-reach) echo "Wi-Fi Off" ;;
        not-set-up) echo "wrench.and.screwdriver" ;;
        still-checking) echo "More" ;;
        no-workhorses) echo "Add" ;;
    esac
}

# bartool's reading, as "bar far mean inkpx box", or nothing.
reading() {
    local r
    r=$(lim 20 "$BAR" read "$@" 2>&1)
    printf '%s bartool %s\n' "$(now)" "$r" >> "$LOG"
    printf '%s\n' "$r" | sed -n 's/^read bar=\([^ ]*\) far=\([^ ]*\) mean=\([^ ]*\) inkpx=\([^ ]*\) box=\([^ ]*\)$/\1 \2 \3 \4 \5/p'
}

# far_from_bar <bar> <far>: far - bar, to three places.
far_from_bar() { awk -v b="$1" -v f="$2" 'BEGIN { printf "%.3f", f - b }'; }

# recolour_check <our reading> <their reading>: the system recolours the mark.
recolour_check() {
    local ob of _om oi _obx tb tf _tm ti _tbx od td verdict
    read -r ob of _om oi _obx <<< "$1"
    read -r tb tf _tm ti _tbx <<< "$2"
    local detail="appearance=$look ours=[$1] theirs=[$2]"
    if [ -z "${oi:-}" ] || [ -z "${ti:-}" ]; then
        result NOT-SHOWN "the system recolours the mark" "$detail; a picture could not be read"
        return
    fi
    od=$(far_from_bar "$ob" "$of")
    td=$(far_from_bar "$tb" "$tf")
    verdict=$(awk -v oi="$oi" -v ti="$ti" -v od="$od" -v td="$td" 'BEGIN {
        if (oi < 8 || ti < 8) { print "NOT-SHOWN"; exit }
        if ((od < 0) != (td < 0)) { print "FAIL"; exit }
        if (od < 0 ? -od >= 0.3 : od >= 0.3) { print "PASS"; exit }
        print "NOT-SHOWN" }')
    result "$verdict" "the system recolours the mark" "$detail; ours far-bar=$od, theirs far-bar=$td"
}

# barinfo: reads the item into $item ("x y w h"), $spoken_record (its four attributes) and $title (its AXTitle).
# Called directly, never in $(...), so the three reach the caller.
item=""
spoken_record=""
title=""
barinfo() {
    local b pos size
    b=$(lim 25 osascript "$AX" barinfo 2>&1 | grep '^barinfo' | tail -n 1)
    printf '%s ax[barinfo] %s\n' "$(now)" "$b" >> "$LOG"
    pos=$(sed -n 's/.*pos=\([0-9-]*,[0-9-]*\).*/\1/p' <<< "$b")
    size=$(sed -n 's/.*size=\([0-9-]*,[0-9-]*\).*/\1/p' <<< "$b")
    spoken_record=$(sed -n 's/.* \(axdescription=\[.*\]\)$/\1/p' <<< "$b")
    title=$(sed -n 's/.* axtitle=\[\(.*\)\] axhelp=\[.*$/\1/p' <<< "$b")
    item=""
    [ -z "$pos" ] || [ -z "$size" ] && return 1
    item="${pos%,*} ${pos#*,} ${size%,*} ${size#*,}"
}

# shoot <name> <x> <y> <w> <h>: the strip around the item and its zoom; prints our reading and theirs, a line each.
shoot() {
    local name=$1 x=$2 y=$3 w=$4 h=$5 strip
    strip="$OUT/pictures/$name.png"
    lim 15 screencapture -x -R "$((x - 120)),0,$((w + 240)),$((y + h + 3))" "$strip" >> "$LOG" 2>&1 \
        || printf '%s drv screencapture failed for %s\n' "$(now)" "$name" >> "$LOG"
    printf '%s drv picture %s.png\n' "$(now)" "$name" >> "$LOG"
    lim 20 "$BAR" zoom "$strip" 120 0 $((w + 80)) $((y + h + 3)) "$OUT/pictures/$name-zoom.png" >> "$LOG" 2>&1
    local ours theirs
    ours=$(reading "$strip" 120 "$y" "$w" "$h")
    theirs=$(reading "$strip" $((120 + w)) "$y" 80 "$h")
    printf '%s\n%s\n' "$ours" "$theirs"
}

stop_app() {
    [ -n "$app_pid" ] && kill "$app_pid" 2>/dev/null
    [ -n "$app_pid" ] && wait "$app_pid" 2>/dev/null
    app_pid=""
    sleep 1
}

# one_sample <sample>
one_sample() {
    sample=$1
    local since support line x y w h ours theirs both open_ours n want ob of
    since=$(moment)
    support=$(mktemp -d)
    say "== $sample: start the app"
    env MACMOSH_SAMPLE_MENU="$sample" MACMOSH_SUPPORT_DIR="$support" "$APP/Contents/MacOS/MacMosh" \
        >> "$OUT/app-stderr.txt" 2>&1 &
    app_pid=$!
    if ! wait_log "$since" "sample menu: $sample" 25 || ! kill -0 "$app_pid" 2>/dev/null; then
        result FAIL "the app starts" "no 'sample menu: $sample' line, or the process ended"
        stop_app
        return
    fi
    result PASS "the app starts" "pid $app_pid"
    line=$(state_line "$sample")
    if wait_log "$since" "$line" 20; then
        result PASS "the log names the state" "log: $line"
    else
        result FAIL "the log names the state" "no '$line' line within 20 s"
    fi
    sleep 1
    if ! barinfo; then
        result NOT-SHOWN "the menu-bar item's spoken name" "System Events gave no position for the item"
        result NOT-SHOWN "the system recolours the mark" "System Events gave no position for the item"
        stop_app
        return
    fi
    read -r x y w h <<< "$item"
    want=$(expected_spoken "$sample")
    if [ -z "$spoken_record" ]; then
        result FAIL "the menu-bar item's spoken name" "System Events gave no attributes for the item"
    elif [ "$title" = "$want" ]; then
        result PASS "the menu-bar item's spoken name" "$spoken_record"
    else
        result FAIL "the menu-bar item's spoken name" "expected axtitle=[$want]; read $spoken_record"
    fi
    both=$(shoot "$os-$look-menubar-$sample" "$x" "$y" "$w" "$h")
    ours=$(sed -n 1p <<< "$both")
    theirs=$(sed -n 2p <<< "$both")
    recolour_check "$ours" "$theirs"

    if [ "$sample" = six-desks ]; then
        say "open the item: click at $((x + w / 2)),$((y + h / 2))"
        lim 20 "$TOOL" click $((x + w / 2)) $((y + h / 2)) >> "$LOG" 2>&1
        n=0
        for _ in $(seq 1 30); do
            n=$(lim 10 "$TOOL" count 2>/dev/null || echo 0)
            [ "$n" -ge 1 ] && break
            sleep 0.2
        done
        if [ "$n" -ge 1 ]; then
            both=$(shoot "$os-$look-menubar-six-desks-open" "$x" "$y" "$w" "$h")
            open_ours=$(sed -n 1p <<< "$both")
            read -r ob of _ <<< "$open_ours"
            if [ -n "${of:-}" ] && awk -v b="$ob" -v f="$of" 'BEGIN { d = f - b; exit !(d >= 0.3 || d <= -0.3) }'; then
                result PASS "the mark shows on the open item" "appearance=$look open=[$open_ours]"
            else
                result DIFFERS "the mark shows on the open item" "appearance=$look open=[$open_ours]"
            fi
        else
            result DIFFERS "the mark shows on the open item" "the menu did not open within 6 s of the click"
        fi
        lim 20 "$TOOL" keys 53 1 300 >> "$LOG" 2>&1
    fi
    stop_app
}

############################################################ the run
say "picturing the menu bar of $APP on $os ($(sw_vers -productVersion)), appearance $look"
style=$(defaults read -g AppleInterfaceStyle 2>/dev/null || true)
say "AppleInterfaceStyle reads: ${style:-nothing}"
shown=light
[ "$style" = Dark ] && shown=dark
if [ "$look" != "$shown" ]; then
    say "the runner's appearance is not $look; no pictures were taken under that name"
    echo "::error::The runner is not in the $look appearance; the menu bar was not pictured."
    exit 1
fi
BAR=${BAR_TOOL:-$OUT/bartool}
if [ -z "${BAR_TOOL:-}" ]; then
    lim 300 swiftc -O -o "$BAR" "$here/bartool.swift" >> "$LOG" 2>&1 || { say "bartool did not build"; exit 1; }
fi
lim 20 "$TOOL" preflight >> "$LOG" 2>&1
lim 10 "$TOOL" move 600 500 > /dev/null

samples="six-desks sign-ins-off waiting-for-login locked unreadable-list cant-reach not-set-up still-checking no-workhorses"
for s in $samples; do one_sample "$s"; done

applog "$run_since" > "$OUT/app-log.txt"
sample=""
say "done: $failures failed check(s)"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    {
        echo "### The menu bar on $os, $look"
        echo
        echo "| result | sample | check | detail |"
        echo "|---|---|---|---|"
        awk -F '\t' '{ printf "| %s | %s | %s | %s |\n", $1, $3, $4, $5 }' "$RESULTS"
    } >> "$GITHUB_STEP_SUMMARY"
fi
cat "$RESULTS"
[ "$failures" -eq 0 ]
