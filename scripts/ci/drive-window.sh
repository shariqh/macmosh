#!/bin/bash
# CI only (.github/workflows/menu-pictures.yml): starts the debug app with a sample (MACMOSH_SAMPLE_MENU),
# opens the MacMosh window from the menu's Open MacMosh line with posted pointer events (menutool),
# clicks in it, takes pictures, and checks the app's log (main window design, section 8, step 3). It
# moves the pointer and presses keys: never run it on your own Mac. It needs scripts/build-app.sh
# --debug and the built menutool and windowtool first. Kept apart from drive-menu.sh, which another branch changes;
# the small helpers at the top are copies of that script's.
#
#   MENU_OUT=<folder> [WINDOW_APPEARANCE=dark] scripts/ci/drive-window.sh
#
# The workflow runs it twice per macOS version: in the "pictures" job in light, after the menu, and in the
# "window-dark" job with WINDOW_APPEARANCE=dark, after the job has switched the runner to dark (look step 1). In dark
# every name carries "-dark" after the version ("macos15-dark"), so pictures and results say which they are. Both
# jobs turn on keyboard navigation first, for the Tab check.
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
# instead of going to it. In the "window-forms" sample (step 4) it fails when New desk…, Rename… or Remove… does
# not open its form, a form does not refuse a taken name, a form's button does not send its exact arguments to
# the stand-in ssh, or the page does not say what happened. It fails when a name that starts with a dash is not
# refused, when Command-V, Command-A and Command-C, Command-X, Command-Z or Shift-Command-Z does not do its job in a
# form's text field, when Command-W closes anything with a form or the menu open, does not close the window
# without them, ends the app or stops the menu from opening, or when one of these keys sets off the menu-open
# signal (issue #147). How a picture looks never fails it.
# Naming a window (issue 144) fails when a desk's details lack their Name… buttons or Name its window…, the
# sheet does not open, refuse a name or name its window, Name or Use its program's name does not send its exact
# arguments, or the row does not show the name after the check.
# The Settings page (issue 157, the "window-settings" sample) fails as settings_sample says.
# Look step 1 adds two checks to the "six-desks" sample: Tab moves keyboard focus across the page's buttons (it fails
# when Check now, New desk… or a desk's Open is never reached in 25 presses of Tab, or a press sets off the menu-open
# signal), and a picture of the window at its smallest, 700 by 440 (DIFFERS when the window is not 700 wide). In the
# "long-folder" sample it fails when the row of a desk with a 45-character name does not read that name whole.
# A new desk's first window (issue 163) fails when the New desk form's "Same name as the desk" box is not there and
# ticked at script 0.12.0, clearing it does not show the field and its line, a bad name is not refused with the
# rule's sentence, Make desk does not send exactly the window's name (the desk's, its own, or none), or the new
# desk's row does not show that name after the check; and, in the "window-forms-0.11" sample, when the form shows the
# line or sends anything about the window to an older script.
# Look step 2 (issue 174) reads a window's line in a desk's details as two static texts, its name
# (desk.<desk>.line.<id>) and its state (desk.<desk>.state.<id>): "a desk's details list its windows" fails when
# website's three lines do not read claude, zsh and vim with "in a tab", "open in another tab" and "not in a tab", and
# "the details show the window's new name whole" reads the line and the state of window @6. New checks: "the facts sit
# beside the window lines" at the default size, and, at the smallest window with the page scrolled to its end, "below
# 620 points of page the facts go under the window lines" and "at the smallest window Remove… stays in the window"
# (each fails); "the unreadable-list page has its heading, the sentence and the next step" (fails); and three
# findings that never fail: "VoiceOver hears that a desk's details are open" (windowtool isselected), "at the smallest
# window the opened details can be scrolled into view" (menutool scroll, whose sign is tried both ways), and "Forget
# stands apart at the right of its row". In the "window-names" sample, website's vim is then named with 32 letters,
# and "a 32-letter window name reaches the field", "a 32-letter window name leaves the facts their width" (narrower
# facts than with "vim", or facts past the panel or over the lines) and "a 32-letter window name ends before its
# state" each fail.
# Look step 3 (issue 178) makes the sidebar a column of buttons, one per row, each keeping its identifier
# (sidebar.<id>, sidebar.addMac, sidebar.settings) and read as its name and second line. The Tab check takes up to 40
# presses (25 before: the sidebar's rows join the ring) and also fails when the sidebar's three rows of the "six-desks"
# sample are never reached; it pictures the focus on the first, and "after the sidebar Tab goes to the page" (a
# finding) names the stop after Settings. "a desk row whose details are closed is not selected" reads api's row while
# website's details are open (FAIL when it reads selected). In the "windows" sample, "a window in two tabs and a
# repeated name read as the menu's facts" opens shop's details (FAIL). In the "no-workhorses" sample, "the Add a Mac
# page reads its title and today's two settings" and "at the smallest window Add a Mac… stays in the window" fail, and
# a picture shows the page at its smallest. A new "window-sidebar" sample (five Macs in five states) fails when a row is
# not a button with its words, when the chosen row is not the one selected, or when a click on a row does not show its
# page; "Tab and Space choose a Mac in the sidebar" is a finding, and a menu-open signal from them fails. The pointer
# rests on the title bar before the pictures of the details at the smallest window, where a help tag showed.
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
# light, or dark in the window-dark job, which switched the runner to dark before this started.
appearance=${WINDOW_APPEARANCE:-light}
[ "$appearance" = dark ] && os="$os-dark"
failures=0
sample=""
shotn=0
app_pid=""
settings_since=""
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
        # The row's button carries the selected trait while its details are open (look step 2). Unproven (design 15):
        # what the trait reads as through the accessibility API on each macOS version is what this records.
        t=$(wax isselected "desk.website" | grep -E '^(isselected|notfound)' | tail -n 1)
        if [ "$t" = "isselected true" ]; then
            result PASS "VoiceOver hears that a desk's details are open" "desk.website: $t"
        else
            result DIFFERS "VoiceOver hears that a desk's details are open" "desk.website: ${t:-no answer}"
        fi
        # A row whose details are closed is not selected (look step 3): false, or no attribute at all as a finding.
        t=$(wax isselected "desk.api" | grep -E '^(isselected|notfound)' | tail -n 1)
        case "$t" in
            "isselected false") result PASS "a desk row whose details are closed is not selected" "desk.api: $t" ;;
            "isselected none") result DIFFERS "a desk row whose details are closed is not selected" "desk.api: $t" ;;
            *) result FAIL "a desk row whose details are closed is not selected" "desk.api: ${t:-no answer}" ;;
        esac
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

    tab_check
    smallest_window

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

# The Tab check (look step 1): with keyboard navigation on (the workflow turns it on), Tab moves keyboard focus across
# the page's buttons as it does across stock buttons. Up to 40 presses of Tab (look step 3; 25 before, when the sidebar
# was one stop), reading the focused element after each; it passes once Check now, New desk… and a desk's Open have
# each had focus. Look step 3: the sidebar's rows join the ring, and "Tab moves focus through the sidebar's rows" fails
# when Workhorse, Add a Mac… and Settings are not all reached; the stop after Settings is a finding. The loop stops
# early only when all six have been seen and the stop after Settings is known. Pictures show the focus on Check now, on
# New desk… and on the sidebar's first row, for the focus ring. A press that sets off the menu-open signal fails it.
tab_check() {
    local since seen="" f id i prev="" after_settings="" shot_check="" shot_new="" shot_sidebar=""
    since=$(moment)
    for i in $(seq 1 40); do
        tool keys 48 1 150 > /dev/null
        sleep 0.3
        f=$(wax focused | grep '^focused' | tail -n 1)
        id=$(awk '{ print $2 }' <<< "$f")
        say "Tab $i: ${f:-no answer}"
        seen="$seen ${id:-?}"
        if [ "$prev" = "sidebar.settings" ] && [ -z "$after_settings" ]; then after_settings=${id:-?}; fi
        prev=$id
        if [ "$id" = "button.checkNow" ] && [ -z "$shot_check" ]; then snap focus-check-now; shot_check=1; fi
        if [ "$id" = "button.newDesk" ] && [ -z "$shot_new" ]; then snap focus-new-desk; shot_new=1; fi
        if [ "$id" = "sidebar.workhorse" ] && [ -z "$shot_sidebar" ]; then snap focus-sidebar; shot_sidebar=1; fi
        if [[ " $seen " == *" button.checkNow "* && " $seen " == *" button.newDesk "* && " $seen " == *" desk.website.open "* \
              && " $seen " == *" sidebar.workhorse "* && " $seen " == *" sidebar.addMac "* && " $seen " == *" sidebar.settings "* ]] \
           && [ -n "$after_settings" ]; then
            break
        fi
    done
    if [[ " $seen " == *" button.checkNow "* && " $seen " == *" button.newDesk "* && " $seen " == *" desk.website.open "* ]]; then
        result PASS "Tab moves focus across the page's buttons" "focus went to:$seen"
    else
        result FAIL "Tab moves focus across the page's buttons" "Check now, New desk… and website's Open not all reached; focus went to:$seen"
    fi
    if [[ " $seen " == *" sidebar.workhorse "* && " $seen " == *" sidebar.addMac "* && " $seen " == *" sidebar.settings "* ]]; then
        result PASS "Tab moves focus through the sidebar's rows" "focus went to:$seen"
    else
        result FAIL "Tab moves focus through the sidebar's rows" "Workhorse, Add a Mac… and Settings not all reached; focus went to:$seen"
    fi
    if [ "$after_settings" = "button.checkNow" ]; then
        result PASS "after the sidebar Tab goes to the page" "the stop after sidebar.settings is $after_settings"
    else
        result DIFFERS "after the sidebar Tab goes to the page" "the stop after sidebar.settings is ${after_settings:-not seen}"
    fi
    f=$(applog "$since" | grep -cE "menu opened|menu tracking")
    result "$([ "$f" -eq 0 ] && echo PASS || echo FAIL)" "Tab sets off no menu-open signal" \
        "$f 'menu opened' or 'menu tracking' line(s) since the first Tab"
}

# The window at its smallest (look step 1): asked for 600 by 300, the window's minimum keeps it at 700 points wide (its
# content is 700 by 440). A picture of it, then the window back at its default size for the steps after.
smallest_window() {
    local s f
    s=$(wax size 600 300 | grep '^size' | tail -n 1)
    sleep 1
    f=$(wax frame | grep '^frame' | tail -n 1)
    if [ "$(awk '{ print $4 }' <<< "$f")" = 700 ]; then
        result PASS "the window's smallest size is 700 wide" "asked for 600 by 300: ${s:-no answer}; ${f:-no frame}"
    else
        result DIFFERS "the window's smallest size is 700 wide" "asked for 600 by 300: ${s:-no answer}; ${f:-no frame}"
    fi
    snap minimum-size
    wax size 880 680 > /dev/null
    sleep 1
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

# The "window-sidebar" sample (look step 3): five Macs in five states. Each sidebar row is a button read as its name
# and second line; the chosen row alone is selected; a click on a row shows its page and moves the selection; Tab then
# Space on a row is a finding, and a menu-open signal from them fails.
sidebar_sample() {
    local entry id want r v missing="" rows since f i seen=""
    rows="sidebar.workhorse sidebar.attic sidebar.spare sidebar.den sidebar.loft sidebar.addMac sidebar.settings"
    start_app window-sidebar || return
    if ! open_window; then stop_app; return; fi
    sleep 1
    for entry in "workhorse|Workhorse, Ready · 6 desks" "attic|Attic, Ready · 1 desk" "spare|Spare, Locked after a restart" \
                 "den|Den, Can't reach it" "loft|Loft, Checking…" "addMac|Add a Mac…" "settings|Settings"; do
        id="sidebar.${entry%%|*}"
        want=${entry#*|}
        r=$(wax find "$id" | grep '^found' | tail -n 1 | awk '{ print $NF }')
        v=$(val "$id")
        if [ "$r" != AXButton ] || [ "$v" != "$want" ]; then missing="$missing [$id: ${r:-not found}, ${v:-nothing}]"; fi
    done
    if [ -z "$missing" ]; then
        result PASS "each sidebar row is a button with its Mac's name and second line" "all seven rows read as expected"
    else
        result FAIL "each sidebar row is a button with its Mac's name and second line" "missing or wrong:$missing"
    fi
    # shellcheck disable=SC2086 # the rows, one word each
    selected_only "the chosen Mac's row is selected, and only it" sidebar.workhorse ${rows#sidebar.workhorse }
    snap sidebar-states
    if click_id "sidebar.spare"; then
        sleep 1.5
        v=$(val "page.headline")
        result "$([ "$v" = "Spare · Locked after a restart" ] && echo PASS || echo FAIL)" "a click on a Mac's row shows its page" \
            "page.headline reads: ${v:-nothing}"
        # shellcheck disable=SC2086 # the rows, one word each
        selected_only "the clicked row is now the selected one" sidebar.spare ${rows/sidebar.spare /}
    else
        result FAIL "a click on a Mac's row shows its page" "no sidebar row for Spare"
    fi
    rest_on_title
    snap spare-chosen
    # Tab to Attic's row, then Space. No Apple page says what Space does on a plain button: a finding.
    since=$(moment)
    id=""
    for i in $(seq 1 40); do
        tool keys 48 1 150 > /dev/null
        sleep 0.3
        f=$(wax focused | grep '^focused' | tail -n 1)
        id=$(awk '{ print $2 }' <<< "$f")
        seen="$seen ${id:-?}"
        [ "$id" = "sidebar.attic" ] && break
    done
    if [ "$id" = "sidebar.attic" ]; then
        tool keys 49 1 150 > /dev/null
        sleep 1.5
        v=$(val "page.headline")
        result "$([ "$v" = "Attic · Ready" ] && echo PASS || echo DIFFERS)" "Tab and Space choose a Mac in the sidebar" \
            "after $i presses of Tab and one of Space page.headline reads: ${v:-nothing}; focus went to:$seen"
    else
        result DIFFERS "Tab and Space choose a Mac in the sidebar" "Tab never reached sidebar.attic in 40 presses; focus went to:$seen"
    fi
    f=$(applog "$since" | grep -cE "menu opened|menu tracking")
    result "$([ "$f" -eq 0 ] && echo PASS || echo FAIL)" "Tab and Space set off no menu-open signal" \
        "$f 'menu opened' or 'menu tracking' line(s) since the first Tab"
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
    # A 45-character name is cut on screen, never wrapped, and read whole.
    local long="garden-planner-for-the-allotment-by-the-river"
    t=$(val "desk.$long")
    if [[ "$t" == "$long, "* ]]; then
        result PASS "a long name's row reads the name whole" "desk.$long reads: $t"
    else
        result FAIL "a long name's row reads the name whole" "desk.$long reads: ${t:-nothing}"
    fi
    snap long-folder
    # A hand-made desk's row keeps today's sentence for VoiceOver, as its hint.
    t=$(wax help "desk.notes" | grep -E '^(help|notfound)' | tail -n 1)
    if [ "${t#help }" = "Not made with MacMosh: folder and restart not known" ]; then
        result PASS "a hand-made desk's row has today's sentence as its hint" "desk.notes: ${t#help }"
    else
        result FAIL "a hand-made desk's row has today's sentence as its hint" "desk.notes: ${t:-nothing}"
    fi
    long_folder_smallest
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

# The long folder at the window's smallest (700 by 440): website-redesign's line, with both facts, wraps inside its
# column, so the row ends before its state cell and Open stays in the window. A picture, then the default size back.
long_folder_smallest() {
    local w s r o f
    wax size 600 300 > /dev/null
    sleep 1
    f=$(wax frame | grep '^frame' | tail -n 1)
    w=$(awk '{ print $2 + $4 }' <<< "$f")
    r=$(right "desk.website-redesign")
    s=$(box "desk.website-redesign.status" | awk 'NF == 4 { print $1 }')
    o=$(right "desk.website-redesign.open")
    if [ -n "$r" ] && [ -n "$s" ] && [ -n "$o" ] && [ "$r" -le "$s" ] && [ "$o" -le "$w" ]; then
        result PASS "at the smallest window a long folder's row ends before its state" \
            "row ends at $r, state starts at $s, Open ends at $o, window ends at $w (${f:-no frame})"
    else
        result FAIL "at the smallest window a long folder's row ends before its state" \
            "row ends at ${r:-?}, state starts at ${s:-?}, Open ends at ${o:-?}, window ends at ${w:-?} (${f:-no frame})"
    fi
    same_end "at the smallest window the long folder's state stands in the column" "website-redesign" "notes"
    snap long-folder-minimum-size
    wax size 880 680 > /dev/null
    sleep 1
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

# The opened details at the default size and at the smallest (look step 2), website's open. At the default size the
# facts sit beside the window lines. At 700 by 440 website, the sample's last row, is below the window's bottom, so the
# page is scrolled to its end with one posted scroll at its middle; the sign that moves it there is not documented, so
# the other is tried when the first did not bring the details into view. Then the facts are read under the lines and
# Remove… inside the window, a picture is taken, the page is scrolled back and the window is set to its default size,
# so the clicks that follow find the page as before.
details_beside_and_under() {
    local l f lb ft rr fx fy fw fh px py try sign="" bottom strip_bottom
    l=$(right "desk.website.lines"); f=$(box "desk.website.facts" | awk 'NF == 4 { print $1 }')
    if [ -n "$l" ] && [ -n "$f" ] && [ "$f" -ge "$l" ]; then
        result PASS "the facts sit beside the window lines" "lines end at $l, facts start at $f"
    else
        result FAIL "the facts sit beside the window lines" "lines end at ${l:-?}, facts start at ${f:-?}"
    fi
    wax size 600 300 > /dev/null
    sleep 1
    read -r _ fx fy fw fh <<< "$(wax frame | grep '^frame' | tail -n 1)"
    if [ -z "${fh:-}" ]; then
        result NOT-SHOWN "at the smallest window the opened details can be scrolled into view" "no frame for the window"
        wax size 880 680 > /dev/null
        sleep 1
        return
    fi
    bottom=$((fy + fh))
    # The page's middle: right of the sidebar (200 points) and its one-point line.
    px=$((fx + 200 + 1 + (fw - 201) / 2)); py=$((fy + fh / 2))
    say "before the scroll: the strip ends at $(box "desk.website.strip" | awk 'NF == 4 { print $2 + $4 }'), the window at $bottom"
    for try in -100 100; do
        tool scroll "$px" "$py" "$try" > /dev/null
        # The pointer leaves the page before a fact's help tag can show (look step 3: one showed in a picture).
        rest_on_title
        strip_bottom=$(box "desk.website.strip" | awk 'NF == 4 { print $2 + $4 }')
        say "scrolled $try at $px,$py: the strip ends at ${strip_bottom:-?}, the window at $bottom"
        if [ -n "$strip_bottom" ] && [ "$strip_bottom" -le "$bottom" ]; then sign=$try; break; fi
    done
    if [ -n "$sign" ]; then
        result PASS "at the smallest window the opened details can be scrolled into view" \
            "a scroll of $sign lines took the page to its end: the strip ends at $strip_bottom, the window at $bottom"
    else
        result DIFFERS "at the smallest window the opened details can be scrolled into view" \
            "after scrolls of -100 and 100 lines the strip ends at ${strip_bottom:-?}, the window at $bottom"
    fi
    lb=$(box "desk.website.lines" | awk 'NF == 4 { print $2 + $4 }'); ft=$(box "desk.website.facts" | awk 'NF == 4 { print $2 }')
    if [ -n "$lb" ] && [ -n "$ft" ] && [ "$ft" -ge "$lb" ]; then
        result PASS "below 620 points of page the facts go under the window lines" "lines end at $lb, facts start at $ft"
    else
        result FAIL "below 620 points of page the facts go under the window lines" "lines end at ${lb:-?}, facts start at ${ft:-?}"
    fi
    rr=$(right "button.remove")
    if [ -n "$rr" ] && [ "$rr" -le $((fx + fw)) ]; then
        result PASS "at the smallest window Remove… stays in the window" "Remove… ends at $rr, the window at $((fx + fw))"
    else
        result FAIL "at the smallest window Remove… stays in the window" "Remove… ends at ${rr:-?}, the window at $((fx + fw))"
    fi
    if [ -n "$sign" ]; then
        # The pointer rested on the page for the scroll, where a fact's help tag would cover the picture: the title
        # bar has none.
        rest_on_title
        snap website-windows-minimum-size
        tool scroll "$px" "$py" "$((-sign))" > /dev/null
        sleep 1
    else
        result NOT-SHOWN "the details stacked at the smallest window, in a picture" \
            "the strip was not in view: lines $(box desk.website.lines), facts $(box desk.website.facts), strip $(box desk.website.strip)"
    fi
    wax size 880 680 > /dev/null
    sleep 1
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

    # website's details list its three windows, each as two static texts, its name and its state (look step 2), each
    # with its own button.
    if click_id "desk.website"; then
        sleep 1
        missing=""
        local entry id want_name want_state r part
        for entry in "@1:claude:in a tab" "@2:zsh:open in another tab" "@3:vim:not in a tab"; do
            id=${entry%%:*}
            want_name=${entry#*:}
            want_state=${want_name#*:}
            want_name=${want_name%%:*}
            v=$(val "desk.website.line.$id")
            [ "$v" = "$want_name" ] || missing="$missing [line $id: ${v:-none}]"
            v=$(val "desk.website.state.$id")
            [ "$v" = "$want_state" ] || missing="$missing [state $id: ${v:-none}]"
            for part in line state; do
                r=$(wax find "desk.website.$part.$id" | grep '^found' | tail -n 1 | awk '{ print $NF }')
                [ "$r" = AXStaticText ] || missing="$missing [$part $id role: ${r:-none}]"
            done
            wax find "desk.website.win.$id" | grep -q '^found' || missing="$missing [button $id]"
        done
        if [ -z "$missing" ]; then
            result PASS "a desk's details list its windows" "website: claude in a tab, zsh open in another tab, vim not in a tab, each with a button"
        else
            result FAIL "a desk's details list its windows" "missing or wrong:$missing"
        fi
        v=$(wax value "desk.website.win.@1" | grep '^value' | tail -n 1)
        [ "${v#value }" = "Go to" ] || result DIFFERS "a window in a findable tab has Go to" "desk.website.win.@1 reads ${v:-nothing}"
        snap website-windows
        details_beside_and_under
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

    # shop's details (look step 3): web in two tabs, and a second window with the same name, which reads as the menu's
    # "web (window 1)".
    if click_id "desk.shop"; then
        sleep 1
        local l9 s9 l10 s10
        l9=$(val "desk.shop.line.@9"); s9=$(val "desk.shop.state.@9")
        l10=$(val "desk.shop.line.@10"); s10=$(val "desk.shop.state.@10")
        if [ "$l9|$s9|$l10|$s10" = "web|in 2 tabs|web (window 1)|not in a tab" ]; then
            result PASS "a window in two tabs and a repeated name read as the menu's facts" "$l9, $s9 | $l10, $s10"
        else
            result FAIL "a window in two tabs and a repeated name read as the menu's facts" \
                "@9: ${l9:-nothing}, ${s9:-nothing} | @10: ${l10:-nothing}, ${s10:-nothing}"
        fi
        rest_on_title
        snap shop-windows
    else
        result FAIL "a window in two tabs and a repeated name read as the menu's facts" "no row for shop"
    fi
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
    # Look step 2: a heading, the menu's sentence and the next step (ListProblemPage; the two fixed parts proposed).
    local h p x
    h=$(val "page.listProblemHeading"); p=$(val "page.listProblem"); x=$(val "page.listProblemNext")
    if [ "$h" = "MacMosh can't list your Macs" ] && [ "$p" = "Can't read MacMosh's saved settings: workhorses.json: not JSON" ] \
        && [ "$x" = "Once the file can be read again, your Macs come back at the next check." ]; then
        result PASS "the unreadable-list page has its heading, the sentence and the next step" "$h | $p | $x"
    else
        result FAIL "the unreadable-list page has its heading, the sentence and the next step" \
            "heading: ${h:-nothing} | sentence: ${p:-nothing} | next step: ${x:-nothing}"
    fi
    snap unreadable-list
    # Settings with a list that can't be read: This Mac's terminal and the store's sentence (issue 157).
    if click_id "sidebar.settings" && wait_id "settings.none" 5; then
        result PASS "Settings with an unreadable list shows the store's sentence" "settings.none reads: $(val settings.none)"
    else
        result FAIL "Settings with an unreadable list shows the store's sentence" "no settings.none"
    fi
    snap unreadable-settings
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
    # Look step 3: the title and each setting's sentence, one text each, in today's words; Add a Mac… is the chosen row.
    local h s1 s2 f r b fx fy fw fh
    h=$(val "page.addMac"); s1=$(val "page.addMac.step.1"); s2=$(val "page.addMac.step.2")
    if [ "$h" = "Add a Mac" ] && [ "$s1" = "Remote Login, so MacMosh can reach it." ] \
        && [ "$s2" = "Screen Sharing, so you can log in to it after a restart." ]; then
        result PASS "the Add a Mac page reads its title and today's two settings" "$h | $s1 | $s2"
    else
        result FAIL "the Add a Mac page reads its title and today's two settings" \
            "title: ${h:-nothing} | 1: ${s1:-nothing} | 2: ${s2:-nothing}"
    fi
    selected_only "the chosen row is Add a Mac…" sidebar.addMac sidebar.settings
    snap add-a-mac
    # At the smallest window the button stays in the window and the art is cut to its foot.
    wax size 600 300 > /dev/null
    sleep 1
    f=$(wax frame | grep '^frame' | tail -n 1)
    r=$(box "button.menu.pair" | awk 'NF == 4 { print $1 + $3 }'); b=$(box "button.menu.pair" | awk 'NF == 4 { print $2 + $4 }')
    read -r _ fx fy fw fh <<< "$f"
    if [ -n "$r" ] && [ -n "$b" ] && [ -n "${fh:-}" ] && [ "$r" -le $((fx + fw)) ] && [ "$b" -le $((fy + fh)) ]; then
        result PASS "at the smallest window Add a Mac… stays in the window" \
            "Add a Mac… ends at $r across and $b down, the window at $((fx + fw)) and $((fy + fh))"
    else
        result FAIL "at the smallest window Add a Mac… stays in the window" \
            "Add a Mac… ends at ${r:-?} across and ${b:-?} down; ${f:-no frame}"
    fi
    rest_on_title
    snap add-a-mac-minimum-size
    wax size 880 680 > /dev/null
    sleep 1
    # Settings with no workhorse: This Mac's terminal and "No workhorses yet…" (issue 157).
    if click_id "sidebar.settings" && wait_id "settings.none" 5; then
        result PASS "Settings with no workhorse says so" "settings.none reads: $(val settings.none)"
    else
        result FAIL "Settings with no workhorse says so" "no settings.none"
    fi
    snap no-workhorse-settings
    stop_app
}

############################################################ the forms (step 4)
# wait_id <identifier> <seconds>: until the window (or a sheet or dialog of it) has that element.
wait_id() {
    local deadline=$((SECONDS + $2))
    while [ "$SECONDS" -lt "$deadline" ]; do
        wax find "$1" | grep -q '^found' && return 0
        sleep 0.5
    done
    return 1
}

# gone_id <identifier> <seconds>: until it has no such element.
gone_id() {
    local deadline=$((SECONDS + $2))
    while [ "$SECONDS" -lt "$deadline" ]; do
        wax find "$1" | grep -q '^found' || return 0
        sleep 0.5
    done
    return 1
}

# val <identifier>: that element's text, or nothing.
val() { wax value "$1" | grep '^value' | tail -n 1 | sed 's/^value //'; }

# box <identifier>: that element's "x y w h", or nothing. right <identifier>: its right edge, or nothing.
box() { wax box "$1" | grep '^box' | tail -n 1 | sed 's/^box //'; }
right() { box "$1" | awk 'NF == 4 { print $1 + $3 }'; }

# rest_on_title: the pointer on the window's title bar, which has no help tag, before a picture.
rest_on_title() {
    local x y w
    read -r _ x y w _ <<< "$(wax frame | grep '^frame' | tail -n 1)"
    [ -n "${w:-}" ] && lim 10 "$TOOL" move "$((x + w / 2))" "$((y + 12))" >> "$LOG" 2>&1
    # A tag shown before the move fades out; one second was not always enough on macOS 26.
    sleep 2
}

# selected_only <check> <chosen> <other…> (look step 3): PASS when the chosen element reads "isselected true" and every
# other "isselected false"; DIFFERS when the chosen is true and some other has no selected attribute (listed); FAIL
# otherwise.
selected_only() {
    local check=$1 chosen=$2 t v id none="" bad="" detail
    shift 2
    t=$(wax isselected "$chosen" | grep -E '^(isselected|notfound)' | tail -n 1)
    detail="$chosen: ${t:-no answer}"
    for id in "$@"; do
        v=$(wax isselected "$id" | grep -E '^(isselected|notfound)' | tail -n 1)
        detail="$detail; $id: ${v:-no answer}"
        case "$v" in
            "isselected false") ;;
            "isselected none") none="$none $id" ;;
            *) bad="$bad $id" ;;
        esac
    done
    if [ "$t" = "isselected true" ] && [ -z "$bad" ] && [ -z "$none" ]; then
        result PASS "$check" "$detail"
    elif [ "$t" = "isselected true" ] && [ -z "$bad" ]; then
        result DIFFERS "$check" "with no selected attribute:$none; $detail"
    else
        result FAIL "$check" "$detail"
    fi
}

# same_end <check> <desk> <other desk>: the two rows' buttons end within 2 points of each other, so the state cells
# after them stand in one column (look step 1), whether or not the row has an Open button.
same_end() {
    local a b
    a=$(right "desk.$2"); b=$(right "desk.$3")
    if [ -n "$a" ] && [ -n "$b" ] && [ $((a - b)) -ge -2 ] && [ $((a - b)) -le 2 ]; then
        result PASS "$1" "desk.$2 ends at $a, desk.$3 at $b"
    else
        result FAIL "$1" "desk.$2 ends at ${a:-?}, desk.$3 at ${b:-?}"
    fi
}

# clear_field <identifier>: a click in the field, then the caret to its end and every character deleted, with
# keys a text field handles itself (arrows and Delete), not the edit menu's shortcuts.
clear_field() {
    click_id "$1" || return 1
    sleep 0.4
    tool keys 124 70 5 > /dev/null
    tool keys 51 70 5 > /dev/null
}

# expect_log <check> <moment> <text>: the app's log since then has that text, exactly.
expect_log() {
    if wait_log "$2" "$3" 10 > /dev/null; then
        result PASS "$1" "the log has: $3"
    else
        result FAIL "$1" "the log has no: $3; sample ssh lines: $(applog "$2" | grep -F "sample ssh:" | sed 's/.*sample ssh: //' | tr '\n' '|')"
    fi
}

# expect_value <check> <identifier> <want> <seconds>: the element reads exactly that within the time.
expect_value() {
    local deadline=$((SECONDS + $4)) v=""
    while [ "$SECONDS" -lt "$deadline" ]; do
        v=$(val "$2")
        [ "$v" = "$3" ] && { result PASS "$1" "$2 reads: $v"; return 0; }
        sleep 0.5
    done
    result FAIL "$1" "$2 reads: ${v:-nothing} (expected: $3)"
    return 1
}

# expect_line <check> <moment> <line>: one of the stand-in's desk-new lines since then is exactly that line, with
# nothing after it (expect_log only looks for the text inside a line).
expect_line() {
    local lines
    wait_log "$2" " desk-new " 10 > /dev/null
    sleep 1
    lines=$(applog "$2" | grep -F "sample ssh: " | grep -F " desk-new " | sed 's/.*sample ssh: /sample ssh: /')
    if printf '%s\n' "$lines" | grep -qxF -- "$3"; then
        result PASS "$1" "the log has exactly: $3"
    else
        result FAIL "$1" "expected exactly: $3; desk-new lines: $(printf '%s' "$lines" | tr '\n' '|')"
    fi
}

# expect_row <check> <desk> <start>: within 10 s the desk's row reads its name, its windows' names and its folder,
# starting with that text ("recipes, build logs, ").
expect_row() {
    local deadline=$((SECONDS + 10)) v=""
    while [ "$SECONDS" -lt "$deadline" ]; do
        v=$(val "desk.$2")
        if [[ "$v" == "$3"* ]]; then
            result PASS "$1" "desk.$2 reads: $v"
            return 0
        fi
        sleep 0.5
    done
    result FAIL "$1" "desk.$2 reads: ${v:-nothing} (expected it to start with: $3)"
    return 1
}

# checked <identifier>: "checked 1" when the checkbox is ticked, "checked 0" when clear, else what windowtool said.
checked() { wax checked "$1" | grep -E '^(checked|notfound)' | tail -n 1; }

# The New desk form, Rename and Remove in the window (main window design, section 8, step 4): the sample
# "window-forms" is Attic, Ready, with no projects folder saved, whose desks a stand-in ssh changes. It writes
# each call's exact remote command to the log (`sample ssh: ... run=<command>`) and answers as the script would.
forms_sample() {
    local since start v x y paste want typed deadline clip keys_since n
    start=$(moment)
    start_app window-forms || return
    if ! open_window; then stop_app; return; fi
    sleep 2
    snap page
    # What the app's main menu holds when the window opens (debug builds log it; issue #147). A finding.
    v=$(applog "$start" | grep -F "main menu: " | sed 's/.*main menu: /main menu: /' | tr '\n' '|')
    result "$([ -n "$v" ] && echo PASS || echo NOT-SHOWN)" "the app logs its main menu when the window opens" "${v:-no 'main menu:' line}"

    # New desk… opens the form, which asks for a projects folder first.
    if ! click_id "button.newDesk" || ! wait_id "form.newDesk" 6; then
        result FAIL "New desk… opens the form" "no New desk sheet"
        snap no-form
        stop_app
        return
    fi
    result PASS "New desk… opens the form" "form.newDesk found"
    sleep 0.5
    # shellcheck disable=SC2088 # the field's own text, a tilde and all
    expect_value "with no projects folder the form offers one" "form.projectsFolder" "~/Development" 3
    snap new-desk-projects-folder

    # Save fills the list from the workhorse.
    since=$(moment)
    click_id "form.saveProjectsFolder"
    expect_log "Save lists the folders of the saved projects folder" "$since" \
        "run=~/.macmosh/macmosh-host folders '~/Development'"
    if wait_id "form.folder.garden-planner" 8; then
        result PASS "the folder list fills after Save" "form.folder.garden-planner found"
    else
        result FAIL "the folder list fills after Save" "no row for garden-planner"
        snap no-list
        stop_app
        return
    fi
    sleep 0.5
    snap new-desk-form

    # A click on a folder names the desk after it.
    click_id "form.folder.garden-planner"
    expect_value "a chosen folder names the desk" "form.name" "garden-planner" 3

    # The first window's line (issue 163): at script 0.12.0 its box is there and ticked at first, with no field.
    v=$(checked "form.sameAsDesk")
    result "$([ "$v" = "checked 1" ] && echo PASS || echo FAIL)" "the first window's box is there and ticked at first" "${v:-no answer}"
    if wax find "form.firstWindowName" | grep -q '^found'; then
        result FAIL "ticked, the form has no field for the window's own name" "form.firstWindowName is there"
    else
        result PASS "ticked, the form has no field for the window's own name" "no form.firstWindowName"
    fi

    # A taken name is refused as it is typed, and Make desk is off.
    clear_field "form.name"
    tool type "api" > /dev/null
    sleep 0.5
    expect_value "a taken name is refused as typed" "form.name.help" "Attic already has a desk called api." 3
    v=$(wax enabled "form.make" | grep '^enabled' | tail -n 1)
    if [ "$v" = "enabled false" ]; then
        result PASS "Make desk is off while the name is taken" "$v"
    else
        result FAIL "Make desk is off while the name is taken" "${v:-no answer}"
    fi
    snap taken-name

    # A typed path that is neither full nor starts with ~ says why under the field, and Make desk stays off.
    click_id "form.path" > /dev/null
    sleep 0.4
    tool type "Development/garden" > /dev/null
    expect_value "a refused path says why under the field" "form.path.help" "A path is full, starting with /, or starts with ~." 3
    snap bad-path
    clear_field "form.path"
    if gone_id "form.path.help" 3; then
        result PASS "the path's line goes once the field is empty" "form.path.help gone"
    else
        result FAIL "the path's line goes once the field is empty" "form.path.help is still there"
    fi

    # The name and a command typed with posted keys.
    clear_field "form.name"
    tool type "garden-planner" > /dev/null
    expect_value "a typed name reaches the field" "form.name" "garden-planner" 3
    clear_field "form.command"
    tool type "claude --continue" > /dev/null
    expect_value "a typed command reaches the field" "form.command" "claude --continue" 3

    # A new name can't start with a dash (issue #147): the line under the field says so, and Make desk is off.
    clear_field "form.name"
    tool type "--old" > /dev/null
    expect_value "a name that starts with a dash is refused as typed" "form.name.help" "A desk name can't start with -." 3
    v=$(wax enabled "form.make" | grep '^enabled' | tail -n 1)
    result "$([ "$v" = "enabled false" ] && echo PASS || echo FAIL)" "Make desk is off while the name starts with a dash" "${v:-no answer}"
    snap dash-name
    clear_field "form.name"
    tool type "garden-planner" > /dev/null
    expect_value "the typed name is back to garden-planner" "form.name" "garden-planner" 3

    # The window's editing keys in an app with no menu bar of its own (issue #147): Command-V, then Command-A and
    # Command-C, Command-X, Command-Z and Shift-Command-Z in the command field, and Command-W with the form open.
    # Each fails the job. None of these key presses may set off the menu-open signal.
    # shellcheck disable=SC2016 # the text as typed, $HOME and all
    paste='claude --continue "fix it" $HOME; ls'
    keys_since=$(moment)
    printf '%s' "$paste" | pbcopy
    # The clipboard is read back first, so an empty field after Command-V means the paste did not land, not that
    # there was nothing to paste.
    clip=$(pbpaste)
    if [ "$clip" != "$paste" ]; then
        result NOT-SHOWN "Command-V pastes into the command field" "the clipboard was not set (pbpaste reads: ${clip:-nothing})"
    else
        say "pbpaste reads back the text pbcopy was given"
        clear_field "form.command"
        tool chord v cmd > /dev/null
        sleep 0.8
        v=$(val "form.command")
        if [ "$v" = "$paste" ]; then
            result PASS "Command-V pastes into the command field" "the clipboard held the text, and the field reads back: $v"
        else
            result FAIL "Command-V pastes into the command field" "the clipboard held the text (pbpaste), and after Command-V the field reads: ${v:-nothing}"
        fi
    fi
    # The whole screen with the window in front: no Dock icon and no menu bar of the app's.
    snap_screen keys-screen
    if [ "$(val "form.command")" != "$paste" ]; then
        clear_field "form.command"
        tool type "$paste" > /dev/null
        sleep 0.5
    fi

    # Command-A then Command-C puts the field's text on the clipboard.
    printf '%s' "not the field" | pbcopy
    click_id "form.command" > /dev/null
    sleep 0.4
    tool chord a cmd > /dev/null
    sleep 0.3
    tool chord c cmd > /dev/null
    sleep 0.6
    clip=$(pbpaste)
    if [ "$clip" = "$paste" ]; then
        result PASS "Command-A then Command-C copies the field's text" "pbpaste reads: $clip"
    else
        result FAIL "Command-A then Command-C copies the field's text" "pbpaste reads: ${clip:-nothing} (the field: $(val "form.command"))"
    fi

    # Command-X empties the field and fills the clipboard.
    printf '%s' "not the field" | pbcopy
    tool chord a cmd > /dev/null
    sleep 0.3
    tool chord x cmd > /dev/null
    sleep 0.6
    v=$(val "form.command")
    clip=$(pbpaste)
    if [ -z "$v" ] && [ "$clip" = "$paste" ]; then
        result PASS "Command-X cuts the field's text" "the field is empty, pbpaste reads: $clip"
    else
        result FAIL "Command-X cuts the field's text" "the field reads: ${v:-nothing}; pbpaste reads: ${clip:-nothing}"
    fi
    snap after-cut

    # Command-Z brings the text back, and Shift-Command-Z cuts it again. Each is tried only from the state the key
    # before it left, so neither passes when nothing happened: without the cut, Command-Z is not shown.
    if [ -n "$(val "form.command")" ]; then
        result NOT-SHOWN "Command-Z undoes the cut" "the cut did not happen, so there is nothing to undo"
    else
        tool chord z cmd > /dev/null
        sleep 0.6
        v=$(val "form.command")
        if [ "$v" = "$paste" ]; then
            result PASS "Command-Z undoes the cut" "the field reads: $v"
        else
            result FAIL "Command-Z undoes the cut" "the field reads: ${v:-nothing}"
        fi
    fi
    if [ "$(val "form.command")" != "$paste" ]; then
        result NOT-SHOWN "Shift-Command-Z redoes the cut" "the field does not hold the undone text, so there is nothing to redo"
    else
        tool chord z shiftcmd > /dev/null
        sleep 0.6
        v=$(val "form.command")
        if [ -z "$v" ]; then
            result PASS "Shift-Command-Z redoes the cut" "the field is empty"
        else
            result FAIL "Shift-Command-Z redoes the cut" "the field reads: $v"
        fi
    fi

    # Command-W with the form open closes nothing: neither the form nor the window (issue #147). This row means
    # something only when "Command-W closes the window" passes in the same run (window_keys), and so does the one
    # with the menu open.
    tool chord w cmd > /dev/null
    sleep 1.5
    n=$(windows)
    if [ "${n:-0}" -eq 1 ] && wax find "form.newDesk" | grep -q '^found'; then
        result PASS "Command-W with the form open closes nothing" "windows=1, form.newDesk still there (read with: Command-W closes the window)"
    else
        result FAIL "Command-W with the form open closes nothing" "windows=${n:-?}; form.newDesk: $(wax find "form.newDesk" | head -n 1)"
    fi

    # The key presses set off no menu-open signal: no "menu opened" and no "menu tracking" line since the first.
    v=$(applog "$keys_since" | grep -cE "menu opened|menu tracking")
    if [ "$v" -eq 0 ]; then
        result PASS "the editing keys set off no menu-open signal" "no 'menu opened' or 'menu tracking' line"
    else
        result FAIL "the editing keys set off no menu-open signal" "$v line(s): $(applog "$keys_since" | grep -E "menu opened|menu tracking" | sed 's/.*menu/menu/' | tr '\n' '|')"
    fi

    if [ "$(val "form.command")" != "$paste" ]; then
        clear_field "form.command"
        tool type "$paste" > /dev/null
        sleep 0.5
    fi
    typed=$(val "form.command")
    [ "$typed" = "$paste" ] || result DIFFERS "the command with quotes, \$ and ; is in the field" "it reads: ${typed:-nothing}"
    snap new-desk-filled

    # Return presses Make desk: one ssh call with the command as one argument, exactly as typed.
    since=$(moment)
    tool keys 36 1 100 > /dev/null
    sleep 0.6
    v=$(val "form.make")
    if [ "$v" = "Making…" ]; then
        result PASS "the button says Making… while the desk is made" "form.make reads: $v"
    else
        result DIFFERS "the button says Making… while the desk is made" "form.make reads: ${v:-nothing}"
    fi
    snap making
    # The box is ticked, so the first window gets the desk's name (issue 163).
    want="sample ssh: to=alex@192.168.1.20 batch=yes stdin=closed limit=15s run=~/.macmosh/macmosh-host desk-new garden-planner '~/Development/garden-planner' --reopen --window-name garden-planner --command '$paste'"
    # The row is read before the log, which can take longer to read than the sample's 0.8-second check.
    if gone_id "form.newDesk" 6; then
        result PASS "the form closes once the desk is made" "form.newDesk gone"
    else
        result FAIL "the form closes once the desk is made" "the sheet is still there"
    fi
    v=$(val "desk.garden-planner.status")
    result "$([ "$v" = "Updating…" ] && echo PASS || echo DIFFERS)" "the new desk's row says Updating… until the check lands" "it reads: ${v:-nothing}"
    snap updating
    same_end "a new desk's state stands in the column while it has no Open" "garden-planner" "api"
    expect_log "Make desk sends the exact arguments" "$since" "$want"
    expect_log "Make desk writes its log line" "$since" "window action: newDesk ok"
    expect_value "the page says what happened" "page.result" "Created the desk garden-planner on Attic." 10
    v=$(val "desk.garden-planner.status")
    deadline=$((SECONDS + 8))
    while [ "$v" = "Updating…" ] && [ "$SECONDS" -lt "$deadline" ]; do sleep 0.5; v=$(val "desk.garden-planner.status"); done
    if [ "$v" = "No tab" ]; then
        result PASS "once the check lands the new desk's row is the check's" "desk.garden-planner.status reads: $v"
    else
        result FAIL "once the check lands the new desk's row is the check's" "desk.garden-planner.status reads: ${v:-nothing}"
    fi
    expect_log "Open it in a tab now runs the menu's open for the new desk" "$since" "menu action: tab connect (window)"
    expect_row "ticked, the new desk's first window has the desk's name" "garden-planner" "garden-planner, garden-planner, "
    sleep 2
    snap after-new-desk

    # Rename… on api: the field holds the old name; a new one is sent as typed.
    click_id "desk.api" > /dev/null
    sleep 1
    if click_id "button.rename" && wait_id "form.rename" 6; then
        expect_value "Rename's field holds the old name" "form.newName" "api" 3
        snap rename
        clear_field "form.newName"
        tool type "api-v2" > /dev/null
        sleep 0.5
        snap rename-filled
        since=$(moment)
        tool keys 36 1 100 > /dev/null
        expect_log "Rename sends the exact arguments" "$since" \
            "sample ssh: to=alex@192.168.1.20 batch=yes stdin=closed limit=15s run=~/.macmosh/macmosh-host desk-rename api api-v2"
        expect_log "Rename writes its log line" "$since" "window action: rename ok"
        if gone_id "form.rename" 6; then
            result PASS "the Rename form closes once renamed" "form.rename gone"
        else
            result FAIL "the Rename form closes once renamed" "the sheet is still there"
        fi
        expect_value "the page says what Rename did" "page.result" "Renamed api to api-v2 on Attic." 10
        if gone_id "desk.api" 8 && wait_id "desk.api-v2" 2; then
            result PASS "after the check the row has the new name only" "desk.api gone, desk.api-v2 there"
        else
            result FAIL "after the check the row has the new name only" "desk.api still there, or no desk.api-v2"
        fi
        sleep 2
        snap after-rename
    else
        result FAIL "Rename… opens its form" "no Rename button or form for api"
    fi

    # Remove… on website: the terminal's sentence, a destructive Remove website and Cancel.
    click_id "desk.website" > /dev/null
    sleep 1
    if click_id "button.remove"; then
        sleep 1.5
        v=$(wax text "This removes the desk website" | grep '^text' | tail -n 1 | sed 's/^text //')
        if [ "$v" = "This removes the desk website and closes its 3 windows (claude, zsh, vim), with whatever is running in them." ]; then
            result PASS "Remove asks with the terminal's sentence" "$v"
        else
            result FAIL "Remove asks with the terminal's sentence" "the dialog reads: ${v:-nothing}"
        fi
        snap remove
        snap_screen remove-screen
        read -r _ x y _ <<< "$(wax button "Remove website" | grep '^found' | tail -n 1)"
        if [ -n "${y:-}" ]; then
            since=$(moment)
            say "click on [Remove website] at $x,$y"
            tool click "$x" "$y" > /dev/null
            expect_log "Remove sends the exact arguments" "$since" \
                "sample ssh: to=alex@192.168.1.20 batch=yes stdin=closed limit=15s run=~/.macmosh/macmosh-host desk-remove website --kill"
            expect_log "Remove writes its log line" "$since" "window action: remove ok"
            expect_value "the page says what Remove did" "page.result" "Removed the desk website from Attic." 10
            if gone_id "desk.website" 8; then
                result PASS "after the check the removed desk's row is gone" "desk.website gone"
            else
                result FAIL "after the check the removed desk's row is gone" "desk.website still there"
            fi
            sleep 2
            snap after-remove
        else
            result FAIL "Remove asks with the terminal's sentence" "no Remove website button"
        fi
    else
        result FAIL "Remove… opens its confirmation" "no Remove button for website"
    fi

    # After Rename and Remove, so the two desks it makes don't push website's strip under the Dock (issue 163).
    first_window_forms

    # The sheets and the dialog are no menu: the menu-open signal never came (design, section 7.2). A finding.
    v=$(applog "$start" | grep -cF "menu opened")
    if [ "$v" -eq 1 ]; then
        result PASS "the forms set off no menu-open signal" "one 'menu opened': the menu's own, for Open MacMosh"
    else
        result DIFFERS "the forms set off no menu-open signal" "'menu opened' lines: $v (one is the menu's own)"
    fi
    stop_app
}

# The first window's line of the New desk form (issue 163), in the "window-forms" sample after garden-planner was
# made with the box ticked, and after Rename and Remove: the form again on recipes, cleared and empty, with a bad name and with a name of its own,
# each pictured; Make desk with that name; then a desk with the box clear and the field empty. The stand-in names the
# window as the script would, and the row shows its name after the check.
first_window_forms() {
    local since v help="Left empty, the window is named after the program running in it."
    if ! click_id "button.newDesk" || ! wait_id "form.folder.recipes" 8; then
        result FAIL "New desk… opens the form again with its folders" "no form, or no row for recipes"
        snap no-form-again
        return
    fi
    sleep 0.5
    click_id "form.folder.recipes"
    expect_value "a chosen folder names the second desk" "form.name" "recipes" 3
    # The command field holds the last command sent; emptied, so these desks start a plain shell.
    clear_field "form.command"
    v=$(checked "form.sameAsDesk")
    result "$([ "$v" = "checked 1" ] && echo PASS || echo FAIL)" "a new form has the box ticked again" "${v:-no answer}"
    snap first-window-ticked

    # Clear: the field and its grey line show, and Make desk stays on.
    click_id "form.sameAsDesk"
    if ! wait_id "form.firstWindowName" 3; then
        result FAIL "clearing the box shows the field for the window's own name" "no form.firstWindowName; the box: $(checked "form.sameAsDesk")"
        snap no-window-field
        tool keys 53 1 100 > /dev/null
        return
    fi
    result PASS "clearing the box shows the field for the window's own name" "form.firstWindowName found; the box: $(checked "form.sameAsDesk")"
    expect_value "clear and empty, the line says tmux names the window" "form.firstWindowName.help" "$help" 3
    v=$(wax enabled "form.make" | grep '^enabled' | tail -n 1)
    result "$([ "$v" = "enabled true" ] && echo PASS || echo FAIL)" "Make desk is on with the box clear and the field empty" "${v:-no answer}"
    snap first-window-clear-empty

    # A name that breaks the rule: the rule's sentence, and Make desk is off.
    click_id "form.firstWindowName" > /dev/null
    sleep 0.4
    tool type "a#b" > /dev/null
    expect_value "a bad window name shows the rule's sentence" "form.firstWindowName.help" \
        "A window name uses letters, digits, spaces, -, _ and full stops only." 3
    v=$(wax enabled "form.make" | grep '^enabled' | tail -n 1)
    result "$([ "$v" = "enabled false" ] && echo PASS || echo FAIL)" "Make desk is off while the window's name is bad" "${v:-no answer}"
    snap first-window-bad-name

    # A name of its own, with a space.
    clear_field "form.firstWindowName"
    tool type "build logs" > /dev/null
    expect_value "a window name with a space reaches the field" "form.firstWindowName" "build logs" 3
    expect_value "a good window name brings the grey line back" "form.firstWindowName.help" "$help" 3
    v=$(wax enabled "form.make" | grep '^enabled' | tail -n 1)
    result "$([ "$v" = "enabled true" ] && echo PASS || echo FAIL)" "Make desk is on with a window name of its own" "${v:-no answer}"
    snap first-window-named
    since=$(moment)
    tool keys 36 1 100 > /dev/null
    expect_line "Make desk sends the window's own name" "$since" \
        "sample ssh: to=alex@192.168.1.20 batch=yes stdin=closed limit=15s run=~/.macmosh/macmosh-host desk-new recipes '~/Development/recipes' --reopen --window-name 'build logs'"
    if gone_id "form.newDesk" 6; then
        result PASS "the form closes once recipes is made" "form.newDesk gone"
    else
        result FAIL "the form closes once recipes is made" "the sheet is still there"
        snap form-stays
        tool keys 53 1 100 > /dev/null
        return
    fi
    expect_value "the result line is unchanged with a window name" "page.result" "Created the desk recipes on Attic." 10
    expect_row "after the check the new desk's row shows the window's own name" "recipes" "recipes, build logs, "
    sleep 1
    snap after-named-window

    # Clear and empty: nothing about the window is sent, and tmux names it after its program.
    if ! click_id "button.newDesk" || ! wait_id "form.newDesk" 6; then
        result FAIL "New desk… opens the form a third time" "no form"
        return
    fi
    sleep 1
    click_id "form.path" > /dev/null
    sleep 0.4
    # shellcheck disable=SC2088 # the text typed into the field, a tilde and all
    tool type "~/Development/shop" > /dev/null
    expect_value "a typed path names the third desk" "form.name" "shop" 3
    click_id "form.sameAsDesk"
    wait_id "form.firstWindowName" 3 || true
    v=$(checked "form.sameAsDesk")
    result "$([ "$v" = "checked 0" ] && echo PASS || echo FAIL)" "the box is clear for the third desk" "${v:-no answer}"
    snap first-window-clear-before-make
    since=$(moment)
    tool keys 36 1 100 > /dev/null
    expect_line "clear and empty, Make desk sends nothing about the window" "$since" \
        "sample ssh: to=alex@192.168.1.20 batch=yes stdin=closed limit=15s run=~/.macmosh/macmosh-host desk-new shop '~/Development/shop' --reopen"
    gone_id "form.newDesk" 6 || tool keys 53 1 100 > /dev/null
    expect_row "after the check the window is named after its program" "shop" "shop, zsh, "
    sleep 1
    snap after-unnamed-window
}

# The "window-forms-0.11" sample (issue 163): the forms sample with a workhorse script older than 0.12.0. Its New desk
# form has no first-window line, and Make desk sends nothing about the window; the stand-in refuses --window-name as
# a 0.11.0 script does.
forms_older_script() {
    local since v
    start_app window-forms-0.11 || return
    if ! open_window; then stop_app; return; fi
    sleep 2
    if ! click_id "button.newDesk" || ! wait_id "form.newDesk" 6; then
        result FAIL "New desk… opens the form with an older script" "no New desk sheet"
        snap no-form
        stop_app
        return
    fi
    sleep 1
    click_id "form.path" > /dev/null
    sleep 0.4
    # shellcheck disable=SC2088 # the text typed into the field, a tilde and all
    tool type "~/Development/shop" > /dev/null
    expect_value "a typed path names the desk" "form.name" "shop" 3
    v=$(checked "form.sameAsDesk")
    if [ "$v" = "notfound" ] && ! wax find "form.firstWindowName" | grep -q '^found'; then
        result PASS "with an older script the form has no first-window line" "no form.sameAsDesk, no form.firstWindowName"
    else
        result FAIL "with an older script the form has no first-window line" "form.sameAsDesk: ${v:-no answer}"
    fi
    snap older-script-form
    since=$(moment)
    tool keys 36 1 100 > /dev/null
    expect_line "with an older script Make desk sends nothing about the window" "$since" \
        "sample ssh: to=alex@192.168.1.20 batch=yes stdin=closed limit=15s run=~/.macmosh/macmosh-host desk-new shop '~/Development/shop' --reopen"
    expect_value "the older script makes the desk" "page.result" "Created the desk shop on Attic." 10
    expect_row "with an older script tmux names the window" "shop" "shop, zsh, "
    sleep 1
    snap older-script-after
    stop_app
}

# Command-W and Command-Q with the window in front, and Command-W with the menu-bar menu open (issue #147).
# Command-W closes the window and the app keeps running with its menu; with the menu open it closes nothing.
# Command-Q comes last: what it does is reported, and the app is stopped after it either way.
window_keys() {
    local since n v
    start_app six-desks || return
    if ! open_window; then stop_app; return; fi
    sleep 1
    snap_screen window-in-front

    # Command-W with the menu-bar menu open closes nothing; Escape then closes the menu.
    if open_menu; then
        tool chord w cmd > /dev/null
        sleep 1
        close_menu
        sleep 1
        n=$(windows)
        if [ "${n:-0}" -eq 1 ]; then
            result PASS "Command-W with the menu open closes nothing" "windows=1 (read with: Command-W closes the window)"
        else
            result FAIL "Command-W with the menu open closes nothing" "windows=${n:-?}"
        fi
    else
        result NOT-SHOWN "Command-W with the menu open closes nothing" "the menu did not open"
    fi

    # Command-W in the window closes it: the window comes to the front first, with a click on its title bar.
    local frame fx fy fw
    frame=$(wax frame | grep '^frame' | tail -n 1)
    read -r _ fx fy fw _ <<< "$frame"
    [ -n "${fw:-}" ] && tool click "$((fx + fw / 2))" "$((fy + 12))" > /dev/null
    sleep 0.5
    since=$(moment)
    tool chord w cmd > /dev/null
    n=$(wait_windows 0 5)
    if [ "$n" -eq 0 ]; then
        result PASS "Command-W closes the window" "windows=0"
    else
        result FAIL "Command-W closes the window" "windows=$n after Command-W"
    fi
    v=$(applog "$since" | grep -cE "menu opened|menu tracking")
    if [ "$v" -eq 0 ]; then
        result PASS "Command-W sets off no menu-open signal" "no 'menu opened' or 'menu tracking' line"
    else
        result FAIL "Command-W sets off no menu-open signal" "$v line(s)"
    fi
    sleep 1.5
    if kill -0 "$app_pid" 2>/dev/null; then
        result PASS "after Command-W the app keeps running" "pid $app_pid still there"
    else
        result FAIL "after Command-W the app keeps running" "the app ended"
        app_pid=""
        return
    fi
    if open_menu; then
        result PASS "the menu still opens after Command-W" "menu windows=$(count)"
        close_menu
    else
        result FAIL "the menu still opens after Command-W" "no menu window within 6 s of the click"
    fi

    # Command-Q with the window in front: reported, never failed. The window is opened again if Command-W closed
    # it, and brought to the front with a click on its title bar either way.
    if [ "$(windows)" = 0 ] && ! open_window; then
        result NOT-SHOWN "Command-Q with the window in front leaves the app running" "the window did not open again"
    else
        frame=$(wax frame | grep '^frame' | tail -n 1)
        read -r _ fx fy fw _ <<< "$frame"
        [ -n "${fw:-}" ] && tool click "$((fx + fw / 2))" "$((fy + 12))" > /dev/null
        sleep 1
        say "$(wax front | grep '^front' | tail -n 1)"
        tool chord q cmd > /dev/null
        sleep 3
        if kill -0 "$app_pid" 2>/dev/null; then
            result PASS "Command-Q with the window in front leaves the app running" "pid $app_pid still there, windows=$(windows)"
        else
            result DIFFERS "Command-Q with the window in front leaves the app running" "the app quit"
            app_pid=""
        fi
    fi
    stop_app
}

############################################################ naming a window (issue 144)
# The "window-forms" sample again, in a fresh app, so website is there with its three windows (@4 claude, @5 zsh,
# @6 vim; blog has one, @3). Its script is 0.11.0 and its report gives the windows' ids, so website's details have
# a Name… on each window and blog's strip has Name its window…. The stand-in ssh names the window as the script
# would and writes each call's exact remote command to the log.
# website's vim (@6) named with 32 letters, the longest the sheet allows (WindowName.maxLength), at the default size
# (look step 2's review): the facts beside the lines keep the width they had with "vim" and stay in the panel, and the
# name gives way before its state. A picture, with the pointer on the title bar.
long_window_name() {
    local long="Database Migration Worker Logs 2" v deadline before after fx fr sr nr sl lr
    before=$(box "desk.website.facts" | awk 'NF == 4 { print $3 }')
    if ! click_id "desk.website.name.@6" || ! wait_id "form.nameWindow" 6; then
        result FAIL "a 32-letter window name leaves the facts their width" "no sheet for website's window @6"
        return
    fi
    sleep 1
    clear_field "form.windowName"
    tool type "$long" > /dev/null
    expect_value "a 32-letter window name reaches the field" "form.windowName" "$long" 3
    tool keys 36 1 100 > /dev/null
    gone_id "form.nameWindow" 6 > /dev/null
    deadline=$((SECONDS + 10))
    v=$(val "desk.website.line.@6")
    while [ "$v" != "$long" ] && [ "$SECONDS" -lt "$deadline" ]; do sleep 0.5; v=$(val "desk.website.line.@6"); done
    sleep 1
    read -r fx _ after _ <<< "$(box "desk.website.facts")"
    fr=$(right "desk.website.facts"); sr=$(right "desk.website.strip"); lr=$(right "desk.website.lines")
    nr=$(right "desk.website.line.@6"); sl=$(box "desk.website.state.@6" | awk 'NF == 4 { print $1 }')
    if [ "$v" = "$long" ] && [ -n "$before" ] && [ -n "${after:-}" ] && [ -n "$fr" ] && [ -n "$sr" ] && [ -n "$lr" ] \
        && [ "$after" -ge $((before - 1)) ] && [ "$fr" -le "$sr" ] && [ "$lr" -le "$fx" ]; then
        result PASS "a 32-letter window name leaves the facts their width" \
            "facts $after wide (with vim: $before), from $fx to $fr, the panel ends at $sr, the lines at $lr"
    else
        result FAIL "a 32-letter window name leaves the facts their width" \
            "line @6 reads ${v:-nothing}; facts ${after:-?} wide (with vim: ${before:-?}), from ${fx:-?} to ${fr:-?}, the panel ends at ${sr:-?}, the lines at ${lr:-?}"
    fi
    if [ -n "$nr" ] && [ -n "$sl" ] && [ "$nr" -le "$sl" ]; then
        result PASS "a 32-letter window name ends before its state" "the name ends at $nr, its state starts at $sl"
    else
        result FAIL "a 32-letter window name ends before its state" "the name ends at ${nr:-?}, its state starts at ${sl:-?}"
    fi
    rest_on_title
    snap long-window-name
}

window_names_sample() {
    local since v missing want deadline id t
    start_app window-forms || return
    # The same sample as forms_sample: its pictures and results are named apart.
    sample=window-names
    if ! open_window; then stop_app; return; fi
    sleep 2

    # website's details: each window has its Name… beside its Open.
    if ! click_id "desk.website" || ! wait_id "desk.website.strip" 5; then
        result FAIL "a desk's details have a Name… on each window" "no strip for website"
        stop_app
        return
    fi
    sleep 0.5
    missing=""
    for id in @4 @5 @6; do
        v=$(val "desk.website.name.$id")
        [ "$v" = "Name…" ] || missing="$missing [$id: ${v:-none}]"
    done
    if [ -z "$missing" ]; then
        result PASS "a desk's details have a Name… on each window" "desk.website.name.@4, @5 and @6 read Name…"
    else
        result FAIL "a desk's details have a Name… on each window" "missing or wrong:$missing"
    fi
    snap details-name-buttons

    # Name… on vim (window 2) opens the sheet, its field holding the name, selected.
    if ! click_id "desk.website.name.@6" || ! wait_id "form.nameWindow" 6; then
        result FAIL "Name… opens the sheet" "no sheet for website's window @6"
        snap no-sheet
        stop_app
        return
    fi
    result PASS "Name… opens the sheet" "form.nameWindow found"
    sleep 1
    v=$(wax text "Name a window of" | grep '^text' | tail -n 1 | sed 's/^text //')
    result "$([ "$v" = "Name a window of website" ] && echo PASS || echo FAIL)" "the sheet's title names the desk" "it reads: ${v:-nothing}"
    v=$(wax text "Name for window" | grep '^text' | tail -n 1 | sed 's/^text //')
    result "$([ "$v" = "Name for window 2 (vim)" ] && echo PASS || echo FAIL)" "the sheet's label names the window and its name" "it reads: ${v:-nothing}"
    expect_value "the field holds the window's name" "form.windowName" "vim" 3
    v=$(wax selected "form.windowName" | grep '^selected' | tail -n 1 | sed 's/^selected //')
    result "$([ "$v" = "vim" ] && echo PASS || echo DIFFERS)" "the field's name is selected" "the selected text reads: ${v:-nothing}"
    v=$(wax enabled "form.nameButton" | grep '^enabled' | tail -n 1)
    result "$([ "$v" = "enabled false" ] && echo PASS || echo FAIL)" "Name is off while the name is unchanged" "${v:-no answer}"
    expect_value "the line under the field is the rule" "form.windowName.help" \
        "A window name is 1 to 32 letters, digits, spaces, -, _ and full stops. It can't start with a space or -, or end with a space." 3
    snap sheet

    # Typing with nothing clicked: the selected name is replaced. A finding; the field is cleared after either way.
    tool type "-x" > /dev/null
    sleep 0.5
    v=$(val "form.windowName")
    result "$([ "$v" = "-x" ] && echo PASS || echo DIFFERS)" "typing replaces the selected name" "the field reads: ${v:-nothing}"
    if [ "$v" != "-x" ]; then
        clear_field "form.windowName"
        tool type "-x" > /dev/null
        sleep 0.5
    fi
    # A refused name says why under the field, and Name stays off.
    expect_value "a name starting with - is refused with its reason" "form.windowName.help" "A window name can't start with -." 3
    v=$(wax enabled "form.nameButton" | grep '^enabled' | tail -n 1)
    result "$([ "$v" = "enabled false" ] && echo PASS || echo FAIL)" "Name is off while the name is refused" "${v:-no answer}"
    snap refused

    # A name with a space, typed with posted keys; Return presses Name: one call, the name as one argument.
    clear_field "form.windowName"
    tool type "front end" > /dev/null
    expect_value "a name with a space reaches the field" "form.windowName" "front end" 3
    v=$(wax enabled "form.nameButton" | grep '^enabled' | tail -n 1)
    result "$([ "$v" = "enabled true" ] && echo PASS || echo FAIL)" "Name is on for a valid new name" "${v:-no answer}"
    snap typed
    since=$(moment)
    tool keys 36 1 100 > /dev/null
    # The row is read before the log, which takes a second or two to read: the sample's check takes 0.8 s.
    if gone_id "form.nameWindow" 6; then
        result PASS "the sheet closes once the window is named" "form.nameWindow gone"
    else
        result FAIL "the sheet closes once the window is named" "the sheet is still there"
    fi
    v=$(val "desk.website.status")
    result "$([ "$v" = "Updating…" ] && echo PASS || echo DIFFERS)" "the desk's row says Updating… until the check lands" "it reads: ${v:-nothing}"
    snap updating
    want="sample ssh: to=alex@192.168.1.20 batch=yes stdin=closed limit=15s run=~/.macmosh/macmosh-host window-name website @6 'front end'"
    expect_log "Name sends the exact arguments" "$since" "$want"
    expect_log "Name writes its log line" "$since" "window action: nameWindow ok"
    expect_value "the page says what Name did" "page.result" 'Named window 2 of website "front end" on Attic.' 10
    # After the check, the row's list of names and the details show the new name whole.
    deadline=$((SECONDS + 10))
    v=$(val "desk.website")
    while [[ "$v" != *"claude, zsh, front end"* ]] && [ "$SECONDS" -lt "$deadline" ]; do sleep 0.5; v=$(val "desk.website"); done
    if [[ "$v" == *"claude, zsh, front end"* ]]; then
        result PASS "after the check the row shows the new name" "desk.website reads: $v"
    else
        result FAIL "after the check the row shows the new name" "desk.website reads: ${v:-nothing}"
    fi
    v=$(val "desk.website.line.@6"); t=$(val "desk.website.state.@6")
    result "$([ "$v" = "front end" ] && [ "$t" = "not in a tab" ] && echo PASS || echo DIFFERS)" \
        "the details show the window's new name whole" "the window's line reads: ${v:-nothing}; its state: ${t:-nothing}"
    rest_on_title
    snap after-name

    # Use its program's name: --auto, and the name goes back to the program's.
    if click_id "desk.website.name.@6" && wait_id "form.nameWindow" 6; then
        sleep 1
        v=$(wax text "Name for window" | grep '^text' | tail -n 1 | sed 's/^text //')
        result "$([ "$v" = "Name for window 2 (front end)" ] && echo PASS || echo FAIL)" "the sheet names the window by its new name" "it reads: ${v:-nothing}"
        snap sheet-again
        since=$(moment)
        click_id "form.useProgramsName"
        expect_log "Use its program's name sends --auto" "$since" \
            "sample ssh: to=alex@192.168.1.20 batch=yes stdin=closed limit=15s run=~/.macmosh/macmosh-host window-name website @6 --auto"
        expect_log "Use its program's name writes its log line" "$since" "window action: nameWindow ok"
        expect_value "the page says the window follows its program again" "page.result" \
            "Window 2 of website follows its program's name again on Attic." 10
        deadline=$((SECONDS + 10))
        v=$(val "desk.website")
        while [[ "$v" != *"claude, zsh, vim"* ]] && [ "$SECONDS" -lt "$deadline" ]; do sleep 0.5; v=$(val "desk.website"); done
        result "$([[ "$v" == *"claude, zsh, vim"* ]] && echo PASS || echo FAIL)" "after the check the row shows the program's name again" "desk.website reads: ${v:-nothing}"
        sleep 1
        snap after-auto
    else
        result FAIL "Name… opens the sheet again" "no sheet for website's window @6"
    fi
    long_window_name

    # blog has one window, so no list: its strip has Name its window….
    click_id "desk.blog" > /dev/null
    sleep 1
    if wax find "desk.blog.name.@3" | grep -q '^found'; then
        result FAIL "a desk with one window lists no window" "desk.blog.name.@3 is there"
    else
        result PASS "a desk with one window lists no window" "no desk.blog.name.@3"
    fi
    v=$(val "button.nameWindow")
    result "$([ "$v" = "Name its window…" ] && echo PASS || echo FAIL)" "a desk with one window has Name its window…" "button.nameWindow reads: ${v:-nothing}"
    snap one-window
    if click_id "button.nameWindow" && wait_id "form.nameWindow" 6; then
        sleep 1
        v=$(wax text "Name for window" | grep '^text' | tail -n 1 | sed 's/^text //')
        result "$([ "$v" = "Name for window 0 (zsh)" ] && echo PASS || echo FAIL)" "Name its window… opens the sheet for its window" "it reads: ${v:-nothing}"
        snap one-window-sheet
        since=$(moment)
        click_id "form.cancel"
        if gone_id "form.nameWindow" 4 && ! applog "$since" | grep -qF "window-name"; then
            result PASS "Cancel closes the sheet and sends nothing" "form.nameWindow gone; no window-name in the log"
        else
            result FAIL "Cancel closes the sheet and sends nothing" "the sheet is there, or a window-name call was sent"
        fi
    else
        result FAIL "Name its window… opens the sheet for its window" "no sheet for blog"
    fi
    stop_app
}

############################################################ ended desks (step 5, issue 152)
# The "window-ended" sample: Attic, Ready, every desk open at launch. The first click on Check now ends the last
# shell of recipes, garden, blog and shop and closes website (permanent), and a permanent desk called shop, closed,
# takes shop's name. The stand-in ssh writes each call's exact remote command to the log and answers desk-new as the
# script would. It fails when the Ended group does not show the four with their three buttons, when Start again or
# Start again and keep it does not send its exact arguments with batch=yes stdin=closed limit=15s, write its log
# line, say what it did and bring the desk back among the desks and out of Ended, when Forget does not remove the
# line or sends anything, when the taken name's buttons are not off with the reason, or when the window closed and
# opened again no longer lists an ended desk. How a picture looks never fails it.
ended_sample() {
    local since v want deadline missing b n cx cy start_moment
    start_moment=$(moment)
    start_app window-ended || return
    if ! open_window; then stop_app; return; fi
    sleep 2

    # MacMosh started with nothing listed: every desk is open, and there is no Ended group.
    if wax find "ended.heading" | grep -q '^found'; then
        result FAIL "nothing is listed as ended at first" "the Ended group is there before any desk ended"
    else
        result PASS "nothing is listed as ended at first" "no ended.heading"
    fi
    snap at-start

    # Check now: the stand-in's shells end. The check after it lists garden, which has no reopen; the others keep
    # their reopen lines, so they get one more check (they may be on their way back after a restart). A second
    # Check now lists them. A background check landing in between can list them early, so that is DIFFERS.
    since=$(moment)
    click_id "button.checkNow" > /dev/null
    if wait_id "ended.garden" 10; then
        if wax find "ended.recipes" | grep -q '^found'; then
            result DIFFERS "a desk with reopen waits one more check" "ended.recipes already there (a background check may have landed)"
        else
            result PASS "a desk with reopen waits one more check" "ended.garden there, no ended.recipes yet"
        fi
    else
        result FAIL "a desk without reopen shows under Ended at the next check" "no ended.garden within 10 s of Check now"
    fi
    sleep 1
    click_id "button.checkNow" > /dev/null
    if wait_id "ended.recipes" 10; then
        result PASS "a desk whose last shell exited shows under Ended" "ended.recipes found"
    else
        result FAIL "a desk whose last shell exited shows under Ended" "no ended.recipes within 10 s of Check now"
        snap no-ended
        stop_app
        return
    fi
    sleep 1
    missing=""
    for v in blog garden recipes shop; do
        wax find "ended.$v" | grep -q '^found' || missing="$missing $v"
    done
    v=$(val "ended.heading")
    if [ -z "$missing" ] && [ "$v" = "Ended" ]; then
        result PASS "the Ended group lists the four desks that ended" "heading reads: $v; blog, garden, recipes and shop are there"
    else
        result FAIL "the Ended group lists the four desks that ended" "heading reads: ${v:-nothing}; missing:${missing:- none}"
    fi
    # website is permanent: it stays among the desks as closed, and is not under Ended.
    v=$(val "desk.website")
    if [[ "$v" == *"Closed"* ]] && ! wax find "ended.website" | grep -q '^found'; then
        result PASS "a permanent desk that closed stays among the desks" "desk.website reads: $v; no ended.website"
    else
        result FAIL "a permanent desk that closed stays among the desks" "desk.website reads: ${v:-nothing}"
    fi
    missing=""
    for b in "startAgain:Start again" "keep:Start again and keep it" "forget:Forget"; do
        v=$(val "ended.recipes.${b%%:*}")
        [ "$v" = "${b#*:}" ] || missing="$missing [${b%%:*}: ${v:-none}]"
    done
    if [ -z "$missing" ]; then
        result PASS "an ended desk has its three buttons" "Start again, Start again and keep it, Forget"
    else
        result FAIL "an ended desk has its three buttons" "missing or wrong:$missing"
    fi
    v=$(val "ended.recipes.second")
    # shellcheck disable=SC2016,SC2088 # the row's text, a tilde and $HOME as shown
    want='~/Development/my recipes · started with claude --continue "fix it" $HOME'
    result "$([ "$v" = "$want" ] && echo PASS || echo FAIL)" "the row has the folder and its startup command" "it reads: ${v:-nothing}"
    v=$(val "ended.recipes.when")
    result "$([[ "$v" == "ended about "[0-2][0-9]:[0-5][0-9] ]] && echo PASS || echo FAIL)" "the row says when it ended" "it reads: ${v:-nothing}"
    # Look step 2: Forget stands apart, at the right of its row, as Remove… does in a desk's details. A finding.
    local kr fl
    kr=$(right "ended.recipes.keep"); fl=$(box "ended.recipes.forget" | awk 'NF == 4 { print $1 }')
    if [ -n "$kr" ] && [ -n "$fl" ] && [ "$fl" -ge $((kr + 24)) ]; then
        result PASS "Forget stands apart at the right of its row" "Start again and keep it ends at $kr, Forget starts at $fl"
    else
        result DIFFERS "Forget stands apart at the right of its row" "Start again and keep it ends at ${kr:-?}, Forget starts at ${fl:-?}"
    fi
    snap ended-group

    # shop's name is held by a permanent desk again: both Start again buttons are off, with the reason; Forget is not.
    v="$(wax enabled "ended.shop.startAgain" | grep '^enabled' | tail -n 1) $(wax enabled "ended.shop.keep" | grep '^enabled' | tail -n 1) $(wax enabled "ended.shop.forget" | grep '^enabled' | tail -n 1)"
    if [ "$v" = "enabled false enabled false enabled true" ]; then
        result PASS "a taken name has both Start again buttons off" "Start again, keep it, Forget: $v"
    else
        result FAIL "a taken name has both Start again buttons off" "Start again, keep it, Forget: $v"
    fi
    expect_value "a taken name says why under its buttons" "ended.shop.note" "Attic already has a desk called shop." 3
    # shop's command is longer than its line: the picture shows the line cut, and the text behind it is whole. A
    # finding: whether the accessibility value of a cut line is the whole text is not something the app decides.
    v=$(val "ended.shop.second")
    # shellcheck disable=SC2088 # the row's text, a tilde and all
    want="~/Development/shop · started with npm run dev -- --port 4000 --host 0.0.0.0 --open --watch --verbose --log-level debug --no-cache"
    result "$([ "$v" = "$want" ] && echo PASS || echo DIFFERS)" "a long command is whole behind its cut line" "it reads: ${v:-nothing}"

    # Start again on recipes: one call, the same desk, its folder with a space and its command as one argument.
    since=$(moment)
    click_id "ended.recipes.startAgain" > /dev/null
    sleep 0.6
    v=$(val "ended.recipes.startAgain")
    result "$([ "$v" = "Starting…" ] && echo PASS || echo DIFFERS)" "Start again says Starting… while it runs" "it reads: ${v:-nothing}"
    snap starting
    # shellcheck disable=SC2016 # the remote command as sent, $HOME and all
    want='sample ssh: to=alex@192.168.1.20 batch=yes stdin=closed limit=15s run=~/.macmosh/macmosh-host desk-new recipes '"'"'/Users/alex/Development/my recipes'"'"' --reopen --command '"'"'claude --continue "fix it" $HOME'"'"
    expect_log "Start again sends the exact arguments" "$since" "$want"
    expect_log "Start again writes its log line" "$since" "window action: startAgain ok"
    expect_value "the page says what Start again did" "page.result" "Started recipes again on Attic." 10
    expect_log "Start again opens a tab on the desk" "$since" "menu action: tab connect (window)"
    if gone_id "ended.recipes" 8 && wait_id "desk.recipes" 8; then
        result PASS "after Start again the desk is among the desks and gone from Ended" "desk.recipes there, ended.recipes gone"
    else
        result FAIL "after Start again the desk is among the desks and gone from Ended" "ended.recipes still there, or no desk.recipes"
    fi
    deadline=$((SECONDS + 8))
    v=$(val "desk.recipes.status")
    while [ "$v" != "No tab" ] && [ "$SECONDS" -lt "$deadline" ]; do sleep 0.5; v=$(val "desk.recipes.status"); done
    result "$([ "$v" = "No tab" ] && echo PASS || echo FAIL)" "once the check lands the desk's row is the check's" "desk.recipes.status reads: ${v:-nothing}"
    sleep 1
    snap after-start-again

    # Start again and keep it on garden: its own flags (no reopen, keep running) and --permanent.
    since=$(moment)
    click_id "ended.garden.keep" > /dev/null
    expect_log "Start again and keep it sends --permanent with the desk's flags" "$since" \
        "sample ssh: to=alex@192.168.1.20 batch=yes stdin=closed limit=15s run=~/.macmosh/macmosh-host desk-new garden /Users/alex/Development/garden --no-reopen --keep --permanent --command claude"
    expect_value "the page says it is kept" "page.result" "Started garden again on Attic. It is kept when it exits." 10
    if gone_id "ended.garden" 8 && wait_id "desk.garden" 8; then
        result PASS "after Start again and keep it the desk is back" "desk.garden there, ended.garden gone"
    else
        result FAIL "after Start again and keep it the desk is back" "ended.garden still there, or no desk.garden"
    fi
    sleep 2
    snap after-keep

    # Forget on blog: the line goes and nothing is sent.
    since=$(moment)
    click_id "ended.blog.forget" > /dev/null
    if gone_id "ended.blog" 5; then
        result PASS "Forget removes the line" "ended.blog gone"
    else
        result FAIL "Forget removes the line" "ended.blog still there"
    fi
    expect_log "Forget writes its log line" "$since" "window action: forget ok"
    sleep 2
    n=$(applog "$since" | grep -cF "sample ssh:")
    result "$([ "$n" -eq 0 ] && echo PASS || echo FAIL)" "Forget sends nothing" "sample ssh lines since the click: $n"
    snap after-forget

    # The log lines the actions added name no desk, folder or command.
    v=$(applog "$start_moment" | grep -F "window action: " | grep -E "recipes|garden|blog|shop|claude" | head -n 1)
    result "$([ -z "$v" ] && echo PASS || echo FAIL)" "the action log lines have fixed words only" "${v:-no desk, folder or command in them}"

    # Closed and opened again, the window still lists shop: the list is the app's, not the window's.
    read -r _ cx cy <<< "$(wax close | grep '^close' | tail -n 1)"
    if [ -z "${cy:-}" ]; then
        result NOT-SHOWN "the window opened again still lists the ended desk" "no close button found"
        stop_app
        return
    fi
    say "click on the close button at $cx,$cy"
    tool click "$cx" "$cy" > /dev/null
    if [ "$(wait_windows 0 5)" -ne 0 ]; then
        result NOT-SHOWN "the window opened again still lists the ended desk" "the window did not close"
        stop_app
        return
    fi
    sleep 3
    if open_window && wait_id "ended.shop" 6; then
        v=$(val "ended.shop.note")
        result PASS "the window opened again still lists the ended desk" "ended.shop there; its note reads: ${v:-nothing}"
    else
        result FAIL "the window opened again still lists the ended desk" "no ended.shop after opening the window again"
    fi
    sleep 1
    snap reopened
    stop_app
}

############################################################ the Settings page (issue 157)
# settings_file <name>: the window-settings sample's own saved file (workhorses.json or settings.json), in the
# temporary folder named after the app's process (SampleSettings.paths); nothing, and false, when it is not there.
settings_file() {
    local d
    for d in "$(getconf DARWIN_USER_TEMP_DIR 2>/dev/null)" "${TMPDIR:-}"; do
        [ -n "$d" ] || continue
        if [ -d "${d%/}/macmosh-sample-settings-$app_pid/support" ]; then
            echo "${d%/}/macmosh-sample-settings-$app_pid/support/$1"
            return 0
        fi
    done
    return 1
}

# json_changes <before> <after>: every field that differs between the two saved files, as "attic.mode=tabs" (or
# "attic.projectsFolder=(gone)"), joined with |; for settings.json, "terminal=iterm2". A missing file reads as empty.
json_changes() {
    python3 -I - "$1" "$2" <<'PY'
import json, sys
def read(path):
    try:
        with open(path) as f:
            d = json.load(f)
    except Exception:
        return {}
    if isinstance(d, dict) and "workhorses" in d:
        return {w.get("id", "?") + "." + k: v for w in d["workhorses"] for k, v in w.items()}
    return d if isinstance(d, dict) else {}
a, b = read(sys.argv[1]), read(sys.argv[2])
out = []
for k in sorted(set(a) | set(b)):
    if a.get(k) != b.get(k):
        v = b.get(k, "(gone)")
        out.append(k + "=" + (v if isinstance(v, str) else json.dumps(v)))
print("|".join(out))
PY
}

# setting_lines <since>: the Settings page's log lines since then, one per line.
setting_lines() { applog "$1" | grep -F "window action: setting" | sed 's/.*window action: /window action: /'; }

# settings_step <check> <file> <want changes> <want log: ok, failed or none> <command...>: keeps a copy of the
# sample's file, runs the command (a click or keys), waits for the page's log line, and checks that the file
# changed in exactly those fields (none for "") and that exactly that one line was logged. The lines are counted
# from the start of the page ($settings_since), so a line of the step before is never taken for this one's.
settings_step() {
    local check=$1 name=$2 want=$3 line=$4 file before got lines n0 deadline want_lines=""
    shift 4
    if ! file=$(settings_file "$name"); then
        result NOT-SHOWN "$check" "the sample's $name was not found"
        return 1
    fi
    before=$(mktemp)
    cp "$file" "$before" 2>/dev/null || : > "$before"
    n0=$(setting_lines "$settings_since" | wc -l | tr -d ' ')
    "$@"
    if [ "$line" = none ]; then
        sleep 2.5
    else
        deadline=$((SECONDS + 10))
        while [ "$(setting_lines "$settings_since" | wc -l | tr -d ' ')" -le "$n0" ] && [ "$SECONDS" -lt "$deadline" ]; do
            sleep 0.5
        done
    fi
    sleep 0.5
    got=$(json_changes "$before" "$file")
    lines=$(setting_lines "$settings_since" | tail -n +"$((n0 + 1))" | tr '\n' '|' | sed 's/|$//')
    [ "$line" != none ] && want_lines="window action: setting $line"
    if [ "$got" = "$want" ] && [ "$lines" = "$want_lines" ]; then
        result PASS "$check" "changed: ${got:-nothing}; log: ${lines:-nothing}"
    else
        result FAIL "$check" "changed: ${got:-nothing} (expected: ${want:-nothing}); log: ${lines:-nothing} (expected: ${want_lines:-nothing})"
    fi
    mv "$before" "$OUT/ax/.settings-before-$shotn.json" 2>/dev/null || true
}

# click_radio <group identifier> <title>: a posted click on that choice of a radio group.
click_radio() {
    local found x y
    found=$(wax radio "$1" "$2" | grep '^found' | tail -n 1)
    read -r _ x y _ <<< "$found"
    if [ -z "${y:-}" ]; then
        say "no radio [$2] in [$1]"
        return 1
    fi
    say "click on radio [$2] of [$1] at $x,$y"
    tool click "$x" "$y" > /dev/null
}

# chosen <group identifier>: the title of its chosen radio button, or "none".
chosen() { wax chosen "$1" | grep '^chosen' | tail -n 1 | sed 's/^chosen //'; }

# type_and <identifier> <text> <tab|return>: empties the field, types the text, then leaves it with Tab or Return.
type_and() {
    clear_field "$1" || return 1
    [ -n "$2" ] && tool type "$2" > /dev/null
    sleep 0.3
    if [ "$3" = tab ]; then tool keys 48 1 100 > /dev/null; else tool keys 36 1 100 > /dev/null; fi
}

# The "window-settings" sample: Attic (Mosh, Adaptive, ~/Development) and Spare (Tabs, Never), Ready, whose
# settings the page saves into the sample's own saved list in a temporary folder. It fails when the page does not
# open from the sidebar, a click on a choice or an edit of a field does not save exactly that field with its log
# line, a bad value is not refused with its sentence or saves anything, the name does not show in the sidebar and
# the workhorse's page at once, a button does not send its exact tab command, Command-V does not paste into the
# Name field, a click or key press on the page sets off the menu-open signal, or the window opened again does not
# show the saved values. How a picture looks never fails it.
settings_sample() {
    local page_since v want file
    start_app window-settings || return
    if ! open_window; then stop_app; return; fi
    sleep 1
    if file=$(settings_file workhorses.json); then
        result PASS "the sample's saved list is in its own temporary folder" "$(basename "$(dirname "$(dirname "$file")")")/support/workhorses.json"
    else
        result FAIL "the sample's saved list is in its own temporary folder" "no macmosh-sample-settings-$app_pid folder"
        stop_app
        return
    fi
    page_since=$(moment)
    settings_since=$page_since
    if ! click_id "sidebar.settings" || ! wait_id "settings.heading" 6; then
        result FAIL "Settings in the sidebar opens the page" "no settings.heading"
        snap no-settings
        stop_app
        return
    fi
    sleep 1
    result PASS "Settings in the sidebar opens the page" "settings.heading found"
    snap page
    v="$(val settings.attic.heading)|$(val settings.spare.heading)"
    result "$([ "$v" = "Attic|Spare" ] && echo PASS || echo FAIL)" "one section per workhorse, in saved order" "headings: $v"
    v="$(chosen settings.thisMac.terminal)|$(chosen settings.attic.connection)|$(chosen settings.attic.prediction)|$(chosen settings.spare.connection)|$(chosen settings.spare.prediction)"
    result "$([ "$v" = "Pick for me|Mosh|Adaptive|Tabs|Never" ] && echo PASS || echo FAIL)" "the choices show what is saved" "$v"
    expect_value "an empty projects folder says what New desk does then" "settings.spare.projectsFolder.line" \
        "Not set. New desk has no folders to list until it is." 3
    v=$(val settings.thisMac.pickForMe)
    result "$([[ "$v" == "Pick for me opens tabs in iTerm2 when it is in the Applications folder, and in Terminal when it isn't. On this Mac that is "* ]] && echo PASS || echo FAIL)" "the line says what Pick for me picks" "${v:-nothing}"

    # The terminal: each choice saves settings.json's one field and nothing in the saved list.
    settings_step "Terminal: iTerm2 is saved" settings.json "terminal=iterm2" ok click_radio settings.thisMac.terminal "iTerm2"
    settings_step "Terminal: Terminal is saved" settings.json "terminal=appleTerminal" ok click_radio settings.thisMac.terminal "Terminal"
    settings_step "Terminal: Pick for me is saved" settings.json "terminal=(gone)" ok click_radio settings.thisMac.terminal "Pick for me"
    expect_value "the terminal's line says what uses it next" "settings.thisMac.terminal.line" "Saved. Used by the next tab MacMosh opens." 3

    # Attic's connection and typing prediction: each click saves that one field of Attic.
    settings_step "Connection: Tabs is saved" workhorses.json "attic.mode=tabs" ok click_radio settings.attic.connection "Tabs"
    expect_value "the line under Connection is the chosen one's" "settings.attic.connection.about" \
        "Every window of a desk as a real iTerm2 tab. When the Wi-Fi drops or the lid closes, the tabs close; your work keeps running, and reconnecting brings the tabs back. Needs iTerm2." 3
    settings_step "Connection: Plain ssh is saved" workhorses.json "attic.mode=ssh" ok click_radio settings.attic.connection "Plain ssh"
    snap after-connection
    settings_step "Connection: Mosh is saved" workhorses.json "attic.mode=mosh" ok click_radio settings.attic.connection "Mosh"
    for v in Always Never Experimental Adaptive; do
        want=$(tr '[:upper:]' '[:lower:]' <<< "$v")
        settings_step "Typing prediction: $v is saved" workhorses.json "attic.prediction=$want" ok \
            click_radio settings.attic.prediction "$v"
    done
    expect_value "the saved line says what uses it next" "settings.attic.prediction.line" "Saved. Used by the next Mosh tab you open." 3
    # A click on the choice already saved writes nothing and logs nothing.
    settings_step "a click on the saved choice saves nothing" workhorses.json "" none click_radio settings.attic.connection "Mosh"

    # The name: typed, then the field left with Tab. The sidebar and the page's heading show it at once.
    settings_step "a new name is saved when the field is left" workhorses.json "attic.name=Loft" ok type_and settings.attic.name "Loft" tab
    expect_value "the name's line says what uses it next" "settings.attic.name.line" "Saved. The menu shows it at its next check." 3
    expect_value "the section's heading shows the new name" "settings.attic.heading" "Loft" 3
    v=$(val sidebar.attic)
    result "$([[ "$v" == *Loft* ]] && echo PASS || echo DIFFERS)" "the sidebar shows the new name at once" "sidebar.attic reads: ${v:-nothing}"
    snap after-name

    # An empty name: its sentence, nothing saved, and the field back to the saved name.
    settings_step "an empty name is refused and saves nothing" workhorses.json "" failed type_and settings.attic.name "" return
    expect_value "an empty name says what is wrong" "settings.attic.name.line" "The name can't be empty." 3
    expect_value "the refused field goes back to the saved name" "settings.attic.name" "Loft" 3
    snap refused-name

    # Command-V pastes into the Name field, and Return saves it.
    printf '%s' "Attic" | pbcopy
    if [ "$(pbpaste)" = "Attic" ]; then
        clear_field "settings.attic.name"
        tool chord v cmd > /dev/null
        sleep 0.8
        v=$(val settings.attic.name)
        result "$([ "$v" = "Attic" ] && echo PASS || echo FAIL)" "Command-V pastes into the Name field" "the field reads: ${v:-nothing}"
        settings_step "the pasted name is saved with Return" workhorses.json "attic.name=Attic" ok tool keys 36 1 100
    else
        result NOT-SHOWN "Command-V pastes into the Name field" "the clipboard was not set"
    fi

    # The projects folder, saved and then emptied.
    # shellcheck disable=SC2088 # the text typed, a tilde and all
    settings_step "a projects folder is saved with Return" workhorses.json "attic.projectsFolder=~/Projects" ok \
        type_and settings.attic.projectsFolder "~/Projects" return
    expect_value "the folder's line says what uses it next" "settings.attic.projectsFolder.line" "Saved. Used by the next New desk." 3
    settings_step "an emptied projects folder is saved as not set" workhorses.json "attic.projectsFolder=(gone)" ok \
        type_and settings.attic.projectsFolder "" return
    expect_value "the emptied folder's line says so" "settings.attic.projectsFolder.line" \
        "Saved. New desk has no folders to list until it is set." 3

    # Advanced, closed at first, holds the ssh key file.
    if wax find "settings.attic.keyFile" | grep -q '^found'; then
        result FAIL "Advanced is closed at first" "settings.attic.keyFile is there"
    else
        result PASS "Advanced is closed at first" "no settings.attic.keyFile"
    fi
    if click_id "settings.attic.advanced" && wait_id "settings.attic.keyFile" 4; then
        result PASS "Advanced opens with a click" "settings.attic.keyFile found"
        v=$(val settings.attic.keyFile)
        result "$([ -z "$v" ] && echo PASS || echo FAIL)" "the key file is empty for MacMosh's own key" "it reads: ${v:-nothing}"
        snap advanced-open
        # shellcheck disable=SC2088 # the text typed, a tilde and all
        settings_step "a key file with no file there is refused" workhorses.json "" failed \
            type_and settings.attic.keyFile "~/.ssh/no_such_key" return
        expect_value "a missing key file says what is wrong" "settings.attic.keyFile.line" \
            "There is no file at ~/.ssh/no_such_key on this Mac, so it was not saved." 3
        snap refused-key
        settings_step "a key file that is not a full path is refused" workhorses.json "" failed \
            type_and settings.attic.keyFile "keys/work" return
        expect_value "a relative key file says what is wrong" "settings.attic.keyFile.line" \
            "A key file's path is full, starting with /, or starts with ~." 3
        # An empty file in ~/.ssh, on a GitHub runner only: never in a person's own ~/.ssh.
        if [ -n "${GITHUB_ACTIONS:-}" ]; then
            mkdir -p "$HOME/.ssh" && : > "$HOME/.ssh/sample_work_key"
            # shellcheck disable=SC2088 # the text typed, a tilde and all
            settings_step "a key file that is there is saved as typed" workhorses.json "attic.identityFile=~/.ssh/sample_work_key" ok \
                type_and settings.attic.keyFile "~/.ssh/sample_work_key" return
            settings_step "an emptied key file is MacMosh's own key again" workhorses.json "attic.identityFile=(gone)" ok \
                type_and settings.attic.keyFile "" return
            expect_value "the emptied key file's line says so" "settings.attic.keyFile.line" \
                "Saved. MacMosh's own key is used from the next check on." 3
        else
            result NOT-SHOWN "a key file that is there is saved as typed" "not on a GitHub runner, so no file is made in ~/.ssh"
        fi
    else
        result FAIL "Advanced opens with a click" "no settings.attic.keyFile after the click"
    fi

    # The two buttons open today's tabs through the menu's path.
    local since
    since=$(moment)
    click_id "settings.attic.checklist" > /dev/null
    expect_ran "Run the checklist… opens the checklist's tab" "$since" "tab prepare attic --pause"
    sleep 1
    since=$(moment)
    click_id "settings.attic.remove" > /dev/null
    expect_ran "Remove MacMosh from this workhorse… opens remove's tab" "$since" "tab remove attic"

    # No click or key press on the page set off the menu-open signal.
    v=$(applog "$page_since" | grep -cE "menu opened|menu tracking")
    if [ "$v" -eq 0 ]; then
        result PASS "the page sets off no menu-open signal" "no 'menu opened' or 'menu tracking' line"
    else
        result FAIL "the page sets off no menu-open signal" "$v line(s): $(applog "$page_since" | grep -E "menu opened|menu tracking" | sed 's/.*menu/menu/' | tr '\n' '|')"
    fi
    v=$(applog "$page_since" | grep -F "window action: setting" | grep -vE "window action: setting (ok|failed)$" | head -n 1)
    result "$([ -z "$v" ] && echo PASS || echo FAIL)" "the page's log lines have fixed words only" "${v:-only 'setting ok' and 'setting failed'}"

    # Text typed and not left, then another sidebar line chosen: what the page shows afterwards is what is saved.
    local typed_since cx cy rest_since signals
    typed_since=$(moment)
    rest_since=$typed_since
    clear_field "settings.spare.name" && tool type "Typed" > /dev/null
    sleep 0.5
    click_id "sidebar.attic" > /dev/null
    sleep 1.5
    v=$(val page.headline)
    result "$([ "$v" = "Attic · Ready" ] && echo PASS || echo FAIL)" "the workhorse's page heading has the saved name" "page.headline reads: ${v:-nothing}"
    click_id "sidebar.settings" > /dev/null
    wait_id "settings.spare.name" 5 > /dev/null
    sleep 1
    v=$(val settings.spare.name)
    file=$(settings_file workhorses.json)
    want=$(python3 -I -c 'import json,sys; print(next(w["name"] for w in json.load(open(sys.argv[1]))["workhorses"] if w["id"] == "spare"))' "$file" 2>/dev/null)
    result "$([ "$v" = "$want" ] && echo PASS || echo FAIL)" "text not left before another sidebar line shows as saved or not at all" \
        "the field reads: ${v:-nothing}; saved: ${want:-?}; log: $(setting_lines "$typed_since" | tr '\n' '|' | sed 's/|$//')"

    # Text typed and not left, then the window closed and opened again: the saved values, and the typed text only
    # if it was saved.
    typed_since=$(moment)
    # shellcheck disable=SC2088 # the text typed, a tilde and all
    clear_field "settings.spare.projectsFolder" && tool type "~/Typed" > /dev/null
    sleep 0.5
    # The menu-open signal, counted up to the close: opening the window again goes through the menu.
    signals=$(applog "$rest_since" | grep -cE "menu opened|menu tracking")
    read -r _ cx cy <<< "$(wax close | grep '^close' | tail -n 1)"
    if [ -z "${cy:-}" ]; then
        result NOT-SHOWN "the window opened again shows the saved values" "no close button found"
        stop_app
        return
    fi
    say "click on the close button at $cx,$cy"
    tool click "$cx" "$cy" > /dev/null
    if [ "$(wait_windows 0 5)" -ne 0 ]; then
        result NOT-SHOWN "the window opened again shows the saved values" "the window did not close"
        stop_app
        return
    fi
    sleep 2
    # What the file and the log hold while the window is closed: told, never failed, as either is sound.
    want=$(python3 -I -c 'import json,sys; print(next(w.get("projectsFolder", "") for w in json.load(open(sys.argv[1]))["workhorses"] if w["id"] == "spare"))' "$file" 2>/dev/null)
    result PASS "while the window is closed, text typed and not sent is saved or not" \
        "saved folder: ${want:-nothing}; log: $(setting_lines "$typed_since" | tr '\n' '|' | sed 's/|$//')"
    if ! open_window || ! click_id "sidebar.settings" || ! wait_id "settings.heading" 6; then
        result FAIL "the window opened again shows the saved values" "the Settings page did not open again"
        stop_app
        return
    fi
    rest_since=$(moment)
    sleep 1.5
    want=$(python3 -I -c 'import json,sys; print(next(w.get("projectsFolder", "") for w in json.load(open(sys.argv[1]))["workhorses"] if w["id"] == "spare"))' "$file" 2>/dev/null)
    v=$(val settings.spare.projectsFolder)
    result "$([ "$v" = "$want" ] && echo PASS || echo FAIL)" "text not left before the window closed shows as saved or not at all" \
        "the field reads: ${v:-nothing}; saved: ${want:-nothing}; log: $(setting_lines "$typed_since" | tr '\n' '|' | sed 's/|$//')"
    v="$(val settings.attic.name)|$(chosen settings.attic.connection)|$(chosen settings.attic.prediction)|$(val settings.attic.projectsFolder)|$(chosen settings.thisMac.terminal)"
    result "$([ "$v" = "Attic|Mosh|Adaptive||Pick for me" ] && echo PASS || echo FAIL)" "the window opened again shows the saved values" "$v"
    snap reopened

    # A change made outside the page (as `macmosh set` would make it) shows at the next check, without leaving it.
    local outside_since
    outside_since=$(moment)
    python3 -I - "$file" <<'PY'
import json, os, sys
path = sys.argv[1]
with open(path) as f:
    d = json.load(f)
for w in d["workhorses"]:
    if w["id"] == "attic":
        w["projectsFolder"] = "~/Elsewhere"
with open(path + ".w6", "w") as f:
    json.dump(d, f)
os.replace(path + ".w6", path)
PY
    # shellcheck disable=SC2088 # the text expected, a tilde and all
    expect_value "the page follows a change made outside it at the next check" "settings.attic.projectsFolder" "~/Elsewhere" 6
    v=$(setting_lines "$outside_since" | tr '\n' '|' | sed 's/|$//')
    result "$([ -z "$v" ] && echo PASS || echo FAIL)" "a change made outside the page logs nothing of the page's" "log: ${v:-nothing}"

    # A key file typed and not sent, then another sidebar line chosen: it is refused as focus leaves, and the page
    # opened again still says why, under the field, with Advanced open by itself.
    if click_id "settings.attic.advanced" && wait_id "settings.attic.keyFile" 4; then
        typed_since=$(moment)
        # shellcheck disable=SC2088 # the text typed, a tilde and all
        clear_field "settings.attic.keyFile" && tool type "~/.ssh/still_no_key" > /dev/null
        sleep 0.5
        click_id "sidebar.attic" > /dev/null
        sleep 1.5
        click_id "sidebar.settings" > /dev/null
        if wait_id "settings.attic.keyFile.line" 5; then
            expect_value "a key file refused as the page was left is still explained there" "settings.attic.keyFile.line" \
                "There is no file at ~/.ssh/still_no_key on this Mac, so it was not saved." 3
            v=$(val settings.attic.keyFile)
            result "$([ -z "$v" ] && echo PASS || echo FAIL)" "the refused key file's field shows what is stored" \
                "it reads: ${v:-nothing}; log: $(setting_lines "$typed_since" | tr '\n' '|' | sed 's/|$//')"
            snap refusal-kept
        else
            result FAIL "a key file refused as the page was left is still explained there" \
                "no settings.attic.keyFile.line; log: $(setting_lines "$typed_since" | tr '\n' '|' | sed 's/|$//')"
            snap refusal-lost
        fi
    else
        result FAIL "a key file refused as the page was left is still explained there" "Advanced did not open"
    fi

    # Again, for the steps after the first count, leaving out the menu that opened the window again.
    v=$((signals + $(applog "$rest_since" | grep -cE "menu opened|menu tracking")))
    result "$([ "$v" -eq 0 ] && echo PASS || echo FAIL)" "the page sets off no menu-open signal, to its last step" \
        "$v 'menu opened' or 'menu tracking' line(s), leaving out the menu that opened the window again"
    stop_app
}

############################################################ the run
say "driving the window of $APP on $os ($(sw_vers -productVersion))"
tool preflight > /dev/null
lim 10 "$TOOL" move 600 500 > /dev/null

forms_sample
forms_older_script
window_keys
window_names_sample
six_desks
windows_sample
ready_then_locked
two_workhorses
sidebar_sample
long_folder
unreadable_list
no_workhorses
ended_sample
settings_sample

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
