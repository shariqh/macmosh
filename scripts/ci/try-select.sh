#!/bin/bash
# CI only (.github/workflows/terminal-scripts.yml, issue #129): runs the app's own select scripts
# against a real terminal app on a GitHub runner, and reads back which tab is in front. It opens,
# minimizes and raises terminal windows: never run it on your own Mac.
#
#   SCRIPTS=<folder> OUT=<folder> scripts/ci/try-select.sh iterm2|terminal
#
# SCRIPTS holds iterm2-select.applescript and terminal-select.applescript, which the test
# SelectScriptFiles writes from the app's own constants. Each select runs as the app runs it:
# osascript -e <script> <tty>, the script's text unchanged.
#
# The cases: (a) a tab in a window that is not in front (for iTerm2 also not the selected tab of its
# window); (b) a tab in a minimized window; (c) the tab that is already in front; (d) a tty no tab
# has, whose answer must be gone. After each, a separate AppleScript reads which window is in front
# and which tab or session is current in it.
#
# What it leaves in OUT: <app>-driver.log (every step and every answer), <app>-results.tsv (one line
# per check: PASS, FAIL, NOTE or SKIPPED), and pictures/<os>-<app>-<step>.png.
# It fails when a case does not end with the wanted tty in front or the answer is not the expected
# one. When osascript cannot drive the app at all, it writes a SKIPPED line that says so, and fails.
set -uo pipefail

app=${1:?say iterm2 or terminal}
SCRIPTS=${SCRIPTS:?set SCRIPTS to the folder with the exported select scripts}
OUT=${OUT:?set OUT to the folder for logs and pictures}
mkdir -p "$OUT/pictures"
LOG="$OUT/$app-driver.log"
RESULTS="$OUT/$app-results.tsv"
: > "$RESULTS"
os="macos$(sw_vers -productVersion | cut -d. -f1)"
failures=0

case "$app" in
    iterm2) name="iTerm2"; bundle="/Applications/iTerm.app" ;;
    terminal) name="Terminal"; bundle="/System/Applications/Utilities/Terminal.app" ;;
    *) echo "say iterm2 or terminal" >&2; exit 64 ;;
esac
select_script=$(< "$SCRIPTS/$app-select.applescript")

now() { perl -MTime::HiRes=time -e 'printf "%.3f", time'; }
say() { printf '%s %s\n' "$(now)" "$*" | tee -a "$LOG"; }
# lim <seconds> <command...>: the command, stopped by SIGALRM (exit 142) after that many seconds.
lim() { perl -e 'alarm shift @ARGV; exec @ARGV or die "exec failed"' "$@"; }

# result <PASS|FAIL|NOTE|SKIPPED> <check> <detail>
result() {
    printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$os" "$name" "$2" "$3" >> "$RESULTS"
    say "RESULT $1 [$name] $2: $3"
    if [ "$1" = FAIL ] || [ "$1" = SKIPPED ]; then failures=$((failures + 1)); fi
}

# osa <seconds> <script text> [arguments...]: runs it with osascript -e, as the app does. Sets ANSWER
# (what it printed), ERR (what it said on stderr) and STATUS (its exit code; 142 when it was stopped).
osa() {
    local secs=$1 text=$2
    shift 2
    ANSWER=$(lim "$secs" osascript -e "$text" "$@" 2> "$OUT/$app-stderr.txt")
    STATUS=$?
    ERR=$(cat "$OUT/$app-stderr.txt")
    say "osascript exit=$STATUS answer=[$ANSWER] stderr=[$ERR]"
}

snap() {
    lim 15 screencapture -x "$OUT/pictures/$os-$app-$1.png" >> "$LOG" 2>&1 || say "screencapture failed for $1"
}

############################################################ the app's own words, from its dictionary
if [ "$app" = iterm2 ]; then
    # ITermLauncher's commands: a window, and a tab in the current window.
    make_windows='tell application "iTerm2"
    repeat 2 times
        create window with default profile
        tell current window
            create tab with default profile
        end tell
    end repeat
    return count of windows
end tell'
    # One line per tab: window, tab, tty, whether it is the current tab of its window, minimized.
    layout='tell application "iTerm2"
    set out to {}
    repeat with i from 1 to count of windows
        set cur to tty of current session of window i
        repeat with j from 1 to count of tabs of window i
            set x to tty of current session of tab j of window i
            set end of out to "window " & i & " tab " & j & " " & x & " current=" & (x is cur) & " minimized=" & (miniaturized of window i)
        end repeat
    end repeat
    set AppleScript'"'"'s text item delimiters to linefeed
    return out as text
end tell'
    # The front window's current session, whether that window is minimized, and whether iTerm2 is frontmost.
    front='tell application "iTerm2"
    return (tty of current session of window 1) & " minimized=" & (miniaturized of window 1) & " frontmost=" & frontmost
end tell'
    minimize='on run argv
    tell application "iTerm2"
        repeat with w in windows
            repeat with t in tabs of w
                repeat with s in sessions of t
                    if (tty of s) is (item 1 of argv) then
                        set miniaturized of w to true
                        return "minimized"
                    end if
                end repeat
            end repeat
        end repeat
    end tell
    return "not found"
end run'
else
    # Terminal can't open a tab by script; `do script` opens a window with one tab.
    make_windows='tell application "Terminal"
    repeat 3 times
        do script ""
    end repeat
    return count of windows
end tell'
    layout='tell application "Terminal"
    set out to {}
    repeat with i from 1 to count of windows
        repeat with j from 1 to count of tabs of window i
            set x to tty of tab j of window i
            set end of out to "window " & i & " tab " & j & " " & x & " current=" & (selected of tab j of window i) & " minimized=" & (miniaturized of window i)
        end repeat
    end repeat
    set AppleScript'"'"'s text item delimiters to linefeed
    return out as text
end tell'
    front='tell application "Terminal"
    return (tty of selected tab of window 1) & " minimized=" & (miniaturized of window 1) & " frontmost=" & frontmost
end tell'
    minimize='on run argv
    tell application "Terminal"
        repeat with w in windows
            repeat with t in tabs of w
                if (tty of t) is (item 1 of argv) then
                    set miniaturized of w to true
                    return "minimized"
                end if
            end repeat
        end repeat
    end tell
    return "not found"
end run'
fi

show_layout() {
    osa 20 "$layout"
    LAYOUT=$ANSWER
    printf '%s\n' "$LAYOUT" | sed 's/^/layout: /' >> "$LOG"
}

# try_case <case> <tty> <expected answer>: runs the app's script on that tty and checks the answer, and
# then which tty is in front, unminimized.
try_case() {
    local label=$1 tty=$2 want=$3 before seen
    osa 20 "$front"
    before=$ANSWER
    say "== case $label: select $tty (expect $want); in front before: $before"
    osa 30 "$select_script" "$tty"
    if [ "$STATUS" -ne 0 ]; then
        result FAIL "case $label: the script's answer" "osascript exit $STATUS: $ERR"
    elif [ "$ANSWER" = "$want" ]; then
        result PASS "case $label: the script's answer" "$ANSWER"
    else
        result FAIL "case $label: the script's answer" "expected $want, got [$ANSWER]"
    fi
    sleep 1
    osa 20 "$front"
    seen=$ANSWER
    show_layout
    snap "case-$label"
    if [ "$want" = gone ]; then
        if [ "$seen" = "$before" ]; then
            result PASS "case $label: nothing moved" "in front: $seen"
        else
            result FAIL "case $label: nothing moved" "before: $before; after: $seen"
        fi
        return
    fi
    if [[ "$seen" == "$tty minimized=false"* ]]; then
        result PASS "case $label: the wanted tab is in front" "$seen"
    else
        result FAIL "case $label: the wanted tab is in front" "wanted $tty; in front: $seen"
    fi
    if [[ "$seen" == *"frontmost=true" ]]; then
        result PASS "case $label: $name is the frontmost app" "$seen"
    else
        result NOTE "case $label: $name is the frontmost app" "not frontmost: $seen"
    fi
}

############################################################ the run
finish() {
    say "done: $failures failed check(s)"
    if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
        {
            echo "### $name on $os"
            echo
            echo "| result | check | detail |"
            echo "|---|---|---|"
            awk -F '\t' '{ printf "| %s | %s | %s |\n", $1, $4, $5 }' "$RESULTS"
        } >> "$GITHUB_STEP_SUMMARY"
    fi
    cat "$RESULTS"
    [ "$failures" -eq 0 ]
    exit
}

say "$name $(defaults read "$bundle/Contents/Info.plist" CFBundleShortVersionString) on $os ($(sw_vers -productVersion))"
say "select script: $(printf '%s' "$select_script" | shasum -a 256 | cut -d' ' -f1), $(printf '%s' "$select_script" | wc -c | tr -d ' ') bytes"
bundle_id=$(defaults read "$bundle/Contents/Info.plist" CFBundleIdentifier)
lim 20 open -a "$bundle"
sleep 8
snap started

# tcc_log <step>: what macOS's privacy service (TCC) said about Apple events in the last 3 minutes.
tcc_log() {
    lim 60 /usr/bin/log show --last 3m --style compact --predicate 'subsystem == "com.apple.TCC"' 2>/dev/null \
        | grep -E "AppleEvents|$bundle_id" | tail -n 60 > "$OUT/$app-tcc-$1.txt"
    say "TCC log ($1): $(wc -l < "$OUT/$app-tcc-$1.txt" | tr -d ' ') lines in $app-tcc-$1.txt"
    grep -m 5 -oE "(responsible|attribution)[^}]{0,200}" "$OUT/$app-tcc-$1.txt" | sed 's/^/  /' | tee -a "$LOG"
}

# probe <step>: one real Apple event (AppleScript answers an app's `version` without one). True when it answered.
probe() {
    osa 20 "tell application \"$name\" to count windows"
    snap "probe-$1"
    tcc_log "$1"
    if [ "$STATUS" -eq 0 ]; then
        result PASS "osascript drives $name ($1)" "$name counted $ANSWER window(s)"
        return 0
    fi
    if [ "$STATUS" -eq 142 ]; then
        result NOTE "osascript drives $name ($1)" "no answer in 20 s (a consent window may be waiting; see probe-$1.png)"
    else
        result NOTE "osascript drives $name ($1)" "osascript exit $STATUS: $ERR"
    fi
    return 1
}

# grant: what GitHub's runner images do to let a process send Apple events (actions/runner-images,
# images/macos/scripts/build/configure-tccdb-macos.sh: a kTCCServiceAppleEvents row in the user's and the
# system's TCC.db with sqlite3), for this app's bundle id and the clients the image names.
grant() {
    local ts client row
    ts=$(date +%s)
    for client in /opt/hca/hosted-compute-agent /usr/bin/osascript /bin/bash; do
        row="'kTCCServiceAppleEvents','$client',1,2,3,1,NULL,NULL,0,'$bundle_id',NULL,NULL,$ts,NULL,NULL,'UNUSED',$ts"
        lim 20 sqlite3 "$HOME/Library/Application Support/com.apple.TCC/TCC.db" "INSERT OR REPLACE INTO access VALUES($row);" >> "$LOG" 2>&1
        say "user TCC.db: $client -> $bundle_id: exit $?"
        lim 20 sudo sqlite3 "/Library/Application Support/com.apple.TCC/TCC.db" "INSERT OR REPLACE INTO access VALUES($row);" >> "$LOG" 2>&1
        say "system TCC.db: $client -> $bundle_id: exit $?"
    done
    say "restart the privacy service: user $(killall tccd 2>&1; echo "exit $?"), system $(sudo killall tccd 2>&1; echo "exit $?")"
    sleep 3
}

if ! probe as-is; then
    say "osascript could not drive $name as the runner comes; adding the runner image's kind of privacy rows"
    grant
    if ! probe after-grant; then
        result SKIPPED "osascript drives $name" "the runner would not let osascript control $name, as it comes or with the runner image's privacy rows; see $app-driver.log and $app-tcc-*.txt"
        finish
    fi
fi

osa 60 "$make_windows"
if [ "$STATUS" -ne 0 ]; then
    snap make-windows
    tcc_log make-windows
    result FAIL "make windows" "osascript exit $STATUS: $ERR"
    finish
fi
# Wait until every tab has its terminal device.
for _ in $(seq 1 20); do
    show_layout
    if [ -n "$LAYOUT" ] && ! printf '%s\n' "$LAYOUT" | awk '$5 !~ /^\/dev\/ttys[0-9]+$/ { bad = 1 } END { exit !bad }'; then
        break
    fi
    sleep 1
done
snap windows
result NOTE "windows and tabs" "$(printf '%s\n' "$LAYOUT" | wc -l | tr -d ' ') tabs: $(printf '%s' "$LAYOUT" | tr '\n' ';')"

# (a) a tab in a window that is not in front; for iTerm2, also not the current tab of its window.
if [ "$app" = iterm2 ]; then
    a=$(printf '%s\n' "$LAYOUT" | awk '$2 != 1 && $6 == "current=false" { print $5; exit }')
else
    a=$(printf '%s\n' "$LAYOUT" | awk '$2 != 1 { print $5; exit }')
fi
if [ -n "$a" ]; then try_case a "$a" ok; else result FAIL "case a" "no such tab in the layout"; fi

# (b) a tab in a minimized window: minimize a window behind the front one, then select one of its tabs
# (for iTerm2, one that is not its current tab).
show_layout
if [ "$app" = iterm2 ]; then
    b=$(printf '%s\n' "$LAYOUT" | awk '$2 != 1 && $6 == "current=false" { print $5; exit }')
else
    b=$(printf '%s\n' "$LAYOUT" | awk '$2 != 1 { print $5; exit }')
fi
if [ -n "$b" ]; then
    osa 20 "$minimize" "$b"
    sleep 2
    show_layout
    if printf '%s\n' "$LAYOUT" | grep -F " $b " | grep -q "minimized=true"; then
        result PASS "case b: the window is minimized before the select" "$(printf '%s\n' "$LAYOUT" | grep -F " $b ")"
    else
        result NOTE "case b: the window is minimized before the select" "the layout does not show it minimized: $(printf '%s' "$LAYOUT" | tr '\n' ';')"
    fi
    snap minimized
    try_case b "$b" ok
else
    result FAIL "case b" "no such tab in the layout"
fi

# (c) the tab that is already in front.
osa 20 "$front"
c=${ANSWER%% *}
try_case c "$c" ok

# (d) a terminal device that no tab has.
d=/dev/ttys999
while printf '%s\n' "$LAYOUT" | grep -qF " $d "; do d="/dev/ttys$((${d#/dev/ttys} - 1))"; done
try_case d "$d" gone

finish
