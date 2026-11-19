#!/bin/bash
# sitting-1.sh: walks through the five short tests of "sitting 1" and records what happened.
# Run it on the daily Mac (the Air), from a checkout of the macmosh repository:
#   scripts/sitting-1.sh <user@workhorse>
#   scripts/sitting-1.sh --dry-run <user@workhorse>     (prints every command, runs none)
# Plain bash 3.2 (what macOS ships at /bin/bash). It never asks for, reads or stores a password:
# ssh and sudo ask for it themselves. Design: docs/superpowers/specs/2026-11-18-macmosh-v1-design.md, section 9.
set -u

WORK_NAME=macmosh-sitting-1

usage() {
    cat <<'EOF'
usage: scripts/sitting-1.sh [--dry-run] <user@workhorse>

Walks you through the five tests of sitting 1. For each one it says what is about to happen,
shows the command, waits for Enter, runs it and asks what you saw. Everything goes into
~/macmosh-sitting-1/results.txt.

  --dry-run   print every command for all five items, run none of them, create no files
              and open no connection
EOF
}

# ---------------------------------------------------------------- arguments

DRY=0
HOST=""
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY=1 ;;
        -h | --help)
            usage
            exit 0
            ;;
        -*)
            echo "sitting-1.sh: unknown option $1" >&2
            usage >&2
            exit 2
            ;;
        *)
            if [ -n "$HOST" ]; then
                usage >&2
                exit 2
            fi
            HOST=$1
            ;;
    esac
    shift
done

host_re='^[A-Za-z0-9._-]+@[A-Za-z0-9._-]+$'
if ! [[ $HOST =~ $host_re ]]; then
    echo "sitting-1.sh: give the workhorse as user@host (letters, digits, dots and dashes only)." >&2
    usage >&2
    exit 2
fi
HOST_ONLY=${HOST#*@}
USER_ONLY=${HOST%@*}

# The pinned-key file goes in a folder with a space in its name, on purpose (item 3).
case "$HOME" in
    *[\'\"\$\`\\\&]*)
        echo "sitting-1.sh: your home folder's path has a quote, \$, backtick, backslash or & in it. Stopping." >&2
        exit 2
        ;;
esac
PIN_DIR="$HOME/Library/Application Support/MacMosh/sitting"
PIN="$PIN_DIR/known_hosts"
WORK="$HOME/$WORK_NAME"
RESULTS="$WORK/results.txt"
TMP="$WORK/.step-output"
# shellcheck disable=SC2088  # the tilde is for the workhorse's shell, not this one
REMOTE_SCRIPT='~/.macmosh/macmosh-host'

# One shared ssh connection, so the password is typed once. Steps that test host-key options
# switch it off (ControlPath=none), because a shared connection skips the host-key check.
# shellcheck disable=SC2016  # $HOME is meant to stay literal here; the shell that runs the step expands it
MUX='-o ControlMaster=auto -o ControlPersist=60m -o ControlPath="$HOME/macmosh-sitting-1/cm-%C"'

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd) || exit 1
REPO=$(dirname "$SCRIPT_DIR")
cd "$REPO" || exit 1

# ---------------------------------------------------------------- small helpers

# def NAME <<'EOF' ... EOF  stores the here-document in NAME, without its last line break.
def() {
    local text
    IFS= read -r -d '' text || true
    printf -v "$1" '%s' "${text%$'\n'}"
}

ADDR=""
PLUGDIR=""
fill() {
    local s=$1 target
    target="$USER_ONLY@${ADDR:-192.168.1.20}"
    s=${s//@W@/$HOST}
    s=${s//@H@/$HOST_ONLY}
    s=${s//@M@/$MUX}
    s=${s//@R@/$REMOTE_SCRIPT}
    s=${s//@PINDIR@/$PIN_DIR}
    s=${s//@PIN@/$PIN}
    s=${s//@T@/$target}
    s=${s//@PLUGDIR@/${PLUGDIR:-<your SwiftBar plugin folder>}}
    printf '%s' "$s"
}

say() { printf '%s\n' "$*"; }
rule() { printf '\n%s\n' "------------------------------------------------------------"; }

rec() {
    [ "$DRY" = 1 ] && return 0
    printf '%s\n' "$*" >> "$RESULTS"
}

stop_here() {
    echo
    echo "Stopped early. What you did so far is in $RESULTS"
    echo "The probe desk may still be on the workhorse. To remove it:"
    echo "  ssh $HOST '$REMOTE_SCRIPT desk-remove probe --kill'"
    exit 1
}

# ask <prompt>: puts the answer in REPLY. Ends the script on Ctrl-C or end of input.
ask() {
    printf '%s' "$1"
    if ! read -r REPLY; then
        stop_here
    fi
}

show_cmd() {
    printf '%s\n' "$1" | sed -e '1s/^/    $ /' -e '2,$s/^/      /'
}

# ---------------------------------------------------------------- steps

STEP=0
ITEM=0
WHERE="Item 0"

# run_step <label> <blurb> <mode> <hint> <command>
#   mode cap: the output is shown and recorded. mode tty: the step is interactive, so its output is not recorded.
run_step() {
    local label=$1 blurb=$2 mode=$3 hint=$4 cmd rc=0
    cmd=$(fill "$5")
    STEP=$((STEP + 1))
    [ "$DRY" = 1 ] || : > "$TMP"
    printf '\n%s, step %s: %s\n' "$WHERE" "$STEP" "$label"
    say "  $blurb"
    show_cmd "$cmd"
    if [ "$DRY" = 1 ]; then
        say "    (dry run: not run)"
        return 0
    fi
    ask "  Press Enter to run it, or type s and Enter to skip this step: "
    case "$REPLY" in
        s | S)
            rec ""
            rec "-- $WHERE, step $STEP: $label (skipped)"
            return 0
            ;;
    esac
    if [ "$mode" = cap ]; then
        bash -c "$cmd" 2>&1 | tee -a "$TMP"
        rc=${PIPESTATUS[0]}
    else
        bash -c "$cmd"
        rc=$?
    fi
    if [ "$rc" -ne 0 ]; then
        say "  That step ended with exit status $rc. It may be the result you are testing for: write down what you saw."
        say "  Carrying on."
    fi
    ask "  $hint
  > "
    rec ""
    rec "-- $WHERE, step $STEP: $label"
    rec "\$ $cmd"
    rec "exit status: $rc"
    if [ "$mode" = cap ]; then
        rec "output:"
        sed 's/^/    /' "$TMP" >> "$RESULTS"
    else
        rec "(interactive step: its output was not recorded)"
    fi
    rec "what you saw: $REPLY"
    return 0
}

# run_note <label> <blurb> <hint>: a pause with no command, for something he looks at and reports.
run_note() {
    local label=$1 blurb=$2 hint=$3
    STEP=$((STEP + 1))
    printf '\n%s, step %s: %s\n' "$WHERE" "$STEP" "$label"
    say "  $blurb"
    if [ "$DRY" = 1 ]; then
        say "    (dry run: nothing to run)"
        return 0
    fi
    ask "  $hint
  > "
    rec ""
    rec "-- $WHERE, step $STEP: $label (no command)"
    rec "what you saw: $REPLY"
}

# begin_item <number> <title> <blurb>: returns 1 when he skips the item.
begin_item() {
    ITEM=$1
    WHERE="Item $1"
    STEP=0
    rule
    printf 'ITEM %s: %s\n' "$1" "$2"
    printf '%s\n' "$3"
    if [ "$DRY" = 1 ]; then
        return 0
    fi
    rec ""
    rec "=============================================================="
    rec "ITEM $1: $2"
    ask "Press Enter to start this item, or type s and Enter to skip it: "
    case "$REPLY" in
        s | S)
            rec "Verdict: skipped"
            say "Skipped."
            return 1
            ;;
    esac
    return 0
}

# end_item <what a pass looks like>
end_item() {
    say ""
    say "What a pass looks like: $1"
    if [ "$DRY" = 1 ]; then
        return 0
    fi
    while :; do
        ask "Did item $ITEM pass? Type p (pass), f (fail) or s (skip it): "
        case "$REPLY" in
            p | P) rec "Verdict: pass"; break ;;
            f | F) rec "Verdict: fail"; break ;;
            s | S) rec "Verdict: skipped"; break ;;
        esac
    done
}

# ---------------------------------------------------------------- the five items

item_1() {
    begin_item 1 "Install the script and the login agent over ssh" \
"Puts the workhorse script and a login agent on the workhorse, makes a desk called probe,
then stops MacMosh's own desk server and attaches, to see that attaching starts it again.
MacMosh's server is separate: your own tmux sessions are never touched.
Do not log out of the workhorse to fix a failure: that ends every running session there." || return 0

    run_step "Sign in once" \
        "ssh asks for the workhorse's login password here, once. The other steps share this connection." \
        tty "Did ssh ask for the password and then return to the prompt?" \
        'ssh @M@ @W@ true'

    def CMD <<'EOF'
ssh @M@ @W@ 'mkdir -p ~/.macmosh && cat > ~/.macmosh/macmosh-host && chmod 755 ~/.macmosh/macmosh-host' < host/macmosh-host
EOF
    run_step "Copy the script to the workhorse" \
        "Copies host/macmosh-host into ~/.macmosh on the workhorse and makes it runnable." \
        cap "Did it finish without an error message?" "$CMD"

    run_step "Install the login agent" \
        "Asks the workhorse to write and load its login agent. This is the question: does launchctl accept it over ssh?" \
        cap "What did it print? Was there an error?" \
        "ssh @M@ @W@ '@R@ install-agent'"

    run_step "Read the status report" \
        "Look for these lines: server up, signins ok, agent installed." \
        cap "Do you see server up, signins ok and agent installed? Write what you see for each." \
        "ssh @M@ @W@ '@R@ status'"

    def CMD <<'EOF'
ssh @M@ @W@ '~/.macmosh/macmosh-host desk-new probe "$HOME"'
EOF
    run_step "Make the probe desk" \
        "Creates a desk called probe in the workhorse's home folder." \
        cap "Did it finish without an error message?" "$CMD"

    def CMD <<'EOF'
ssh @M@ @W@ 'PATH="$PATH:/opt/homebrew/bin:/usr/local/bin" tmux -L macmosh kill-server'
EOF
    run_step "Stop MacMosh's own desk server" \
        "Stops only the server on tmux's socket named macmosh, which holds only the probe desk. Your own tmux sessions are on another server and stay up." \
        cap "Did it finish without an error message?" "$CMD"

    run_step "Read the status report again" \
        "Now the report should say server down." \
        cap "Does it say server down?" \
        "ssh @M@ @W@ '@R@ status'"

    run_step "Attach to the probe desk" \
        "attach should ask the login agent to start the server again. Inside the desk, type: gh auth status. Then press Ctrl-b, let go, and press d to leave the desk." \
        tty "Did the desk open? What did gh auth status say? (If attach printed an error, copy it.)" \
        "ssh -t @M@ @W@ '@R@ attach probe'"

    run_step "Read the status report a third time" \
        "The report should say server up and signins ok again, now that attach has started the server." \
        cap "Do you see server up and signins ok?" \
        "ssh @M@ @W@ '@R@ status'"

    end_item "the report says server up and signins ok after the install, and again after the server was stopped and attach asked the login agent to start it."
}

item_2() {
    begin_item 2 "Opening a tab from a script, in iTerm2 and in Terminal" \
"Tries the ways of opening a new terminal tab that runs a command. macOS may ask for permission each time.
For each step, copy down the exact wording of any prompt macOS shows. Close the tabs yourself afterwards." || return 0

    local hint="Write down the exact words of any macOS permission prompt (what wants to control what, and the button names). Did a tab open and show the text? New tab or new window?"

    def CMD <<'EOF'
osascript - 'echo hello from macmosh; read' <<'APPLESCRIPT'
on run argv
    tell application "iTerm2"
        activate
        if (count of windows) is 0 then
            create window with default profile command (item 1 of argv)
        else
            tell current window
                create tab with default profile command (item 1 of argv)
            end tell
        end if
    end tell
end run
APPLESCRIPT
EOF
    run_step "iTerm2: create tab with default profile command" \
        "Opens a tab in iTerm2's front window that runs the command, which is passed as an argument." \
        cap "$hint" "$CMD"

    def CMD <<'EOF'
osascript - 'echo hello from macmosh; read' <<'APPLESCRIPT'
on run argv
    tell application "Terminal"
        activate
        do script (item 1 of argv)
    end tell
end run
APPLESCRIPT
EOF
    run_step "Terminal: do script" \
        "Runs the command in Terminal. Note whether it opens a new window or a tab in an old one." \
        cap "$hint" "$CMD"

    def CMD <<'EOF'
osascript - 'echo hello from macmosh; read' <<'APPLESCRIPT'
on run argv
    tell application "Terminal"
        activate
        do script (item 1 of argv) in new tab
    end tell
end run
APPLESCRIPT
EOF
    run_step "Terminal: do script in new tab" \
        "Runs the command in a new tab of Terminal's front window. Have a Terminal window open first." \
        cap "$hint" "$CMD"

    def CMD <<'EOF'
printf '#!/bin/sh\necho hello from macmosh\nread dummy\n' > "$HOME/macmosh-sitting-1/hello.command" && chmod +x "$HOME/macmosh-sitting-1/hello.command" && open -a iTerm "$HOME/macmosh-sitting-1/hello.command"
EOF
    run_step "A .command file opened with iTerm2" \
        "Writes a small .command file and opens it with iTerm2. This is the fallback if the permission is refused." \
        cap "$hint" "$CMD"

    def CMD <<'EOF'
open -a Terminal "$HOME/macmosh-sitting-1/hello.command"
EOF
    run_step "The same .command file opened with Terminal" \
        "Opens the same file with Terminal." \
        cap "$hint" "$CMD"

    end_item "a tab opens and shows the text, the wording of each permission prompt is written down, and you know which form opens a tab in an existing window."
}

item_3() {
    begin_item 3 "mosh with a pinned host key and a one-week timeout" \
"Builds a file with the workhorse's host key, then connects with mosh using that file and a timeout of one week,
and checks the setting arrived. This step asks for the workhorse's password through mosh's own ssh.
If the Air has no mosh, run: brew install mosh" || return 0

    def CMD <<'EOF'
mkdir -p "@PINDIR@" && ssh-keyscan -t ed25519 @H@ 2>/dev/null | awk 'NF >= 3 && $1 !~ /^#/ { $1 = "macmosh-sitting"; print }' > "@PIN@" && test -s "@PIN@" && cat "@PIN@" && ssh-keygen -lf "@PIN@"
EOF
    run_step "Pin the workhorse's host key" \
        "Asks the workhorse for its ed25519 host key and saves it under the name macmosh-sitting, in a folder with a space in its name." \
        cap "Did it print a key and a fingerprint?" "$CMD"

    def CMD <<'EOF'
mosh --ssh="ssh -o HostKeyAlias=macmosh-sitting -o 'UserKnownHostsFile=\"@PIN@\"' -o StrictHostKeyChecking=yes -o ControlPath=none" --server='MOSH_SERVER_NETWORK_TMOUT=604800 PATH="$PATH:/opt/homebrew/bin:/usr/local/bin" mosh-server' @W@ -- /bin/sh -c 'exec "$HOME/.macmosh/macmosh-host" attach "$1"' macmosh-host probe
EOF
    run_step "Open the probe desk with mosh" \
        "mosh asks for the password, then opens the desk. Inside the desk, type this, then press Ctrl-b, let go, and press d to leave:
      ps eww -o command= -p \"\$(pgrep -n mosh-server)\" | tr ' ' '\\n' | grep -a MOSH_SERVER_NETWORK_TMOUT | tee ~/.macmosh/sitting-3-ps.txt" \
        tty "Did the desk open? Was there a host-key error? Did the ps line show MOSH_SERVER_NETWORK_TMOUT=604800?" "$CMD"

    run_step "Read back what the ps line found" \
        "Shows the file the ps line wrote on the workhorse." \
        cap "Does it say MOSH_SERVER_NETWORK_TMOUT=604800?" \
        'ssh @M@ @W@ '\''cat ~/.macmosh/sitting-3-ps.txt'\'

    def CMD <<'EOF'
ssh-keygen -q -t ed25519 -N '' -f "$HOME/macmosh-sitting-1/test_key" < /dev/null; ssh-copy-id -n -i "$HOME/macmosh-sitting-1/test_key.pub" -o HostKeyAlias=macmosh-sitting -o 'UserKnownHostsFile="@PIN@"' -o StrictHostKeyChecking=yes -o ControlPath=none @W@
EOF
    run_step "Try ssh-copy-id as a dry run" \
        "Makes a throwaway test key, then runs ssh-copy-id in dry-run mode (-n) with the same pinned options. It installs nothing." \
        cap "Did it print the key it would install? Was there a host-key error?" "$CMD"

    end_item "the desk opens, the ps line shows MOSH_SERVER_NETWORK_TMOUT=604800, and the dry run prints the key it would install with no host-key error."
}

item_4() {
    begin_item 4 "Tabs mode that reconnects by itself" \
"Runs ssh in a retry loop, with iTerm2's tmux tabs, then you turn Wi-Fi off for 20 seconds and on again.
Run this item from iTerm2. The loop uses the probe desk from item 1.
No key is installed, so ssh asks for the password again each time it reconnects." || return 0

    if [ "$DRY" != 1 ] && [ "${TERM_PROGRAM:-}" != "iTerm.app" ]; then
        say "  This does not look like iTerm2 (TERM_PROGRAM is ${TERM_PROGRAM:-empty}). If so, skip this item and run the helper again from iTerm2."
    fi

    def CMD <<'EOF'
while true; do
    ssh -t -o ControlPath=none -o ServerAliveInterval=5 -o ServerAliveCountMax=2 @W@ '~/.macmosh/macmosh-host attach --cc probe'
    rc=$?
    [ "$rc" -eq 255 ] || break
    echo 'Connection lost. Trying again in 3 seconds...'
    sleep 3
done
exit "$rc"
EOF
    run_step "Attach in Tabs mode, then drop Wi-Fi" \
        "Type the password when asked. When the iTerm2 tabs appear, turn Wi-Fi off for 20 seconds, then on. Watch the loop and the tabs. To finish: press Esc in the first tab, or choose Shell > tmux > Detach. Ctrl-C ends the loop." \
        tty "Did the loop print Connection lost? Did it ask for the password again? Did the tabs come back?" "$CMD"

    end_item "the iTerm2 tabs come back after Wi-Fi returns, with nothing from you except the password."
}

item_5() {
    begin_item 5 "The home address and macOS's Local Network question" \
"Puts a tiny SwiftBar plugin in the menu bar. It tries ssh to the workhorse's home address every 10 seconds.
macOS should ask once whether SwiftBar may use the local network. Before you click Allow, ssh should say No route to host.
Open SwiftBar yourself first, and pick a plugin folder if it asks." || return 0

    if [ ! -s "$PIN" ] && [ "$DRY" != 1 ]; then
        say "  The pinned key from item 3 is missing. Building it now."
        def CMD <<'EOF'
mkdir -p "@PINDIR@" && ssh-keyscan -t ed25519 @H@ 2>/dev/null | awk 'NF >= 3 && $1 !~ /^#/ { $1 = "macmosh-sitting"; print }' > "@PIN@" && test -s "@PIN@" && cat "@PIN@"
EOF
        run_step "Pin the workhorse's host key" \
            "Same as item 3, step 1." cap "Did it print a key?" "$CMD"
    fi

    def CMD <<'EOF'
ssh @M@ @W@ '@R@ status' | awk -F'\t' '$1 == "home" { print $2 }'
EOF
    run_step "Find the workhorse's home address" \
        "Reads the home line of the status report, second field." \
        cap "Is that the workhorse's address on your home network?" "$CMD"
    if [ "$DRY" != 1 ]; then
        local addr_re='^[0-9]{1,3}(\.[0-9]{1,3}){3}$' line
        ADDR=""
        while IFS= read -r line; do
            if [[ $line =~ $addr_re ]]; then
                ADDR=$line
                break
            fi
        done < "$TMP"
        while ! [[ $ADDR =~ $addr_re ]]; do
            ask "  Type the workhorse's home address (like 192.168.1.20): "
            ADDR=$REPLY
        done
        say "  Using $ADDR."
    fi

    run_step "Find SwiftBar's plugin folder" \
        "Reads SwiftBar's setting. If it prints nothing, open SwiftBar and choose a plugin folder first." \
        cap "Is that the folder SwiftBar uses?" \
        'defaults read com.ameba.SwiftBar PluginDirectory'
    if [ "$DRY" != 1 ]; then
        PLUGDIR=$(tail -n 1 "$TMP")
        case "$PLUGDIR" in
            /* | "~"/*) ;;
            *) PLUGDIR="" ;;
        esac
        PLUGDIR=${PLUGDIR/#\~/$HOME}
        while :; do
            case "$PLUGDIR" in
                '' | *[\"\$\`\\]*) ;;
                *)
                    if [ -d "$PLUGDIR" ]; then break; fi
                    ;;
            esac
            ask "  Type the full path of SwiftBar's plugin folder: "
            PLUGDIR=${REPLY/#\~/$HOME}
        done
        say "  Using $PLUGDIR."
    fi

    def CMD <<'EOF'
cat > "@PLUGDIR@/macmosh-sitting-5.10s.sh" <<'PLUGIN'
#!/bin/bash
out=$(/usr/bin/ssh -o BatchMode=yes -o ConnectTimeout=5 -o ControlPath=none -o HostKeyAlias=macmosh-sitting -o 'UserKnownHostsFile="@PIN@"' -o StrictHostKeyChecking=yes @T@ true 2>&1)
rc=$?
echo "ssh exit $rc"
echo '---'
echo "$out" | tr '|' ' '
echo "$(date +%T) exit $rc: $(echo "$out" | tr '\n' ' ')" >> "$HOME/macmosh-sitting-1/item-5.log"
PLUGIN
chmod +x "@PLUGDIR@/macmosh-sitting-5.10s.sh"
EOF
    run_step "Install the plugin" \
        "Writes the plugin into SwiftBar's folder. SwiftBar picks it up within a few seconds and runs it every 10 seconds." \
        cap "Did it finish without an error message?" "$CMD"

    run_note "Before you click Allow" \
        "Wait up to 15 seconds. macOS should ask whether SwiftBar may find and connect to devices on your local network. Do NOT click Allow yet. Click SwiftBar's icon in the menu bar and read the menu." \
        "Copy the exact wording of the macOS prompt. What does the menu say (ssh exit number and message)?"

    run_note "After you click Allow" \
        "Click Allow. Wait 15 seconds, then read the menu again." \
        "What does the menu say now? A pass is ssh exit 0 or Permission denied. No route to host is still a fail."

    run_step "Read the plugin's log" \
        "The plugin wrote one line per run, so the change from No route to host is on record." \
        cap "Does the log show No route to host first and something else after Allow?" \
        "cat \"\$HOME/macmosh-sitting-1/item-5.log\""

    run_step "Remove the plugin" \
        "Deletes the test plugin, so SwiftBar stops running it." \
        cap "Did it finish without an error message?" \
        "rm -f \"@PLUGDIR@/macmosh-sitting-5.10s.sh\""

    end_item "before Allow, ssh says No route to host; after Allow it doesn't. An exit 0 or Permission denied both count."
}

finish() {
    rule
    say "Clean up"
    WHERE="Clean up"
    STEP=0
    if [ "$DRY" != 1 ]; then
        rec ""
        rec "=============================================================="
        rec "CLEAN UP"
    fi
    def CMD <<'EOF'
ssh @M@ @W@ '~/.macmosh/macmosh-host desk-remove probe --kill; rc=$?; rm -f ~/.macmosh/sitting-3-ps.txt; exit $rc'
EOF
    run_step "Remove the probe desk" \
        "Removes the probe desk and closes its session. Only MacMosh's own server is touched." \
        cap "Did it finish without an error message?" "$CMD"

    def CMD <<'EOF'
ssh -o ControlPath="$HOME/macmosh-sitting-1/cm-%C" -O exit @W@
EOF
    run_step "Close the shared ssh connection" \
        "Closes the one connection the steps shared." \
        cap "Did it finish without an error message?" "$CMD"

    rule
    say "Done."
    say "The script and the login agent stay installed on the workhorse, as agreed."
    say "Nothing else was changed there. To remove them later, see the end of docs/sittings/sitting-1.md."
    if [ "$DRY" != 1 ]; then
        say "Your results are in: $RESULTS"
    fi
}

# ---------------------------------------------------------------- main

main() {
    if [ "$DRY" = 1 ]; then
        rule
        say "DRY RUN: every command for all five items is printed below and none is run."
        say "No files are created and no connection is opened."
        say "Workhorse: $HOST   Repository: $REPO"
    else
        if [ ! -t 0 ]; then
            echo "sitting-1.sh: this needs a terminal to ask you questions." >&2
            exit 2
        fi
        if [ ! -f "$REPO/host/macmosh-host" ]; then
            echo "sitting-1.sh: cannot find $REPO/host/macmosh-host. Run this from a checkout of the macmosh repository." >&2
            exit 1
        fi
        umask 077
        mkdir -p "$WORK" || exit 1
        # Ctrl-C stops the step that is running, not the whole walk-through.
        trap ':' INT
        rec ""
        rec "MacMosh sitting 1: results"
        rec "Started: $(date '+%Y-%m-%d %H:%M:%S')"
        rec "Workhorse: $HOST"
        rec "Helper: scripts/sitting-1.sh"
        rule
        say "MacMosh sitting 1. Five short tests. About 45 minutes."
        say "At each step: Enter runs it, s skips it. The helper never asks for a password."
        say "ssh asks for the workhorse's login password itself, once at the start."
        say "Results go to $RESULTS"
        ask "Press Enter to begin: "
    fi
    item_1
    item_2
    item_3
    item_4
    item_5
    finish
}

main
