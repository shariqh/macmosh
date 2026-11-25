#!/bin/bash
# CI only (.github/workflows/terminal-scripts.yml, issue #162): opens real tabs in a real terminal app on a
# GitHub runner, attaches them to a throwaway desk through the branch's workhorse script, and reads back with
# AppleScript what the tab's title says while the window and the desk are named and renamed. It opens and
# closes terminal windows and starts tmux and mosh: never run it on your own Mac.
#
#   SCRIPTS=<folder> OUT=<folder> scripts/ci/try-title.sh iterm2|terminal
#
# SCRIPTS holds tab-title-website.txt, the bytes the app prints to name a tab before it connects (written by
# the test SelectScriptFiles from TabTitle.escape). Each tab prints that file first, as the app does, and then
# attaches. It relies on the privacy rows scripts/ci/try-select.sh wrote for this app in an earlier step of
# the same job, which let osascript control it.
#
# The connections, each on a desk server of its own (tmux on a throwaway socket, macmosh-test-title-<n>, with
# MACMOSH_HOME, HOME and the desk's folder in a temp folder):
#   (a) direct: the tab runs the script's attach --label beef website itself. This stands in for Plain ssh,
#       which carries the bytes between the two ends unchanged; there is no ssh here.
#   (b) mosh: mosh-server new on 127.0.0.1 runs the same attach, and the tab runs mosh-client with
#       MOSH_TITLE_NOPREFIX set, as the app's Mosh connection does; then one more tab without it, read once,
#       to show mosh's "[mosh] " prefix.
#   (c) Tabs (iTerm2 only): the tab runs attach --cc; the script only records what iTerm2 shows for a named
#       and an unnamed window.
# The steps for (a) and (b): before (what the app's once-only title shows alone, read while the tab waits 4
# seconds before it attaches; a NOTE), open (the desk's name), the window named "api" with window-name, the window given
# back to its program (--auto), the desk renamed to "garden", a second window named "blog" and the tab moved
# to it. After each, the title is read until it shows the wanted name or 20 seconds pass, and the seconds it
# took are recorded. A step passes only when a field the app's escape 1 never sets equals the wanted name
# exactly: iTerm2, the session's terminalWindowName ("... as set by the control sequence OSC 0 or OSC 2");
# Terminal, the tab's custom title (it reads "Terminal" with the app's title alone). The tab's title
# (iTerm2) and the window's name (Terminal) are logged with it, with everything else read.
#
# What it leaves in OUT: <app>-title-driver.log, <app>-title-results.tsv (one line per check: PASS, FAIL, NOTE
# or SKIPPED) and pictures/<os>-<app>-title-<connection>-<step>.png. For iTerm2 a step that does not show the
# wanted name is a FAIL. For Terminal, when the tab's custom title is not the desk's name at open, that is
# recorded as a NOTE with everything Terminal says, and its later steps are NOTEs as well: nothing is built
# around Terminal's settings. Tabs (c) only records what it sees and gates nothing, so a Tabs tab the runner
# could not open is a NOTE with the reason, not a SKIPPED (which would fail the job).
set -uo pipefail

app=${1:?say iterm2 or terminal}
SCRIPTS=${SCRIPTS:?set SCRIPTS to the folder with the exported files}
OUT=${OUT:?set OUT to the folder for logs and pictures}
mkdir -p "$OUT/pictures"
LOG="$OUT/$app-title-driver.log"
RESULTS="$OUT/$app-title-results.tsv"
: > "$RESULTS"
os="macos$(sw_vers -productVersion | cut -d. -f1)"
failures=0
here=$(cd "$(dirname "$0")/../.." && pwd)
HOST="$here/host/macmosh-host"
TITLE_FILE="$SCRIPTS/tab-title-website.txt"
WORK=$(mktemp -d "${RUNNER_TEMP:-/tmp}/try-title-$app.XXXXXX")
PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"

case "$app" in
    iterm2) name="iTerm2" ;;
    terminal) name="Terminal" ;;
    *) echo "say iterm2 or terminal" >&2; exit 64 ;;
esac

now() { perl -MTime::HiRes=time -e 'printf "%.3f", time'; }
say() { printf '%s %s\n' "$(now)" "$*" | tee -a "$LOG"; }
lim() { perl -e 'alarm shift @ARGV; exec @ARGV or die "exec failed"' "$@"; }

result() {
    printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$os" "$name" "$2" "$3" >> "$RESULTS"
    say "RESULT $1 [$name] $2: $3"
    if [ "$1" = FAIL ] || [ "$1" = SKIPPED ]; then failures=$((failures + 1)); fi
}

osa() {
    local secs=$1 text=$2
    shift 2
    ANSWER=$(lim "$secs" osascript -e "$text" "$@" 2> "$OUT/$app-title-stderr.txt")
    STATUS=$?
    ERR=$(cat "$OUT/$app-title-stderr.txt")
    say "osascript exit=$STATUS answer=[$ANSWER] stderr=[$ERR]"
}

snap() {
    lim 15 screencapture -x "$OUT/pictures/$os-$app-title-$1.png" >> "$LOG" 2>&1 || say "screencapture failed for $1"
}

finish() {
    say "done: $failures failed check(s)"
    if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
        {
            echo "### Tab titles in $name on $os"
            echo
            echo "| result | check | detail |"
            echo "|---|---|---|"
            awk -F '\t' '{ gsub(/\|/, "\\|", $5); printf "| %s | %s | %s |\n", $1, $4, $5 }' "$RESULTS"
        } >> "$GITHUB_STEP_SUMMARY"
    fi
    cat "$RESULTS"
    [ "$failures" -eq 0 ]
    exit
}

############################################################ the terminal app's words, from its dictionary
if [ "$app" = iterm2 ]; then
    # A window whose one session runs the command; its tty.
    open_tab='on run argv
    tell application "iTerm2"
        activate
        set w to (create window with default profile command (item 1 of argv))
        return tty of current session of w
    end tell
end run'
    # The tab's title, the session's name, the window's name, and the session variables for the two titles a
    # program sets (terminalIconName: "The \"icon\" title, as set by the control sequence OSC 0 or OSC 1.",
    # terminalWindowName: "... OSC 0 or OSC 2.", https://iterm2.com/documentation-variables.html).
    read_tab='on run argv
    tell application "iTerm2"
        repeat with w in windows
            repeat with t in tabs of w
                repeat with s in sessions of t
                    if (tty of s) is (item 1 of argv) then
                        set icon to "?"
                        set wname to "?"
                        tell s
                            try
                                set icon to (variable named "session.terminalIconName")
                            end try
                            try
                                set wname to (variable named "session.terminalWindowName")
                            end try
                        end tell
                        return (title of t) & " | session=" & (name of s) & " | window=" & (name of w) & " | iconName=" & icon & " | windowName=" & wname
                    end if
                end repeat
            end repeat
        end repeat
    end tell
    return "no such tab"
end run'
    open_plain='tell application "iTerm2"
    activate
    set w to (create window with default profile)
    return tty of current session of w
end tell'
    type_in='on run argv
    tell application "iTerm2"
        repeat with w in windows
            repeat with t in tabs of w
                repeat with s in sessions of t
                    if (tty of s) is (item 1 of argv) then
                        tell s to write text (item 2 of argv)
                        return "typed"
                    end if
                end repeat
            end repeat
        end repeat
    end tell
    return "no such tab"
end run'
    close_tab='on run argv
    tell application "iTerm2"
        repeat with w in windows
            repeat with t in tabs of w
                repeat with s in sessions of t
                    if (tty of s) is (item 1 of argv) then
                        close w
                        return "closed"
                    end if
                end repeat
            end repeat
        end repeat
    end tell
    return "no such tab"
end run'
    # Every window, tab and session, for the Tabs connection.
    everything='tell application "iTerm2"
    set out to {}
    repeat with i from 1 to count of windows
        repeat with j from 1 to count of tabs of window i
            set t to tab j of window i
            set end of out to "window " & i & " [" & (name of window i) & "] tab " & j & " title=[" & (title of t) & "] session=[" & (name of current session of t) & "] tty=" & (tty of current session of t)
        end repeat
    end repeat
    set AppleScript'"'"'s text item delimiters to linefeed
    return out as text
end tell'
else
    # Terminal can't open a tab by script; `do script` opens a window with one tab running the command.
    open_tab='on run argv
    tell application "Terminal"
        activate
        set t to do script (item 1 of argv)
        delay 1
        return tty of t
    end tell
end run'
    read_tab='on run argv
    tell application "Terminal"
        repeat with w in windows
            repeat with t in tabs of w
                if (tty of t) is (item 1 of argv) then
                    return (name of w) & " | custom title=" & (custom title of t) & " | displays custom title=" & (title displays custom title of t) & " | displays shell path=" & (title displays shell path of t) & " | processes=" & ((processes of t) as text)
                end if
            end repeat
        end repeat
    end tell
    return "no such tab"
end run'
    close_tab='on run argv
    tell application "Terminal"
        repeat with w in windows
            repeat with t in tabs of w
                if (tty of t) is (item 1 of argv) then
                    close w
                    return "closed"
                end if
            end repeat
        end repeat
    end tell
    return "no such tab"
end run'
    everything=''
    open_plain=''
    type_in=''
fi

############################################################ desks
# A desk server of its own for each connection: the branch's script, its state in WORK.
desk_env() {
    printf '%s\n' "HOME=$WORK/home-$1" "MACMOSH_HOME=$WORK/macmosh-$1" "MACMOSH_SOCKET=macmosh-test-title-$1" \
        "LANG=en_US.UTF-8" "PATH=$PATH" "MACMOSH_HOOK_DELAY=1"
}

# host <n> <arguments...>: the branch's script against desk server n.
host() {
    local n=$1
    shift
    mkdir -p "$WORK/home-$n"
    # shellcheck disable=SC2046  # one line per variable, none with spaces
    lim 30 env -i $(desk_env "$n") /bin/bash "$HOST" "$@"
}

# tm <n> <arguments...>: tmux on desk server n's throwaway socket.
tm() {
    local n=$1
    shift
    lim 20 env LANG=en_US.UTF-8 tmux -L "macmosh-test-title-$n" "$@"
}

# The view carrying this label on server n.
view_of() { tm "$1" list-sessions -F '#{session_id} #{@macmosh-label}' 2>/dev/null | awk -v l="$2" '$2 == l { print $1; exit }'; }

# What tmux itself makes of every session's title on server n, for the log.
tmux_side() {
    tm "$1" list-sessions -F 'tmux: #{session_id} #{session_name} window=#{window_id}:#{window_name} auto=#{automatic-rename} set-titles=#{set-titles} title=[#{E:set-titles-string}]' >> "$LOG" 2>&1
}

new_desk() {
    local n=$1 out
    mkdir -p "$WORK/home-$n"
    out=$(host "$n" start 2>&1; echo "exit $?")
    say "desk server $n start: $out"
    out=$(host "$n" desk-new website "$WORK/home-$n" 2>&1; echo "exit $?")
    say "desk-new website: $out"
}

# The tab's command, written to a file: the app's title bytes first, then, 4 seconds later (so that what the
# app's title alone shows can be read), the rest.
write_tab() {
    local file=$1
    shift
    {
        echo '#!/bin/bash'
        printf 'cat %q\n' "$TITLE_FILE"
        echo 'sleep 4'
        printf '%s\n' "$*"
    } > "$file"
    say "tab script $file: $(tr '\n' ';' < "$file")"
}

open_tab() {
    TTY=""
    osa 30 "$open_tab" "/bin/bash $1"
    if [ "$STATUS" -eq 0 ] && [[ "$ANSWER" == /dev/ttys* ]]; then TTY=$ANSWER; fi
}

read_tab() {
    osa 15 "$read_tab" "$TTY"
    READ=$ANSWER
    # PROOF is a field the app's escape 1 never sets, so only a title from tmux (escape 0) can match it.
    if [ "$app" = iterm2 ]; then
        PROOF=${READ##* | windowName=}
    else
        PROOF=${READ#* | custom title=}
        PROOF=${PROOF%% | *}
    fi
}

# What the tab shows with the app's once-only title (escape 1) alone, before it attaches.
read_before() {
    sleep 1
    read_tab
    snap "$2-0-before"
    result NOTE "$1: the app's once-only title alone, before the attach" "$READ"
}

# wait_title <check> <wanted> <picture>: reads the title until its PROOF field is exactly the wanted text or
# 20 s pass. The seconds run from the end of the step to the end of the read that matched, so they include
# one AppleScript read.
strict=1
wait_title() {
    local check=$1 want=$2 pic=$3 start end took verdict
    start=$(now)
    end=$(perl -e "printf '%.3f', $start + 20")
    while :; do
        read_tab
        if [ "$PROOF" = "$want" ]; then break; fi
        if perl -e "exit !($(now) > $end)"; then break; fi
        sleep 0.25
    done
    took=$(perl -e "printf '%.1f', $(now) - $start")
    snap "$pic"
    if [ "$PROOF" = "$want" ]; then
        result PASS "$check" "shows [$want] after $took s: $READ"
    else
        verdict=FAIL
        [ "$strict" = 1 ] || verdict=NOTE
        result "$verdict" "$check" "wanted [$want], still [$PROOF] after $took s: $READ"
    fi
}

# The steps a tab goes through on desk server n, its view labelled l; c names the connection.
steps() {
    local n=$1 l=$2 c=$3 v desk w1 w2 out
    for _ in $(seq 1 40); do
        v=$(view_of "$n" "$l")
        [ -n "$v" ] && [ "$(tm "$n" list-clients -F '#{session_id}' 2>/dev/null | grep -cxF -- "$v")" -ge 1 ] && break
        sleep 0.5
    done
    tmux_side "$n"
    if [ -z "$v" ]; then
        result FAIL "$c: the tab attaches" "no view labelled $l with a client on server $n"
        return 1
    fi
    say "view $v: own set-titles=[$(tm "$n" show-options -t "$v" -v set-titles 2>&1)] string=[$(tm "$n" show-options -t "$v" -v set-titles-string 2>&1)]"
    desk=$(tm "$n" list-sessions -F '#{session_id} #{session_name}' | awk '$2 == "website" { print $1 }')
    w1=$(tm "$n" display-message -p -t "$v" '#{window_id}')

    # For Terminal, whether its tab shows a title at all is first found out, without a FAIL.
    if [ "$app" = terminal ] && [ "$c" = "(a) direct" ]; then strict=0; fi
    wait_title "$c: open, the desk's name" website "$c-1-open"
    if [ "$app" = terminal ] && [ "$c" = "(a) direct" ]; then
        if [ "$PROOF" = website ]; then
            strict=1
        else
            result NOTE "Terminal: what a tab shows" "no title with the desk's name at open; window name, custom title and the rest: $READ"
        fi
    fi

    out=$(host "$n" window-name website "$w1" api 2>&1; echo "exit $?")
    say "window-name website $w1 api: $out"
    tmux_side "$n"
    wait_title "$c: the window named api" api "$c-2-named"

    out=$(host "$n" window-name website "$w1" --auto 2>&1; echo "exit $?")
    say "window-name --auto: $out"
    tmux_side "$n"
    wait_title "$c: the window back to its program's name" website "$c-3-auto"

    out=$(host "$n" desk-rename website garden 2>&1; echo "exit $?")
    say "desk-rename website garden: $out"
    tmux_side "$n"
    wait_title "$c: the desk renamed garden" garden "$c-4-renamed"

    w2=$(tm "$n" new-window -d -P -F '#{window_id}' -t "$desk:")
    out=$(host "$n" window-name garden "$w2" blog 2>&1; echo "exit $?")
    say "new window $w2, window-name garden $w2 blog: $out"
    tm "$n" select-window -t "$v:$w2"
    tmux_side "$n"
    wait_title "$c: the tab moved to a window named blog" blog "$c-5-moved"
}

end_tab() {
    tm "$1" kill-server >> "$LOG" 2>&1
    sleep 2
    [ -n "$TTY" ] && osa 15 "$close_tab" "$TTY"
}

############################################################ the run
say "$name $(defaults read "$( [ "$app" = iterm2 ] && echo /Applications/iTerm.app || echo /System/Applications/Utilities/Terminal.app)/Contents/Info.plist" CFBundleShortVersionString) on $os ($(sw_vers -productVersion))"
say "tmux: $(tmux -V 2>&1); mosh-server: $(mosh-server --version 2>&1 | head -n 1); mosh-client: $(command -v mosh-client)"
say "workhorse script: $(/bin/bash "$HOST" version 2>&1); app's title bytes: $(od -An -c "$TITLE_FILE" | tr -s ' \n' ' ')"
[ -f "$TITLE_FILE" ] || { result FAIL "the app's title bytes" "no $TITLE_FILE"; finish; }

osa 20 "tell application \"$name\" to count windows"
if [ "$STATUS" -ne 0 ]; then
    result SKIPPED "osascript drives $name" "osascript exit $STATUS: $ERR"
    finish
fi

# (a) direct: the tab runs the script's attach itself.
new_desk 1
# shellcheck disable=SC2046
write_tab "$WORK/tab-a.sh" "exec env $(desk_env 1 | tr '\n' ' ') /bin/bash $(printf '%q' "$HOST") attach --label beef website"
open_tab "$WORK/tab-a.sh"
if [ -z "$TTY" ]; then
    result FAIL "(a) direct: open a tab" "no tty: $ANSWER $ERR"
else
    read_before "(a) direct" "(a) direct"
    steps 1 beef "(a) direct"
fi
end_tab 1

# (b) mosh: mosh-server on 127.0.0.1 runs the attach; the tab runs mosh-client.
mosh_tab() {
    # mosh_tab <n> <label> <port> <with prefix variable: 1 or 0>
    local n=$1 l=$2 port=$3 noprefix=$4 out key client
    new_desk "$n"
    # shellcheck disable=SC2046
    out=$(lim 30 env -i $(desk_env "$n") TERM=xterm-256color mosh-server new -i 127.0.0.1 -p "$port" -- /bin/bash "$HOST" attach --label "$l" website 2>&1)
    say "mosh-server new: $(printf '%s' "$out" | sed 's/MOSH CONNECT \([0-9]*\) .*/MOSH CONNECT \1 <key>/' | tr '\n' ';')"
    key=$(printf '%s\n' "$out" | awk '$1 == "MOSH" && $2 == "CONNECT" { print $4; exit }')
    MOSH_PID=$(printf '%s\n' "$out" | sed -n 's/.*detached, pid = \([0-9]*\).*/\1/p' | head -n 1)
    if [ -z "$key" ]; then
        result SKIPPED "(b) mosh: mosh-server starts" "mosh-server new did not print a key: $(printf '%s' "$out" | tr '\n' ';')"
        return 1
    fi
    client=$(command -v mosh-client)
    if [ "$noprefix" = 1 ]; then
        write_tab "$WORK/tab-$l.sh" "exec env MOSH_KEY=$key MOSH_TITLE_NOPREFIX=1 LANG=en_US.UTF-8 $client 127.0.0.1 $port"
    else
        write_tab "$WORK/tab-$l.sh" "exec env -u MOSH_TITLE_NOPREFIX MOSH_KEY=$key LANG=en_US.UTF-8 $client 127.0.0.1 $port"
    fi
    open_tab "$WORK/tab-$l.sh"
    if [ -z "$TTY" ]; then
        result FAIL "(b) mosh: open a tab" "no tty: $ANSWER $ERR"
        return 1
    fi
    return 0
}

# The desk server, mosh-server and the tab's mosh-client end before the window is closed, so that closing it
# asks nothing (on run 1 a window still running mosh-client stayed open).
end_mosh() {
    tm "$1" kill-server >> "$LOG" 2>&1
    if [ -n "${MOSH_PID:-}" ] && kill -0 "$MOSH_PID" 2>/dev/null; then kill "$MOSH_PID"; fi
    [ -n "$TTY" ] && pkill -x -t "${TTY#/dev/}" mosh-client >> "$LOG" 2>&1
    sleep 2
    [ -n "$TTY" ] && osa 15 "$close_tab" "$TTY"
}

if ! command -v mosh-server >/dev/null || ! command -v mosh-client >/dev/null; then
    result SKIPPED "(b) mosh" "mosh-server or mosh-client is not installed"
else
    if mosh_tab 2 cafe 60001 1; then
        read_before "(b) mosh" "(b) mosh"
        steps 2 cafe "(b) mosh"
    fi
    end_mosh 2
    # One read without MOSH_TITLE_NOPREFIX, to show mosh's own prefix.
    if mosh_tab 3 dead 60002 0; then
        for _ in $(seq 1 40); do
            [ "$(tm 3 list-clients 2>/dev/null | wc -l | tr -d ' ')" -ge 1 ] && break
            sleep 0.5
        done
        tmux_side 3
        wait_title "(b) mosh without MOSH_TITLE_NOPREFIX: the prefix shows" "[mosh] website" "mosh-prefix"
    fi
    end_mosh 3
fi

# (c) Tabs: iTerm2's control mode. Only what iTerm2 shows is recorded; nothing is changed for it.
if [ "$app" = iterm2 ]; then
    new_desk 4
    desk=$(tm 4 list-sessions -F '#{session_id} #{session_name}' | awk '$2 == "website" { print $1 }')
    w1=$(tm 4 display-message -p -t "$desk" '#{window_id}')
    tm 4 new-window -d -t "$desk:"
    say "window-name website $w1 api: $(host 4 window-name website "$w1" api 2>&1; echo "exit $?")"
    tmux_side 4
    # shellcheck disable=SC2046
    write_tab "$WORK/tab-c.sh" "exec env $(desk_env 4 | tr '\n' ' ') /bin/bash $(printf '%q' "$HOST") attach --cc website"
    osa 20 "$everything"
    say "before: $(printf '%s' "$ANSWER" | tr '\n' ';')"
    # On run 1, create window ... command with this tab's command did not answer in 30 s (on both macOS
    # versions), so the window is opened with its shell and the command is typed into it.
    TTY=""
    osa 30 "$open_plain"
    if [ "$STATUS" -eq 0 ] && [[ "$ANSWER" == /dev/ttys* ]]; then TTY=$ANSWER; fi
    if [ -z "$TTY" ]; then
        snap "tabs-no-window"
        result NOTE "(c) Tabs: open a tab" "no tty: osascript exit $STATUS [$ANSWER] $ERR"
    else
        sleep 2
        osa 20 "$type_in" "$TTY" "/bin/bash $WORK/tab-c.sh"
        sleep 14
        snap "tabs"
        osa 20 "$everything"
        result NOTE "(c) Tabs: what iTerm2 shows (window $w1 named api, a second window unnamed)" "$(printf '%s' "$ANSWER" | tr '\n' ';')"
        say "tmux clients: $(tm 4 list-clients -F '#{client_name} #{client_control_mode} #{session_name}' 2>&1 | tr '\n' ';')"
    fi
    tm 4 kill-server >> "$LOG" 2>&1
    sleep 3
    snap "tabs-after"
    [ -n "$TTY" ] && osa 15 "$close_tab" "$TTY"
fi

finish
