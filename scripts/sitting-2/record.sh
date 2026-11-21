#!/bin/bash
# Sitting 2's recorder. It runs on the daily Mac. Every 20 seconds, for two hours at most, it
# writes down what MacMosh says about the workhorse and what ssh sees at each of the workhorse's
# addresses, so nobody takes notes during the lid test and the restart.
#
# It only reads. It changes nothing on either Mac, types no password, and uses MacMosh's own key
# and pinned host key, the way the app's checks do.
#
#   record.sh            start recording in the background, then return
#   record.sh --once     one round, printed to the terminal (to see that it works)
#   record.sh --stop     stop a recorder that is running
#   record.sh --loop     the loop itself; this is what the background copy runs
#
# The record holds real names, addresses and key fingerprints. It stays in ~/macmosh-sitting-2 on
# this Mac and is never copied into the repository.
set -u

dir="${MACMOSH_SITTING_DIR:-$HOME/macmosh-sitting-2}"
log="$dir/record.log"
pidfile="$dir/recorder.pid"
helper="${MACMOSH_HELPER:-/Applications/MacMosh.app/Contents/Helpers/macmosh}"
support="${MACMOSH_SUPPORT_DIR:-$HOME/Library/Application Support/MacMosh}"
list="$support/workhorses.json"
every=20      # seconds between rounds
limit=7200    # the recorder ends by itself after two hours

# One value from the first workhorse in MacMosh's saved list. Empty when the list doesn't have it.
saved() {
    plutil -extract "workhorses.0.$1" raw -o - "$list" 2>/dev/null || true
}

load_workhorse() {
    if [ ! -f "$list" ]; then
        echo "record.sh: MacMosh has no saved workhorse on this Mac ($list is missing)." >&2
        exit 1
    fi
    id=$(saved id)
    user=$(saved user)
    main_address=$(saved mainAddress)
    home_address=$(saved homeAddress)
    local_name=$(saved localName)
    identity=$(saved identityFile)
    if [ -z "$identity" ]; then identity="$HOME/.ssh/macmosh_ed25519"; fi
    if [ -z "$id" ] || [ -z "$user" ]; then
        echo "record.sh: can't read the workhorse's id and user name from $list." >&2
        exit 1
    fi
    # The fingerprint of the host key MacMosh pinned when the workhorse was added.
    pinned=$(ssh-keygen -lf "$support/known_hosts" 2>/dev/null | awk 'NR == 1 {print $2}')
}

# ssh the way MacMosh's own checks run it: its key only, the pinned host key only, no password.
macmosh_ssh() {
    ssh -o "HostKeyAlias=macmosh-$id" -o "UserKnownHostsFile=\"$support/known_hosts\"" \
        -o GlobalKnownHostsFile=/dev/null -o StrictHostKeyChecking=yes -o UpdateHostKeys=no \
        -o IdentitiesOnly=yes -i "$identity" -o IdentityAgent=none \
        -o BatchMode=yes -o ConnectTimeout=5 "$@"
}

# One line about one address: did ssh get in, which sign-in methods the Mac offers there, which host
# key it shows and whether that is the pinned one, and what ssh said last.
# Sets `answered` to the label of the first address where MacMosh's key got in.
probe() {
    local label="$1" address="$2" out code offers key server says same
    if [ -z "$address" ]; then
        echo "probe $label: no address saved"
        return
    fi
    out=$(macmosh_ssh -v -- "$user@$address" true 2>&1)
    code=$?
    offers=$(printf '%s\n' "$out" | sed -n 's/^debug1: Authentications that can continue: //p' | tail -n 1)
    key=$(printf '%s\n' "$out" | sed -n 's/^debug1: Server host key: //p' | tail -n 1)
    server=$(printf '%s\n' "$out" | sed -n 's/^debug1: Remote protocol version [^,]*, remote software version //p' | tail -n 1)
    # What ssh itself said last, without its debug lines and its closing statistics.
    says=$(printf '%s\n' "$out" | grep -v -e '^debug1: ' -e '^[[:space:]]*$' -e '^Transferred: ' -e '^Bytes per second: ' | tail -n 1)
    same="-"
    if [ -n "$key" ] && [ -n "$pinned" ]; then
        case "$key" in
            *"$pinned"*) same="same as pinned" ;;
            *) same="DIFFERENT from pinned" ;;
        esac
    fi
    echo "probe $label: exit=$code | offers=${offers:--} | key=${key:--} ($same) | server=${server:--} | says=${says:--}"
    if [ "$code" -eq 0 ] && [ -z "$answered" ]; then
        answered="$label"
        answered_address="$address"
    fi
}

round() {
    local number="$1" json code
    echo "=== $(date '+%Y-%m-%dT%H:%M:%S%z') round $number"
    json=$("$helper" status "$id" --json 2>&1)
    code=$?
    echo "macmosh status: exit=$code $(printf '%s' "$json" | tr -s '\n\t ' '   ')"
    answered=""
    answered_address=""
    probe main "$main_address"
    probe home "$home_address"
    probe local "$local_name"
    if [ -n "$answered" ]; then
        # The workhorse's own report, word for word: who is at the screen, the desk server, the
        # sign-in check, the power settings and the desks. Then what pmset itself prints about the
        # lid-closed setting, because nobody has written down where that setting shows up.
        # shellcheck disable=SC2088  # the workhorse's shell expands this ~, not this Mac's
        macmosh_ssh -- "$user@$answered_address" '~/.macmosh/macmosh-host status' 2>&1 | sed "s/^/report@$answered: /"
        macmosh_ssh -- "$user@$answered_address" 'pmset -g; pmset -g custom' 2>&1 \
            | grep -i -e 'SleepDisabled' -e 'disablesleep' -e '^ sleep ' | sed "s/^/pmset@$answered: /"
    else
        echo "report: no address let MacMosh's key in"
    fi
}

case "${1:-}" in
    --once)
        load_workhorse
        round 1
        ;;
    --stop)
        if [ -f "$pidfile" ] && kill -0 "$(cat "$pidfile")" 2>/dev/null; then
            kill "$(cat "$pidfile")"
            echo "The recorder is stopped. Its record is $log"
        else
            echo "No recorder is running."
        fi
        ;;
    --loop)
        load_workhorse
        echo "$$" > "$pidfile"
        started=$(date +%s)
        number=0
        echo "### recorder started $(date '+%Y-%m-%dT%H:%M:%S%z'): workhorse $id, a round every $every seconds, for $((limit / 60)) minutes at most"
        while [ $(( $(date +%s) - started )) -lt "$limit" ]; do
            number=$((number + 1))
            round "$number"
            sleep "$every"
        done
        echo "### recorder ended by itself $(date '+%Y-%m-%dT%H:%M:%S%z') after $number rounds"
        ;;
    "")
        load_workhorse
        mkdir -p "$dir"
        if [ -f "$pidfile" ] && kill -0 "$(cat "$pidfile")" 2>/dev/null; then
            echo "A recorder is already running (it started earlier). Its record is $log"
            exit 0
        fi
        # `caffeinate -i` keeps this Mac from going to sleep by itself while the recorder runs. It
        # changes no setting, and it ends with the recorder.
        nohup caffeinate -i bash "$0" --loop >> "$log" 2>&1 &
        echo "Recording what MacMosh and ssh see, every $every seconds, for two hours at most."
        echo "The record is $log"
        echo "You can close this tab. To stop it early: bash $0 --stop"
        ;;
    *)
        echo "usage: record.sh [--once | --stop]" >&2
        exit 2
        ;;
esac
