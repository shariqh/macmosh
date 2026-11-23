#!/bin/bash
# CI only: starts SubmenuTrial in several modes, drives its menu through System Events and, when
# the runner allows it, real pointer events (trialtool), and writes everything to one log:
#   $TRIAL_OUT/trial.log    app lines ("app"), driver lines ("drv"), trialtool lines ("tool")
#   $TRIAL_OUT/shots/*.png  a screenshot at each step
# Every wait has a deadline. Do not run this on your own Mac: it presses keys and moves the pointer.
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
OUT=${TRIAL_OUT:?set TRIAL_OUT}
LOG="$OUT/trial.log"
SHOTS="$OUT/shots"
mkdir -p "$SHOTS"
APP="$here/dist/SubmenuTrial.app/Contents/MacOS/SubmenuTrial"
TOOL="$here/dist/trialtool"
PHASE="X"
shotn=0
app_pid=""
opener_pid=""
POINTER=0
NAV_OK=1
# Which phases to run: A (no style), B (.menu style), C (live model), D (11 rows). Default: all.
PHASES=${TRIAL_PHASES:-ABCD}
# Phase A finds out whether posted pointer events work; TRIAL_POINTER=1 skips asking when A is not run.
POINTER=${TRIAL_POINTER:-0}

now() { perl -MTime::HiRes=time -e 'printf "%.3f", time'; }
say() { printf '%s drv %s\n' "$(now)" "$*" >> "$LOG"; }
mark() {
    say "MARK $PHASE $*"
    echo "== $PHASE $*"
}
# lim <seconds> <command...>: runs the command, killed by SIGALRM after that many seconds.
lim() { perl -e 'alarm shift @ARGV; exec @ARGV or die "exec failed"' "$@"; }

# ax <args>: one System Events call; its output goes to the log and to stdout.
ax() {
    local r st
    r=$(lim 20 osascript "$here/ax.applescript" "$@" 2>&1)
    st=$?
    while IFS= read -r l; do say "ax[$1] $l"; done <<< "$r"
    [ "$st" -ne 0 ] && say "ax[$1] exit=$st"
    printf '%s\n' "$r"
}
tool() { lim 15 "$TOOL" "$@" >> "$LOG" 2>&1; }
wins() { tool windows "$PHASE $1"; }
menu_windows() { lim 10 "$TOOL" windows q 2>/dev/null | sed -n 's/.*menuWindows=\([0-9]*\).*/\1/p' | head -n 1; }
shot() {
    shotn=$((shotn + 1))
    local f
    f=$(printf '%s/%02d-%s-%s.png' "$SHOTS" "$shotn" "$PHASE" "$1")
    lim 15 screencapture -x "$f" >> "$LOG" 2>&1 || say "screencapture failed for $f"
    say "screenshot $(basename "$f")"
}
key() {
    say "key $1 ($2)"
    ax key "$1" > /dev/null
    sleep 0.5
}

# wait_menus <want> <seconds>: until at least <want> menu windows are on screen (0: until none).
wait_menus() {
    local want=$1 limit=$2 n="" i t0
    t0=$(now)
    for ((i = 0; i < limit * 3; i++)); do
        n=$(menu_windows)
        n=${n:-0}
        if [ "$want" -eq 0 ]; then [ "$n" -eq 0 ] && break; else [ "$n" -ge "$want" ] && break; fi
        sleep 0.3
    done
    say "wait_menus want=$want got=$n since=$t0"
}

open_ax() {
    mark "open: AXPress on the menu-bar item (in the background, it returns when the menu closes)"
    lim 60 osascript "$here/ax.applescript" open >> "$LOG" 2>&1 &
    opener_pid=$!
    wait_menus 1 8
}

bar_centre() {
    local b pos size
    b=$(ax barpos | grep '^bar' | tail -n 1)
    pos=$(sed -n 's/.*pos=\([0-9-]*,[0-9-]*\).*/\1/p' <<< "$b")
    size=$(sed -n 's/.*size=\([0-9-]*,[0-9-]*\).*/\1/p' <<< "$b")
    [ -z "$pos" ] && return 1
    echo $(( ${pos%,*} + ${size%,*} / 2 )) $(( ${pos#*,} + ${size#*,} / 2 ))
}

open_pointer() {
    mark "open: real pointer click on the menu-bar item"
    local c
    c=$(bar_centre) || { say "no bar position"; return 1; }
    # shellcheck disable=SC2086
    tool click $c
    wait_menus 1 4
}

open_menu() { if [ "$POINTER" -eq 1 ]; then open_pointer; else open_ax; fi; }

close_all() {
    local i n
    for i in 1 2 3 4; do
        n=$(menu_windows)
        [ "${n:-0}" -eq 0 ] && [ "$i" -gt 1 ] && break
        key 53 escape
    done
    if [ -n "$opener_pid" ]; then
        for i in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$opener_pid" 2>/dev/null || break; sleep 0.5; done
        kill "$opener_pid" 2>/dev/null && say "opener still running, killed"
        wait "$opener_pid" 2>/dev/null
        opener_pid=""
    fi
    wins closed
}

# nav_to <place> <name>: arrow keys until that row is highlighted (AXSelected).
nav_to() {
    local place=$1 name=$2 r i k
    if [ "$NAV_OK" -ne 1 ]; then say "nav_to skipped (selection unreadable)"; return 1; fi
    for k in 125 126; do
        for ((i = 1; i <= 22; i++)); do
            key "$k" arrow
            r=$(ax selected "$place" | grep '^selected' | tail -n 1)
            [[ "$r" == *"] "[0-9]*" $name" ]] && return 0
            [[ "$r" == *"none" ]] && [ "$i" -ge 3 ] && { NAV_OK=0; say "nav_to: nothing reads as selected"; return 1; }
        done
    done
    say "nav_to $name failed"
    return 1
}

# find_xy <place> <name> [prefix]: prints "index x y" for that row.
find_xy() {
    local cmd=find
    [ "${3:-}" = prefix ] && cmd=findprefix
    ax "$cmd" "$1" "$2" | grep '^found' | tail -n 1 | awk '{print $2, $3, $4}'
}

start_app() {
    PHASE=$1
    shift
    mark "start app $*"
    env "$@" TRIAL_LOG="$LOG" "$APP" >> "$OUT/app-stderr.txt" 2>&1 &
    app_pid=$!
    sleep 4
    ax barpos > /dev/null
}

stop_app() {
    close_all
    mark "stop app"
    kill "$app_pid" 2>/dev/null
    wait "$app_pid" 2>/dev/null
    sleep 1
}

# wait_change <op>: until the app logs a model change with that op (add, rename, remove).
wait_change() {
    local start i
    start=$(wc -l < "$LOG")
    for ((i = 0; i < 40; i++)); do
        tail -n +"$((start + 1))" "$LOG" | grep -q "model change.*op=$1" && { say "saw change op=$1"; return 0; }
        sleep 0.2
    done
    say "no change op=$1 within 8 s"
    return 1
}

############################################################ A: no style modifier, static model
if [[ "$PHASES" == *A* ]]; then
start_app A-plain TRIAL_STYLE=plain
tool preflight
tool where

open_ax
wins A1-open
shot A1-open
ax dump top > /dev/null

mark "A2 keyboard walk: down arrow 22 times, reading the highlighted row each time"
for i in $(seq 1 22); do
    key 125 down
    ax selected top > /dev/null
done
shot A2-after-walk
mark "A2 close"
close_all

open_ax
mark "A3 select Plain submenu by keyboard"
nav_to top "Plain submenu"
wins A3-selected
shot A3-plain-selected
mark "A3 right arrow on Plain submenu"
key 124 right
sleep 0.5
wins A3-after-right
shot A3-plain-right
ax selected "Plain submenu" > /dev/null
ax dump "Plain submenu" > /dev/null
mark "A3 keyboard walk in the submenu: down arrow 8 times"
for i in $(seq 1 8); do
    key 125 down
    ax selected "Plain submenu" > /dev/null
done
shot A3-sub-walk
mark "A3 left arrow closes the submenu"
key 123 left
sleep 0.5
wins A3-after-left
shot A3-after-left
mark "A3 escape the whole menu"
close_all

open_ax
mark "A4 select Desk workhorse by keyboard"
nav_to top "Desk workhorse"
wins A4-selected
shot A4-desk-selected
mark "A4 right arrow on Desk workhorse"
key 124 right
sleep 0.5
wins A4-after-right
shot A4-desk-right
ax dump "Desk workhorse" > /dev/null
mark "A4 left arrow"
key 123 left
sleep 0.5
mark "A4 return on Desk workhorse"
key 36 return
sleep 1
wins A4-after-return
shot A4-desk-return
close_all

open_ax
mark "A5 AXPress on Plain submenu"
ax pressname top "Plain submenu" > /dev/null
sleep 1
wins A5-after
shot A5-ax-plain-submenu
close_all

open_ax
mark "A6 AXPress on Desk workhorse"
ax pressname top "Desk workhorse" > /dev/null
sleep 1
wins A6-after
shot A6-ax-desk
close_all

open_ax
mark "A7 AXPress on Plain text line"
ax pressname top "Plain text line" > /dev/null
sleep 1
wins A7-after
shot A7-ax-text
mark "A7 AXPress on Disabled button"
ax pressname top "Disabled button" > /dev/null
sleep 1
wins A7-after-disabled
close_all

open_ax
mark "A8 open Plain submenu by keyboard, then AXPress Sub button inside it"
nav_to top "Plain submenu"
key 124 right
sleep 0.5
wins A8-sub-open
ax pressname "Plain submenu" "Sub button" > /dev/null
mark "A8 after the press"
sleep 1.5
wins A8-after
shot A8-after-sub-press
close_all

open_ax
mark "A9 open Plain submenu by keyboard, return on Sub button"
nav_to top "Plain submenu"
key 124 right
nav_to "Plain submenu" "Sub button"
mark "A9 return"
key 36 return
sleep 1.5
wins A9-after
close_all

################################ pointer: does the runner let a CGEvent click open the menu?
PHASE=A-plain
open_pointer
n=$(menu_windows)
shot P0-pointer-open
if [ "${n:-0}" -ge 1 ]; then
    POINTER=1
    say "POINTER works: a posted click opened the menu"
else
    say "POINTER does not open the menu (menu windows=${n:-?})"
fi
close_all

if [ "$POINTER" -eq 1 ]; then
    open_pointer
    read -r idx x y <<< "$(find_xy top "Plain submenu")"
    mark "P1 pointer rests on Plain submenu (row $idx)"
    tool move "$x" "$y"
    sleep 1.5
    wins P1-rest
    shot P1-rest-plain-submenu
    ax selected top > /dev/null
    read -r sidx sx sy <<< "$(find_xy "Plain submenu" "Sub button")"
    mark "P2 pointer into the submenu and click Sub button (row $sidx)"
    tool move "$sx" "$y"
    tool click "$sx" "$sy"
    sleep 1.5
    wins P2-after
    shot P2-after-sub-click
    close_all

    open_pointer
    read -r idx x y <<< "$(find_xy top "Desk workhorse")"
    mark "P3 pointer rests on Desk workhorse (row $idx)"
    tool move "$x" "$y"
    sleep 1.5
    wins P3-rest
    shot P3-rest-desk
    ax dump "Desk workhorse" > /dev/null
    mark "P4 pointer clicks Desk workhorse"
    tool click "$x" "$y"
    sleep 1.5
    wins P4-after
    shot P4-after-desk-click
    close_all

    open_pointer
    read -r idx x y <<< "$(find_xy top "Plain text line")"
    mark "P5 pointer rests on Plain text line"
    tool move "$x" "$y"
    sleep 1
    shot P5-rest-text
    ax selected top > /dev/null
    read -r idx x2 y2 <<< "$(find_xy top "Disabled button")"
    mark "P6 pointer rests on Disabled button"
    tool move "$x2" "$y2"
    sleep 1
    shot P6-rest-disabled
    ax selected top > /dev/null
    read -r idx x3 y3 <<< "$(find_xy top "   Indented button")"
    mark "P7 pointer rests on the indented button"
    tool move "$x3" "$y3"
    sleep 1
    shot P7-rest-indented
    ax selected top > /dev/null
    mark "P8 pointer clicks Plain text line"
    tool click "$x" "$y"
    sleep 1
    wins P8-after
    shot P8-after-text-click
    close_all
fi
stop_app
fi

############################################################ B: .menuBarExtraStyle(.menu)
if [[ "$PHASES" == *B* ]]; then
start_app B-menu TRIAL_STYLE=menu
open_menu
wins B1-open
shot B1-open
ax dump top > /dev/null
if [ "$POINTER" -eq 1 ]; then
    read -r idx x y <<< "$(find_xy top "Plain submenu")"
    mark "B2 pointer rests on Plain submenu"
    tool move "$x" "$y"
    sleep 1.5
    wins B2-rest
    shot B2-rest-plain-submenu
    read -r idx x y <<< "$(find_xy top "Desk workhorse")"
    mark "B3 pointer rests on Desk workhorse"
    tool move "$x" "$y"
    sleep 1.5
    wins B3-rest
    shot B3-rest-desk
    mark "B4 pointer clicks Desk workhorse"
    tool click "$x" "$y"
    sleep 1.5
    wins B4-after
    close_all
    open_menu
fi
mark "B5 keyboard: Plain submenu, right arrow"
nav_to top "Plain submenu"
key 124 right
sleep 0.5
wins B5-after-right
shot B5-plain-right
ax dump "Plain submenu" > /dev/null
stop_app
fi

############################################################ C: the model changes every 2 s
# The live submenus sit above the changing rows, so their rows never move under the pointer.
if [[ "$PHASES" == *C* ]]; then
start_app C-live TRIAL_STYLE=plain TRIAL_LIVE=1
open_menu
mark "C1 top level open while the model changes: window samples for 5 s"
tool watch 5 C1
shot C1-a
ax dump top > /dev/null
shot C1-b
close_all

# C2: click the second row of a changing list a set time after a change.
for list in P I; do
    for delay in 50 400 1200; do
        open_menu
        read -r first _ _ <<< "$(find_xy top "$list " prefix)"
        read -r idx x y <<< "$(ax posat top "$((first + 1))" | grep '^found' | tail -n 1 | awk '{print $2, $3, $4}')"
        mark "C2 list $list: click row $idx ($x,$y) $delay ms after the next change"
        tool clickafter "$LOG" "$delay" "$x" "$y"
        sleep 1
        wins "C2-$list-$delay-after"
        close_all
    done
done

# C3: does an open submenu stay open while the model changes?
open_menu
read -r idx x y <<< "$(find_xy top "Live submenu I")"
mark "C3a pointer rests on Live submenu I; window samples for 5 s"
tool move "$x" "$y"
tool watch 5 C3a
shot C3a-sub-open
ax dump "Live submenu I" > /dev/null
close_all

stop_app
fi

############################################################ S: live submenus, reworked after run 2
if [[ "$PHASES" == *S* ]]; then
# A 6-second tick here, so a click can land inside the submenu with no change in between.
start_app S-live TRIAL_STYLE=plain TRIAL_LIVE=1 TRIAL_TICK=6

# S1: the pointer sits inside the open submenu (on its second row) while the model changes.
open_menu
read -r pidx px py <<< "$(find_xy top "Live submenu I")"
read -r _ _ py2 <<< "$(ax posat top "$((pidx - 1))" | grep '^found' | tail -n 1 | awk '{print $2, $3, $4}')"
rowh=$((py - py2))
tool move "$px" "$py"
sleep 0.8
read -r _ sx _ <<< "$(ax posat "Live submenu I" 1 | grep '^found' | tail -n 1 | awk '{print $2, $3, $4}')"
say "S geometry: parent row centre $px,$py, row height $rowh, submenu centre x $sx"
mark "S1 pointer rests on the second row of the open Live submenu I; window samples for 5 s"
tool move "$sx" "$py"
tool move "$sx" "$((py + rowh))"
tool watch 8 S1
shot S1-pointer-in-submenu
close_all

# S2: between two changes, rest on the parent row, move into the submenu and click its second row.
for sub in P I P I; do
    open_menu
    read -r pidx px py <<< "$(find_xy top "Live submenu $sub")"
    mark "S2 Live submenu $sub: after a change, rest on its row, move in, click the submenu's second row"
    tool subclick "$LOG" "$px" "$py" "$rowh"
    sleep 1
    wins "S2-$sub-after"
    close_all
done

stop_app
fi

############################################################ K: keyboard while the model changes
# Keys are posted by trialtool (fast); the menu is opened by AXPress with the pointer parked
# outside, so only the keyboard moves the highlight. The app logs what is highlighted 50 ms and
# 400 ms after every change.
if [[ "$PHASES" == *K* ]]; then
start_app K-live TRIAL_STYLE=plain TRIAL_LIVE=1
tool move 300 400
open_ax
wait_change ""
sleep 0.5
mark "K1 three down arrows 0.5 s after a change (to Plain button), then no keys for 7 s"
tool keys 125 3 250
tool watch 7 K1
ax selected top > /dev/null
shot K1-after-idle
close_all

tool move 300 400
open_ax
wait_change ""
sleep 0.5
mark "K2 two up arrows 0.5 s after a change (to the last I row), then no keys for 7 s"
tool keys 126 2 250
tool watch 7 K2
ax selected top > /dev/null
shot K2-after-idle
close_all

tool move 300 400
open_ax
wait_change ""
sleep 0.3
mark "K3 seven down arrows and a right arrow 0.3 s after a change (into Live submenu P), then no keys for 7 s"
tool keys 125 7 100
tool keys 124 1 100
tool watch 7 K3
ax selected top > /dev/null
ax selected "Live submenu P" > /dev/null
shot K3-after-idle
mark "K4 down arrow, then return 100 ms after the next change"
tool keys 125 1 100
wait_change ""
sleep 0.1
tool keys 36 1 100
sleep 1
wins K4-after
close_all

tool move 300 400
open_ax
wait_change ""
mark "K5 seven down arrows and a right arrow right after a change, return 300 ms later (same tick)"
tool keys 125 7 100
tool keys 124 1 100
tool keys 125 1 100
sleep 0.3
tool keys 36 1 100
sleep 1
wins K5-after
close_all
stop_app
fi

############################################################ E: pointer on rows that do nothing
if [[ "$PHASES" == *E* ]]; then
start_app E-static TRIAL_STYLE=plain
open_menu
for name in "Section header" "Plain text line" "Disabled button"; do
    read -r idx x y <<< "$(find_xy top "$name")"
    mark "E1 pointer rests on top-level row $idx \"$name\""
    tool move "$x" "$y"
    sleep 0.8
    shot "E1-rest-$idx"
    ax selected top > /dev/null
done
read -r idx x y <<< "$(ax posat top 2 | grep '^found' | tail -n 1 | awk '{print $2, $3, $4}')"
mark "E2 pointer rests on the divider (row 2)"
tool move "$x" "$y"
sleep 0.8
shot E2-rest-divider
ax selected top > /dev/null
read -r idx x y <<< "$(find_xy top "Plain submenu")"
tool move "$x" "$y"
sleep 0.8
for name in "Sub section header" "Sub text line" "Sub disabled"; do
    read -r idx sx sy <<< "$(find_xy "Plain submenu" "$name")"
    mark "E3 pointer rests on submenu row $idx \"$name\""
    tool move "$sx" "$y"
    tool move "$sx" "$sy"
    sleep 0.8
    wins "E3-$idx"
    shot "E3-rest-sub-$idx"
    ax selected "Plain submenu" > /dev/null
done
mark "E4 pointer clicks the submenu's Sub section header"
read -r idx sx sy <<< "$(find_xy "Plain submenu" "Sub section header")"
tool click "$sx" "$sy"
sleep 1
wins E4-after
close_all
stop_app
fi

############################################################ D: 11 top-level rows, 12-row submenu
if [[ "$PHASES" == *D* ]]; then
start_app D-eleven TRIAL_LAYOUT=eleven
open_menu
wins D1-open
shot D1-open
ax dump top > /dev/null
mark "D2 open Twelve rows"
if [ "$POINTER" -eq 1 ]; then
    read -r idx x y <<< "$(find_xy top "Twelve rows")"
    tool move "$x" "$y"
    sleep 1.2
else
    nav_to top "Twelve rows"
    key 124 right
    sleep 0.5
fi
wins D2-sub-open
shot D2-twelve
ax dump "Twelve rows" > /dev/null
stop_app
fi

mark "done"
