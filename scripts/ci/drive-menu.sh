#!/bin/bash
# CI only (.github/workflows/menu-pictures.yml): starts the debug app with each sample menu
# (MACMOSH_SAMPLE_MENU, issue #113), opens its menu with posted pointer events (menutool), takes a
# picture at each step, and checks the app's log. It moves the pointer and presses keys: never run it
# on your own Mac. It needs scripts/build-app.sh --debug and the built menutool first.
#
#   MENU_OUT=<folder> scripts/ci/drive-menu.sh
#
# What it leaves in MENU_OUT:
#   pictures/<os>-<sample>-<nn>-<step>.png   a screenshot of the whole screen at each step
#   ax/<os>-<sample>-<nn>-<step>.txt         the menu's rows as the accessibility tree reads them
#   driver.log    every step, menutool's and System Events' answers
#   app-log.txt   the app's own log lines (MenuLog) for the whole run
#   results.tsv   one line per check: PASS, FAIL, DIFFERS (a finding that does not fail the job) or
#                 NOT-SHOWN (the step could not be done, so nothing is known)
#
# The job fails only when the app does not start, its menu does not open, a click runs the wrong row
# or none, an open submenu closes under the pointer, or a held change is shown before the clicked
# row has run. How a picture looks never fails it.
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
OUT=${MENU_OUT:?set MENU_OUT to the folder for pictures and logs}
APP=${MENU_APP:-$root/dist/debug/MacMosh.app}
TOOL=${MENU_TOOL:-$root/dist/debug/menutool}
AX="$here/menu-ax.applescript"
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
# A moment for `log show --start`: lines from this second on.
moment() { date '+%Y-%m-%d %H:%M:%S'; }

# result <PASS|FAIL|DIFFERS|NOT-SHOWN> <check> <detail>
result() {
    printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$os" "$sample" "$2" "$3" >> "$RESULTS"
    say "RESULT $1 [$sample] $2: $3"
    if [ "$1" = FAIL ]; then failures=$((failures + 1)); fi
}

tool() { lim 20 "$TOOL" "$@" 2>&1 | tee -a "$LOG"; }
count() { lim 10 "$TOOL" count 2>/dev/null || echo 0; }

# ax <args>: one System Events call; its answer goes to the log and to stdout.
ax() {
    local r st
    r=$(lim 25 osascript "$AX" "$@" 2>&1)
    st=$?
    printf '%s\n' "$r" | sed "s/^/$(now) ax[$1] /" >> "$LOG"
    [ "$st" -ne 0 ] && say "ax[$1] exit=$st"
    printf '%s\n' "$r"
}

# find_xy <place> <prefix>: "index x y name" of that row.
find_xy() { ax find "$1" "$2" | grep '^found' | tail -n 1 | cut -d' ' -f2-; }

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

# wait_menus <want> <seconds>: until at least <want> menu windows are on screen (0: until none);
# prints how many there are then.
wait_menus() {
    local want=$1 deadline n
    deadline=$(($(date +%s) + $2))
    while :; do
        n=$(count)
        if [ "$want" -eq 0 ]; then [ "$n" -eq 0 ] && break; else [ "$n" -ge "$want" ] && break; fi
        [ "$(date +%s)" -ge "$deadline" ] && break
        sleep 0.2
    done
    printf '%s drv menu windows: want %s, have %s\n' "$(now)" "$want" "$n" >> "$LOG"
    echo "$n"
}

# snap <step>: a picture of the screen and the top menu's rows, numbered within the sample.
snap() {
    shotn=$((shotn + 1))
    local name
    name=$(printf '%s-%s-%02d-%s' "$os" "$sample" "$shotn" "$1")
    lim 15 screencapture -x "$OUT/pictures/$name.png" >> "$LOG" 2>&1 || say "screencapture failed for $name"
    if [ "$(count)" -ge 1 ]; then ax names top > "$OUT/ax/$name.txt"; fi
    say "picture $name.png"
}

bar_centre() {
    local b pos size
    b=$(ax barpos | grep '^bar' | tail -n 1)
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

# start_app <sample>: true once the app has logged that it shows the sample.
start_app() {
    sample=$1
    shotn=0
    local since support
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
    sleep 1
    result PASS "the app starts" "pid $app_pid"
}

stop_app() {
    close_menu
    [ -n "$app_pid" ] && kill "$app_pid" 2>/dev/null
    [ -n "$app_pid" ] && wait "$app_pid" 2>/dev/null
    app_pid=""
    sleep 1
}

# opened_or_fail <when>: opens the menu, or records that it did not open.
opened_or_fail() {
    if open_menu; then
        result PASS "the menu opens ($1)" "menu windows=$(count)"
        return 0
    fi
    result FAIL "the menu opens ($1)" "no menu window within 6 s of the click"
    return 1
}

# rest_on <row prefix> <step>: rests the pointer on a top-level row and takes a picture of its submenu.
rest_on() {
    local idx x y name n
    read -r idx x y name <<< "$(find_xy top "$1")"
    if [ -z "${y:-}" ]; then
        result NOT-SHOWN "rest on [$1]" "no such row in the accessibility tree"
        return 1
    fi
    say "rest on row $idx [$name] at $x,$y"
    tool move "$x" "$y" > /dev/null
    sleep 1
    n=$(wait_menus 2 3)
    if [ "$n" -ge 2 ]; then
        result PASS "resting on [$1] opens its submenu" "menu windows=$n"
    else
        result DIFFERS "resting on [$1] opens its submenu" "menu windows=$n"
    fi
    snap "$2"
    ax dump "$1" > "$OUT/ax/$(printf '%s-%s-%02d-%s' "$os" "$sample" "$shotn" "$2")-submenu.txt"
    ax selected top > /dev/null
}

# expect_row <check> <moment> <row id>: the app's log since then names exactly that row.
expect_row() {
    local ran
    wait_log "$2" "sample row ran: " 10 > /dev/null
    sleep 1
    ran=$(applog "$2" | grep -F "sample row ran: " | sed 's/.*sample row ran: //' | tr '\n' ' ' | sed 's/ $//')
    if [ -z "$ran" ]; then
        result FAIL "$1" "no row ran (expected $3)"
    elif [ "$ran" = "$3" ]; then
        result PASS "$1" "the log says row $ran ran"
    else
        result FAIL "$1" "expected $3, the log says: $ran"
    fi
}

# click_in_submenu <parent prefix> <line prefix>: with the submenu open, moves sideways into it at the
# parent row's height (onto its first line, so it stays open) and clicks the line. Prints the x y it
# clicked, or nothing.
click_in_submenu() {
    local idx py sidx sx sy rest
    read -r idx _ py rest <<< "$(find_xy top "$1")"
    read -r sidx sx sy rest <<< "$(find_xy "$1" "$2")"
    if [ -z "${sy:-}" ] || [ -z "${py:-}" ]; then
        say "no position for [$2] in [$1]"
        return 1
    fi
    say "click line $sidx [$rest] of [$1] at $sx,$sy (in from $sx,$py)"
    tool move "$sx" "$py" > /dev/null
    tool click "$sx" "$sy" > /dev/null
}

############################################################ the samples
plain_sample() {
    start_app "$1" || return
    if opened_or_fail "first click"; then snap menu; fi
    stop_app
}

six_desks() {
    local since n idx x y name
    start_app six-desks || return
    if ! opened_or_fail "first click"; then stop_app; return; fi
    snap menu
    rest_on "Workhorse" workhorse-submenu
    rest_on "   website" open-desk-submenu
    rest_on "   garden" closed-desk-submenu

    # A click on a desk's row opens that desk: its primary action, here a log line naming the row.
    read -r idx x y name <<< "$(find_xy top "   website")"
    since=$(moment)
    say "click on row $idx [$name] at $x,$y"
    tool click "$x" "$y" > /dev/null
    expect_row "a click on a desk's row runs that desk's row" "$since" "desk:workhorse:website"
    n=$(wait_menus 0 2)
    if [ "$n" -eq 0 ]; then
        result PASS "the menu closes after the click" "menu windows=0"
    else
        result DIFFERS "the menu closes after the click" "menu windows=$n"
    fi
    snap after-desk-click

    # New window, in a desk's submenu.
    if opened_or_fail "for New window"; then
        rest_on "   api" api-submenu
        since=$(moment)
        if click_in_submenu "   api" "New window"; then
            expect_row "a click on New window in api's submenu runs that line" "$since" "desk:workhorse:api:window"
        else
            result NOT-SHOWN "a click on New window in api's submenu" "the line was not found"
        fi
        snap after-new-window
    fi

    # Escape closes the menu.
    if opened_or_fail "for Escape"; then
        tool keys 53 1 300 > /dev/null
        n=$(wait_menus 0 3)
        if [ "$n" -eq 0 ]; then
            result PASS "Escape closes the menu" "menu windows=0"
        else
            result DIFFERS "Escape closes the menu" "menu windows=$n"
        fi
        snap after-escape
    fi
    stop_app
}

changing() {
    local since open_since hold_since click_since n idx x y name watch fewest changes lines row_at shown_at base
    local sel_before sel_after quick ms before
    start_app changing || return
    open_since=$(moment)
    if ! opened_or_fail "first click"; then stop_app; return; fi
    snap menu

    # Rest on a desk's row until its submenu is open, then wait across at least two changes.
    read -r idx x y name <<< "$(find_xy top "   website")"
    say "rest on row $idx [$name] at $x,$y"
    tool move "$x" "$y" > /dev/null
    n=$(wait_menus 2 4)
    if [ "$n" -lt 2 ]; then
        result NOT-SHOWN "the submenu stays open while the menu changes" "it never opened (menu windows=$n)"
    else
        sleep 0.3
        base=$(printf '%s-%s' "$os" "$sample")
        ax names top > "$OUT/ax/$base-hold-before-top.txt"
        ax dump "   website" > "$OUT/ax/$base-hold-before-submenu.txt"
        sel_before=$(ax selected top | grep '^selected' | tail -n 1)
        snap submenu-open-before-the-wait
        hold_since=$(moment)
        watch=$(tool watch 7.5 hold)
        fewest=$(sed -n 's/.*done after .* fewest=\([0-9]*\).*/\1/p' <<< "$watch")
        snap submenu-open-after-7s
        ax names top > "$OUT/ax/$base-hold-after-top.txt"
        ax dump "   website" > "$OUT/ax/$base-hold-after-submenu.txt"
        sel_after=$(ax selected top | grep '^selected' | tail -n 1)
        n=$(count)
        changes=$(applog "$hold_since" | grep -c "sample changed:")
        if [ "${fewest:-0}" -ge 2 ] && [ "$n" -ge 2 ]; then
            result PASS "the submenu stays open while the menu changes" "menu windows never below 2 in 7.5 s; $changes sample changes in that time"
        else
            result FAIL "the submenu stays open while the menu changes" "fewest menu windows ${fewest:-?}, now $n; $changes sample changes in that time"
        fi
        if [[ "$sel_before" == *"website"* ]] && [ "$sel_after" = "$sel_before" ] \
            && cmp -s "$OUT/ax/$base-hold-before-submenu.txt" "$OUT/ax/$base-hold-after-submenu.txt"; then
            result PASS "the accessibility tree shows the submenu still open" "website's row still highlighted; the submenu at the same place with the same lines"
        else
            result FAIL "the accessibility tree shows the submenu still open" "highlighted before [$sel_before], after [$sel_after]; see ax/$base-hold-*-submenu.txt"
        fi
        if applog "$hold_since" | grep -qF "menu showed the held change"; then
            result DIFFERS "no held change is shown while the menu is open" "a 'menu showed the held change' line during the wait"
        else
            result PASS "no held change is shown while the menu is open" "no 'menu showed the held change' line during the wait"
        fi
        if cmp -s "$OUT/ax/$base-hold-before-top.txt" "$OUT/ax/$base-hold-after-top.txt"; then
            result PASS "the open menu's rows did not change" "the accessibility tree reads the same rows before and after"
        else
            result DIFFERS "the open menu's rows did not change" "see ax/$base-hold-*-top.txt"
        fi
        if wait_log "$open_since" "menu held a change: open with a submenu" 5; then
            result PASS "the app held a change" "log: menu held a change: open with a submenu"
        else
            result DIFFERS "the app held a change" "no 'menu held a change: open with a submenu' line"
        fi

        # A click on a line in the open submenu runs it, and the held change waits until after it.
        click_since=$(moment)
        if click_in_submenu "   website" "New window"; then
            expect_row "a click on New window in the held submenu runs that line" "$click_since" "desk:workhorse:website:window"
            wait_log "$click_since" "menu showed the held change" 6 > /dev/null
            lines=$(applog "$click_since")
            printf '%s\n' "$lines" | sed 's/^/app since the click: /' >> "$LOG"
            row_at=$(printf '%s\n' "$lines" | grep -nF "sample row ran: desk:workhorse:website:window" | head -n 1 | cut -d: -f1)
            shown_at=$(printf '%s\n' "$lines" | grep -nF "menu showed the held change" | head -n 1 | cut -d: -f1)
            if [ -z "$shown_at" ]; then
                result NOT-SHOWN "the held change is shown after the clicked row ran" "no 'menu showed the held change' line after the click"
            elif [ -z "$row_at" ]; then
                result FAIL "the held change is shown after the clicked row ran" "the change was shown and the row never ran"
            elif [ "$shown_at" -gt "$row_at" ]; then
                result PASS "the held change is shown after the clicked row ran" "$(printf '%s\n' "$lines" | sed -n "${shown_at}p" | sed 's/.*\] //')"
            else
                result FAIL "the held change is shown after the clicked row ran" "the change came first"
            fi
        else
            result NOT-SHOWN "a click on New window in the held submenu" "the line was not found"
        fi
        sleep 1

        # Opened again, the menu shows what changed.
        if opened_or_fail "again after the held change"; then
            snap reopened-shows-the-change
            if cmp -s "$OUT/ax/$base-hold-before-top.txt" "$OUT/ax/$(printf '%s-%02d' "$base" "$shotn")-reopened-shows-the-change.txt"; then
                result DIFFERS "the reopened menu shows the change" "the rows read the same as before the wait"
            else
                result PASS "the reopened menu shows the change" "the rows differ from before the wait"
            fi
            close_menu
        fi
    fi

    # A click on a desk's row that lands before its submenu has opened.
    sleep 1
    if opened_or_fail "for the quick click"; then
        read -r idx x y name <<< "$(find_xy top "   website")"
        since=$(moment)
        say "quick click on row $idx [$name] at $x,$y"
        quick=$(tool rushclick "$x" "$y")
        ms=$(sed -n 's/.*button down \([0-9]*\) ms after.*/\1/p' <<< "$quick")
        before=$(sed -n 's/.*menu windows just before it: \([0-9]*\).*/\1/p' <<< "$quick")
        if [ "${ms:-999}" -le 100 ] && [ "${before:-0}" -eq 1 ]; then
            result PASS "the quick click lands before the submenu opens" "button down ${ms} ms after the pointer arrived; 1 menu window just before it"
        else
            result NOT-SHOWN "the quick click lands before the submenu opens" "button down ${ms:-?} ms after the pointer arrived; ${before:-?} menu window(s) just before it"
        fi
        expect_row "a click on a desk's row before its submenu opens runs that desk's row" "$since" "desk:workhorse:website"
        snap after-quick-click
    fi
    stop_app
}

############################################################ the run
say "driving $APP on $os ($(sw_vers -productVersion))"
tool preflight > /dev/null
lim 10 "$TOOL" move 600 500 > /dev/null

six_desks
plain_sample sign-ins-off
plain_sample locked
plain_sample waiting-for-login
plain_sample two-workhorses
plain_sample no-workhorses
changing

applog "$run_since" > "$OUT/app-log.txt"
sample=""
say "done: $failures failed check(s)"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    {
        echo "### Menu pictures on $os"
        echo
        echo "| result | sample | check | detail |"
        echo "|---|---|---|---|"
        awk -F '\t' '{ printf "| %s | %s | %s | %s |\n", $1, $3, $4, $5 }' "$RESULTS"
    } >> "$GITHUB_STEP_SUMMARY"
fi
cat "$RESULTS"
[ "$failures" -eq 0 ]
