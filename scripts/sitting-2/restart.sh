#!/bin/bash
# Sitting 2's restart, run on the daily Mac. It is one MacMosh command with the workhorse's name
# filled in:
#
#   macmosh restart <workhorse> --full
#
# `--full` asks for a restart that leaves the disk locked, so that "Unlock disk…" is tried too.
# The menu's own "Restart…" skips the unlock, which is why this isn't a click.
#
# MacMosh lists the desks that will close, asks you to type the word restart, and then ssh asks for
# the workhorse's password. Nothing restarts before that.
set -u

helper="${MACMOSH_HELPER:-/Applications/MacMosh.app/Contents/Helpers/macmosh}"
support="${MACMOSH_SUPPORT_DIR:-$HOME/Library/Application Support/MacMosh}"

id=$(plutil -extract workhorses.0.id raw -o - "$support/workhorses.json" 2>/dev/null || true)
if [ -z "$id" ]; then
    echo "restart.sh: MacMosh has no saved workhorse on this Mac." >&2
    exit 1
fi

echo "This restarts the workhorse. Everything running on it stops: MacMosh's desks, and also every"
echo "other terminal session and agent on it, which MacMosh does not list below."
echo
exec "$helper" restart "$id" --full
