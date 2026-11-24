#!/bin/bash
# CI only (.github/workflows/menu-pictures.yml): starts the debug app with a sample (MACMOSH_SAMPLE_MENU),
# opens the MacMosh window from the menu's Open MacMosh line with posted pointer events (menutool),
# clicks in it, takes pictures, and checks the app's log (main window design, section 8, step 3). It
# moves the pointer and presses keys: never run it on your own Mac. It needs scripts/build-app.sh
# --debug and the built menutool and windowtool first. Kept apart from drive-menu.sh, which another branch changes;
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
# menu, a click runs the wrong button or none, closing the window ends the app or stops the menu from
# opening, or, in the "windows" sample (issue #134), a desk's details do not list its windows, a window's
# button does not run the menu's action for that window, or a desk whose tab can be found opens a tab
# instead of going to it. How a picture looks never fails it.
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
OUT=${MENU_OUT:?set MENU_OUT to the folder for pictures and logs}
APP=${MENU_APP:-$root/dist/debug/MacMosh.app}
TOOL=${MENU_TOOL:-$root/dist/debug/menutool}
MAX="$here/menu-ax.applescript"
WTOOL=${WINDOW_TOOL:-$root/dist/debug/windowtool}
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

# max <args>: one System Events call on the menu (menu-ax.applescript). wax <args>: one read of the
# window through the accessibility API (windowtool), for the app started last. Each answer goes to the
# log and to stdout; a dump goes to the log by its first line only.
max() {
    local r st
    r=$(lim 50 osascript "$MAX" "$@" 2>&1)
    st=$?
    printf '%s\n' "$r" | sed "s/^/$(now) max[$1] /" >> "$LOG"
    [ "$st" -ne 0 ] && say "max[$1] exit=$st"
    printf '%s\n' "$r"
}
wax() {
    local r st
    if [ -z "$app_pid" ]; then echo "noapp"; return; fi
    r=$(lim 20 "$WTOOL" "$app_pid" "$@" 2>&1)
    st=$?
    printf '%s\n' "$r" | head -n 1 | sed "s/^/$(now) wax[$1] /" >> "$LOG"
    [ "$st" -ne 0 ] && say "wax[$1] exit=$st"
    printf '%s\n' "$r"
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

# snap_screen <step>: a picture of the whole screen, for what is drawn past the window's edge (a help tag).
snap_screen() {
    shotn=$((shotn + 1))
    local name
    name=$(printf '%s-window-%s-%02d-%s' "$os" "$sample" "$shotn" "$1")
    lim 15 screencapture -x "$OUT/pictures/$name.png" >> "$LOG" 2>&1 || say "screencapture failed for $name"
    say "picture $name.png (the whole screen)"
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
    # Whether Open MacMosh brought the app forward with its window focused, before any click in it:
    # Apple says activate() is only a request (design, section 11). A finding, never a failure.
    local front
    front=$(wax front | grep '^front' | tail -n 1)
    if [ "$front" = "front active=true focused=MacMosh" ]; then
        result PASS "Open MacMosh brings the app forward with its window focused" "$front"
    else
        result DIFFERS "Open MacMosh brings the app forward with its window focused" "${front:-no answer}"
    fi
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

    # A desk's row is a button, so the keyboard and VoiceOver can open its strip too. A finding only.
    local role
    role=$(wax find "desk.website" | grep '^found' | tail -n 1 | awk '{ print $NF }')
    if [ "$role" = "AXButton" ]; then
        result PASS "a desk's row is a button" "desk.website is $role"
    else
        result DIFFERS "a desk's row is a button" "desk.website is ${role:-not found}"
    fi

    # A click on a desk's row (its name, not its button) opens the detail strip under it.
    if click_id "desk.website"; then
        sleep 1
        t=$(wax text "Starts with" | grep '^text' | tail -n 1)
        if [ -n "$t" ] && wax find "desk.website.strip" | grep -q '^found'; then
            result PASS "a click on a desk's row opens its detail strip" "website's strip is there, with Starts with"
        else
            result FAIL "a click on a desk's row opens its detail strip" "no strip found for website"
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
        result FAIL "Open the 2 not in a tab runs one connect for each" "no such button: the sample must have it"
    fi
    sleep 1

    # Check now asks for a check, through the same path as the menu's line.
    since=$(moment)
    if click_id "button.checkNow"; then
        expect_ran "Check now asks for a check" "$since" "refresh"
    else
        result FAIL "Check now asks for a check" "no Check now button: the sample must have it"
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
        # Nothing after this would test a closed window, so the checks that follow are not shown.
        result FAIL "the close button closes the window" "windows=$n after the click"
        result NOT-SHOWN "closing the window keeps the app running" "the window did not close"
        result NOT-SHOWN "the menu still opens after the window closed" "the window did not close"
        stop_app
        return
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

# A desk with a long folder that is kept and doesn't come back, and a desk made by hand: a picture of
# their second lines, which wrap rather than cut the facts, and of the hand-made desk's strip.
long_folder() {
    local t
    start_app long-folder || return
    if ! open_window; then stop_app; return; fi
    # The row is a button, so its texts come as one label: the name, the windows, then the second line.
    t=$(wax value "desk.website-redesign" | grep '^value' | tail -n 1)
    if [[ "$t" == *"Kept when it exits"*"Doesn't come back after a restart"* ]]; then
        result PASS "a long folder's row still shows its facts" "${t#value }"
    else
        result DIFFERS "a long folder's row still shows its facts" "the row reads: ${t:-not found}"
    fi
    snap long-folder
    if click_id "desk.notes"; then
        sleep 1
        if wax find "desk.notes.strip" | grep -q '^found'; then
            result PASS "a click on a hand-made desk's row opens its strip" "notes' strip is there"
        else
            result FAIL "a click on a hand-made desk's row opens its strip" "no strip found for notes"
        fi
        snap hand-made-strip
    else
        result NOT-SHOWN "a click on a hand-made desk's row opens its strip" "no row for notes"
    fi
    stop_app
}

# no_tab_opened <check> <moment>: since then the app brought a tab forward and opened none (the sample's
# stand-in opener writes one line for each).
no_tab_opened() {
    local log
    log=$(applog "$2")
    if grep -qF "sample: no tab brought forward" <<< "$log" && ! grep -qF "sample: no tab opened" <<< "$log"; then
        result PASS "$1" "the log says: sample: no tab brought forward; no 'sample: no tab opened'"
    else
        result FAIL "$1" "brought forward: $(grep -cF "sample: no tab brought forward" <<< "$log"), opened: $(grep -cF "sample: no tab opened" <<< "$log")"
    fi
}

# The "windows" sample (issue #134): the menu's sample with window details and stand-in tab records. A desk's
# Open button goes to its tab when this Mac can find it, and a desk's details list its windows with the
# menu's words and actions. website: claude in a tab this Mac can find, zsh in one it can't, vim in none;
# notes: one window in a findable tab; api: two windows, no tab; blog: one, no tab; shop: web in two
# findable tabs, a second web in none; garden: closed.
windows_sample() {
    local since v t line missing
    start_app windows || return
    if ! open_window; then stop_app; return; fi
    sleep 1
    v=$(wax value "desk.notes.open" | grep '^value' | tail -n 1)
    if [ "${v#value }" = "Go to" ]; then
        result PASS "a desk whose tab can be found has Go to" "desk.notes.open reads ${v#value }"
    else
        result DIFFERS "a desk whose tab can be found has Go to" "desk.notes.open reads ${v:-nothing}"
    fi
    v=$(wax value "button.openAllWithoutTab" | grep '^value' | tail -n 1)
    if [ "${v#value }" = "Open the 5 not in a tab" ]; then
        result PASS "Open the N not in a tab counts the windows with no tab" "${v#value }"
    else
        result DIFFERS "Open the N not in a tab counts the windows with no tab" "the button reads ${v:-nothing}"
    fi
    snap page

    # The row's button keeps the menu's words for its click as its help tag: a picture with the pointer
    # resting on website's Open, which opens the 1 window not in a tab. A picture only, never a failure.
    local x y
    read -r _ x y _ <<< "$(wax find "desk.website.open" | grep '^found' | tail -n 1)"
    if [ -n "${y:-}" ]; then
        say "rest the pointer on website's Open at $x,$y"
        lim 10 "$TOOL" move "$x" "$y" >> "$LOG" 2>&1
        sleep 3
        snap_screen help-tag
        lim 10 "$TOOL" move 600 500 >> "$LOG" 2>&1
        sleep 0.5
    else
        result NOT-SHOWN "the row's button has the menu's words as its help tag" "no Open button for website"
    fi

    # website's details list its three windows with the menu's words, each with its own button.
    if click_id "desk.website"; then
        sleep 1
        missing=""
        for line in "claude (in a tab)" "zsh (open in another tab)" "vim"; do
            t=$(wax text "$line" | grep '^text' | tail -n 1)
            [ "${t#text }" = "$line" ] || missing="$missing [$line]"
        done
        for line in "@1" "@2" "@3"; do
            wax find "desk.website.win.$line" | grep -q '^found' || missing="$missing [button $line]"
        done
        if [ -z "$missing" ]; then
            result PASS "a desk's details list its windows" "website: claude (in a tab), zsh (open in another tab), vim, each with a button"
        else
            result FAIL "a desk's details list its windows" "missing:$missing"
        fi
        v=$(wax value "desk.website.win.@1" | grep '^value' | tail -n 1)
        [ "${v#value }" = "Go to" ] || result DIFFERS "a window in a findable tab has Go to" "desk.website.win.@1 reads ${v:-nothing}"
        snap website-windows
    else
        result FAIL "a desk's details list its windows" "no row for website"
    fi

    # A window's button runs the menu's action for that window: vim has no tab, so a tab on it.
    since=$(moment)
    if click_id "desk.website.win.@3"; then
        expect_ran "a window's button runs that window's action (no tab)" "$since" "tab connect workhorse website --window @3"
    else
        result FAIL "a window's button runs that window's action (no tab)" "no button for vim"
    fi
    sleep 1
    # claude is in a tab this Mac can find: going to it, not a new tab.
    since=$(moment)
    if click_id "desk.website.win.@1"; then
        expect_ran "a window's button runs that window's action (its tab)" "$since" \
            "focus 5a3c9e1f7b2d4c60 connect workhorse website --window @1"
        no_tab_opened "a window in a findable tab is brought forward, no tab opened" "$since"
    else
        result FAIL "a window's button runs that window's action (its tab)" "no button for claude"
    fi
    sleep 1

    # notes' tab can be found: its Open button goes to it and opens no new tab.
    since=$(moment)
    if click_id "desk.notes.open"; then
        expect_ran "a desk's button goes to its tab when it can be found" "$since" \
            "focus 8e1f2a3b4c5d6e70 connect workhorse notes --window @7"
        no_tab_opened "a desk whose tab can be found is brought forward, no tab opened" "$since"
    else
        result FAIL "a desk's button goes to its tab when it can be found" "no Open button for notes"
    fi
    sleep 1

    # Open the 5 not in a tab: a tab on each window with none, desk by desk in the board's order.
    since=$(moment)
    if click_id "button.openAllWithoutTab"; then
        expect_ran "Open the N not in a tab opens each window with no tab" "$since" \
            "tabs connect workhorse api --window @5 connect workhorse api --window @6 connect workhorse blog --window @8 connect workhorse shop --window @10 connect workhorse website --window @3"
    else
        result FAIL "Open the N not in a tab opens each window with no tab" "no such button: the sample must have it"
    fi
    sleep 1
    snap after-clicks
    stop_app
}

# The saved list can't be read: the window says what the menu says, not Add a Mac.
unreadable_list() {
    start_app unreadable-list || return
    if ! open_window; then stop_app; return; fi
    if wax find "page.listProblem" | grep -q '^found' && ! wax find "page.addMac" | grep -q '^found'; then
        result PASS "an unreadable list shows the menu's sentence, not Add a Mac" "page.listProblem found"
    else
        result DIFFERS "an unreadable list shows the menu's sentence, not Add a Mac" "page.listProblem not found, or page.addMac found"
    fi
    snap unreadable-list
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
windows_sample
ready_then_locked
two_workhorses
long_folder
unreadable_list
no_workhorses

applog "$run_since" > "$OUT/app-log.txt"
# Any crash report of the app from this job, the menu's step included.
mkdir -p "$OUT/crashes"
find "$HOME/Library/Logs/DiagnosticReports" -name 'MacMosh*' -newermt "$run_since" -exec cp {} "$OUT/crashes/" \; 2>/dev/null
find "$HOME/Library/Logs/DiagnosticReports" -name 'MacMosh*' -exec cp {} "$OUT/crashes/" \; 2>/dev/null
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
