#!/bin/bash
# Starts sitting 2 on the daily Mac. Two things, in order:
#
#   1. starts the recorder (record.sh, beside this file), which runs in the background;
#   2. opens a desk called sitting-2 on the workhorse, marked to come back after a restart.
#
# The desk's tab is a shell on the workhorse. The sitting's two pmset commands are typed there,
# and after the restart the desk should be back in the menu by itself.
set -u

here="$(cd "$(dirname "$0")" && pwd)"
helper="${MACMOSH_HELPER:-/Applications/MacMosh.app/Contents/Helpers/macmosh}"
support="${MACMOSH_SUPPORT_DIR:-$HOME/Library/Application Support/MacMosh}"
desk="sitting-2"

id=$(plutil -extract workhorses.0.id raw -o - "$support/workhorses.json" 2>/dev/null || true)
if [ -z "$id" ]; then
    echo "start.sh: MacMosh has no saved workhorse on this Mac. Pair one first (Add a Mac… in the menu)." >&2
    exit 1
fi

bash "$here/record.sh" || exit 1
echo

# The desk may be there already, from an earlier start. Then this opens it instead of making it.
if "$helper" desks "$id" 2>/dev/null | grep -q "^$desk "; then
    echo "The desk $desk is already there. Opening it."
    exec "$helper" connect "$id" "$desk"
fi
echo "Making the desk $desk on the workhorse, marked to come back after a restart."
exec "$helper" desk new "$id" "$desk" --folder '~' --reopen
