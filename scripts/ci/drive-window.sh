#!/bin/bash
# CI only (.github/workflows/menu-pictures.yml): starts the debug app with a sample (MACMOSH_SAMPLE_MENU),
# opens the MacMosh window from the menu's Open MacMosh line with posted pointer events (menutool),
# clicks in it, takes pictures, and checks the app's log (main window design, section 8, step 3). It
# moves the pointer and presses keys: never run it on your own Mac. It needs scripts/build-app.sh
# --debug and the built menutool first. Kept apart from drive-menu.sh, which another branch changes;
# the small helpers at the top are copies of that script's.
#
#   MENU_OUT=<folder> scripts/ci/drive-window.sh
#
# What it leaves in MENU_OUT:
#   pictures/<os>-window-<sample>-<nn>-<step>.png   a picture of the window (or the screen) at each step
#   ax/<os>-window-<sample>-<nn>-<step>.txt         the window's elements as the accessibility tree reads them
#   driver.log    every step, menutool's and System Events' answers
#   app-log.txt   the app's own log lines (MenuLog) for the whole run
#   results.tsv   one line per check: PASS, FAIL, DIFFERS (a finding that does not fail the job) or
#                 NOT-SHOWN (the step could not be done, so nothing is known)
#
# The job fails only when the app does not start, the window shows at launch or does not open from the
# menu, a click runs the wrong button or none, or closing the window ends the app or stops the menu
# from opening. How a picture looks never fails it.
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
OUT=${MENU_OUT:?set MENU_OUT to the folder for pictures and logs}
APP=${MENU_APP:-$root/dist/debug/MacMosh.app}
TOOL=${MENU_TOOL:-$root/dist/debug/menutool}
MAX="$here/menu-ax.applescript"
WAX="$here/window-ax.applescript"
LOG="$OUT/driver.log"
RESULTS="$OUT/results.tsv"
mkdir -p "$OUT/pictures" "$OUT/ax"
: > "$RESULTS"
os="macos$(sw_vers -productVersion | cut -d. -f1)"
failures=0
sample=""
shotn=0
app_pid=""
run_since=$(date '+%Y-%m-%d %H:%M:%S')

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

tool() { lim 20 "$TOOL" "$@" 2>&1 | tee -a "$LOG"; }
count() { lim 10 "$TOOL" count 2>/dev/null || echo 0; }

# max <args> / wax <args>: one System Events call on the menu or the window; the answer goes to the
# log and to stdout.
ask() {
    local script=$1 tag=$2 r st
    shift 2
    r=$(lim 50 osascript "$script" "$@" 2>&1)
    st=$?
    printf '%s\n' "$r" | sed "s/^/$(now) ${tag}[$1] /" >> "$LOG"
    [ "$st" -ne 0 ] && say "${tag}[$1] exit=$st"
    printf '%s\n' "$r"
}
max() { ask "$MAX" max "$@"; }
wax() { ask "$WAX" wax "$@"; }

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

# wait_menus <want> <seconds>: until at least <want> menu windows are on screen (0: until none).
wait_menus() {
    local want=$1 deadline n
    deadline=$(($(date +%s) + $2))
    while :; do
        n=$(count)
        if [ "$want" -eq 0 ]; then [ "$n" -eq 0 ] && break; else [ "$n" -ge "$want" ] && break; fi
        [ "$(date +%s)" -ge "$deadline" ] && break
        sleep 0.2
    done
    echo "$n"
}

# windows: how many windows called MacMosh the app has now.
windows() { wax windows | sed -n 's/^windows \([0-9]*\).*/\1/p' | tail -n 1; }

# wait_windows <want> <seconds>: until the app has that many MacMosh windows; prints how many it has.
wait_windows() {
    local deadline=$((SECONDS + $2)) n
    while :; do
        n=$(windows)
        [ "${n:-0}" -eq "$1" ] && break
        [ "$SECONDS" -ge "$deadline" ] && break
        sleep 0.5
    done
    echo "${n:-0}"
}

# snap <step>: a picture of the window (of the whole screen when it has none) and its elements.
snap() {
    shotn=$((shotn + 1))
    local name frame
    name=$(printf '%s-window-%s-%02d-%s' "$os" "$sample" "$shotn" "$1")
    frame=$(wax frame | sed -n 's/^frame \([0-9-]*\) \([0-9-]*\) \([0-9]*\) \([0-9]*\)$/\1,\2,\3,\4/p' | tail -n 1)
    if [ -n "$frame" ]; then
        lim 15 screencapture -x -R "$frame" "$OUT/pictures/$name.png" >> "$LOG" 2>&1 || say "screencapture failed for $name"
        wax dump > "$OUT/ax/$name.txt"
    else
        lim 15 screencapture -x "$OUT/pictures/$name.png" >> "$LOG" 2>&1 || say "screencapture failed for $name"
    fi
    say "picture $name.png"
}

bar_centre() {
    local b pos size
    b=$(max barpos | grep '^bar' | tail -n 1)
    pos=$(sed -n 's/.*pos=\([0-9-]*,[0-9-]*\).*/\1/p' <<< "$b")
    size=$(sed -n 's/.*size=\([0-9-]*,[0-9-]*\).*/\1/p' <<< "$b")
    [ -z "$pos" ] || [ -z "$size" ] && return 1
    echo "$((${pos%,*} + ${size%,*} / 2)) $((${pos#*,} + ${size#*,} / 2))"
}

# open_menu: a posted click on the menu-bar item; true when a menu window shows.
open_menu() {
    local c n
    c=$(bar_centre) || { say "no position for the menu-bar item"; return 1; }
    say "open the menu: click on the menu-bar item at $c"
    # shellcheck disable=SC2086
    tool click $c > /dev/null
    n=$(wait_menus 1 6)
    [ "$n" -ge 1 ]
}

close_menu() {
    local _
    for _ in 1 2 3; do
        [ "$(count)" -eq 0 ] && return 0
        tool keys 53 1 300 > /dev/null
    done
}

# start_app <sample>: true once the app has logged that it shows the sample and has checked once. Also
# checks that the window did not open at launch.
start_app() {
    sample=$1
    shotn=0
    local since support n
    since=$(moment)
    support=$(mktemp -d)
    say "== $sample: start the app"
    env MACMOSH_SAMPLE_MENU="$sample" MACMOSH_SUPPORT_DIR="$support" "$APP/Contents/MacOS/MacMosh" \
        >> "$OUT/app-stderr.txt" 2>&1 &
    app_pid=$!
    if ! wait_log "$since" "sample menu: $sample" 25 || ! kill -0 "$app_pid" 2>/dev/null; then
        result FAIL "the app starts" "no 'sample menu: $sample' line, or the process ended"
        stop_app
        return 1
    fi
    wait_log "$since" "menu refreshed" 15 > /dev/null || true
    sleep 2
    result PASS "the app starts" "pid $app_pid"
    n=$(windows)
    if applog "$since" | grep -qF "window opened" || [ "${n:-0}" -ne 0 ]; then
        result FAIL "the window does not open at launch" "windows=${n:-?}; log: $(applog "$since" | grep -cF "window opened") 'window opened' line(s)"
    else
        result PASS "the window does not open at launch" "no MacMosh window, no 'window opened' line"
    fi
}

stop_app() {
    close_menu
    [ -n "$app_pid" ] && kill "$app_pid" 2>/dev/null
    [ -n "$app_pid" ] && wait "$app_pid" 2>/dev/null
    app_pid=""
    sleep 1
}

# open_window: opens the menu, clicks Open MacMosh, and checks that the window opened and the log says
# so. Then clicks the window's title bar, so the clicks that follow land in a key window.
open_window() {
    local since idx x y name n frame fx fy fw
    if ! open_menu; then
        result FAIL "the menu opens" "no menu window within 6 s of the click"
        return 1
    fi
    read -r idx x y name <<< "$(max find top "Open MacMosh" | grep '^found' | tail -n 1 | cut -d' ' -f2-)"
    if [ -z "${y:-}" ]; then
        result FAIL "the window opens from Open MacMosh" "no Open MacMosh line in the menu"
        close_menu
        return 1
    fi
    since=$(moment)
    say "click on line $idx [$name] at $x,$y"
    tool click "$x" "$y" > /dev/null
    n=$(wait_windows 1 10)
    if wait_log "$since" "window opened" 10 && [ "$n" -ge 1 ]; then
        result PASS "the window opens from Open MacMosh" "windows=$n; log: window opened"
    else
        result FAIL "the window opens from Open MacMosh" "windows=$n; 'window opened' in the log: $(applog "$since" | grep -cF "window opened")"
        return 1
    fi
    sleep 1.5
    frame=$(wax frame | grep '^frame' | tail -n 1)
    read -r _ fx fy fw _ <<< "$frame"
    if [ -n "${fw:-}" ]; then
        say "click on the window's title bar at $((fx + fw / 2)),$((fy + 12))"
        tool click "$((fx + fw / 2))" "$((fy + 12))" > /dev/null
        sleep 0.5
    fi
}

# click_id <identifier>: a posted click on the centre of the window's element with that identifier.
click_id() {
    local found x y
    found=$(wax find "$1" | grep '^found' | tail -n 1)
    read -r _ x y _ <<< "$found"
    if [ -z "${y:-}" ]; then
        say "no element [$1] in the window"
        return 1
    fi
    say "click on [$1] at $x,$y"
    tool click "$x" "$y" > /dev/null
}

# expect_ran <check> <moment> <words>: the app's log since then names exactly that window button's action.
expect_ran() {
    local ran
    wait_log "$2" "sample window ran: " 10 > /dev/null
    sleep 1
    ran=$(applog "$2" | grep -F "sample window ran: " | sed 's/.*sample window ran: //' | tr '\n' '|' | sed 's/|$//')
    if [ -z "$ran" ]; then
        result FAIL "$1" "nothing ran (expected $3)"
    elif [ "$ran" = "$3" ]; then
        result PASS "$1" "the log says: sample window ran: $ran"
    else
        result FAIL "$1" "expected [$3], the log says: $ran"
    fi
}

############################################################ the samples
six_desks() {
    local since n t
    start_app six-desks || return
    if ! open_window; then stop_app; return; fi
    snap window

    # A click on a desk's row (its name, not its button) opens the detail strip under it.
    if click_id "desk.website"; then
        sleep 1
        t=$(wax text "Starts with" | grep '^text' | tail -n 1)
        if [ -n "$t" ] && wax find "desk.website.strip" | grep -q '^found'; then
            result PASS "a click on a desk's row opens its detail strip" "website's strip is there, with Starts with"
        else
            result DIFFERS "a click on a desk's row opens its detail strip" "no strip found for website"
        fi
        snap detail-strip
    else
        result NOT-SHOWN "a click on a desk's row opens its detail strip" "no row for website"
    fi

    # A desk's Open button runs that desk's connect, as the menu's line does.
    since=$(moment)
    if click_id "desk.api.open"; then
        expect_ran "a click on a desk's Open runs that desk" "$since" "tab connect workhorse api"
    else
        result FAIL "a click on a desk's Open runs that desk" "no Open button for api"
    fi
    sleep 1

    # Open the 2 not in a tab: one connect tab for each desk with none.
    since=$(moment)
    if click_id "button.openAllWithoutTab"; then
        expect_ran "Open the 2 not in a tab runs one connect for each" "$since" \
            "tabs connect workhorse api connect workhorse blog"
    else
        result NOT-SHOWN "Open the 2 not in a tab runs one connect for each" "no such button"
    fi
    sleep 1
    snap after-clicks

    # Closing the window keeps the app and its menu.
    local close cx cy
    close=$(wax close | grep '^close' | tail -n 1)
    read -r _ cx cy <<< "$close"
    if [ -z "${cy:-}" ]; then
        result NOT-SHOWN "closing the window keeps the app running" "no close button found"
        stop_app
        return
    fi
    say "click on the close button at $cx,$cy"
    tool click "$cx" "$cy" > /dev/null
    n=$(wait_windows 0 5)
    if [ "$n" -eq 0 ]; then
        result PASS "the close button closes the window" "windows=0"
    else
        result DIFFERS "the close button closes the window" "windows=$n"
    fi
    sleep 2
    if kill -0 "$app_pid" 2>/dev/null; then
        result PASS "closing the window keeps the app running" "pid $app_pid still there"
    else
        result FAIL "closing the window keeps the app running" "the app ended"
        app_pid=""
        return
    fi
    if open_menu; then
        result PASS "the menu still opens after the window closed" "menu windows=$(count)"
        snap menu-after-close
        close_menu
    else
        result FAIL "the menu still opens after the window closed" "no menu window within 6 s of the click"
    fi
    stop_app
}

ready_then_locked() {
    local since t
    since=$(moment)
    start_app ready-then-locked || return
    if wait_log "$since" "symbol=lock.circle" 15; then
        result PASS "the sample turns Locked" "log: menu refreshed with lock.circle"
    else
        result NOT-SHOWN "the sample turns Locked" "no lock.circle refresh"
    fi
    if ! open_window; then stop_app; return; fi
    sleep 1
    t=$(wax text "Desks before the restart" | grep '^text' | tail -n 1)
    if [ -n "$t" ]; then
        result PASS "a Locked workhorse shows its last Ready desks, greyed" "${t#text }"
    else
        result DIFFERS "a Locked workhorse shows its last Ready desks, greyed" "no 'Desks before the restart' heading"
    fi
    snap locked
    stop_app
}

two_workhorses() {
    local v
    start_app two-workhorses || return
    if ! open_window; then stop_app; return; fi
    snap first-workhorse
    if click_id "sidebar.spare"; then
        sleep 1.5
        v=$(wax value "page.headline" | grep '^value' | tail -n 1)
        if [ "${v#value }" = "Spare · Locked after a restart" ]; then
            result PASS "a click on the second workhorse shows its page" "${v#value }"
        else
            result DIFFERS "a click on the second workhorse shows its page" "headline: ${v:-none}"
        fi
        snap second-workhorse
    else
        result NOT-SHOWN "a click on the second workhorse shows its page" "no sidebar row for Spare"
    fi
    stop_app
}

no_workhorses() {
    start_app no-workhorses || return
    if ! open_window; then stop_app; return; fi
    if wax find "page.addMac" | grep -q '^found'; then
        result PASS "with no workhorse the Add a Mac page is shown" "page.addMac found"
    else
        result DIFFERS "with no workhorse the Add a Mac page is shown" "page.addMac not found"
    fi
    snap add-a-mac
    stop_app
}

############################################################ the run
say "driving the window of $APP on $os ($(sw_vers -productVersion))"
tool preflight > /dev/null
lim 10 "$TOOL" move 600 500 > /dev/null

six_desks
ready_then_locked
two_workhorses
no_workhorses

applog "$run_since" > "$OUT/app-log.txt"
sample=""
say "done: $failures failed check(s)"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    {
        echo "### Window pictures on $os"
        echo
        echo "| result | sample | check | detail |"
        echo "|---|---|---|---|"
        awk -F '\t' '{ printf "| %s | %s | %s | %s |\n", $1, $3, $4, $5 }' "$RESULTS"
    } >> "$GITHUB_STEP_SUMMARY"
fi
cat "$RESULTS"
[ "$failures" -eq 0 ]
