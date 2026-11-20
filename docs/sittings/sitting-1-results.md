# Sitting 1: results

Shariq ran sitting 1 on 2026-11-20, from 10:59 to 11:11 PT, at the MacBook Air, with `scripts/sitting-1.sh`. **All four items passed.**

Two checks were skipped during the sitting. The build agent ran them straight afterwards, and they are marked "checked afterwards" below.

Every user name, host name, address and key in this file is a placeholder: `alex`, `workhorse`, `daily-mac`, `192.168.1.20`, `<key>` and `SHA256:<fingerprint>`. `mbp` is the short name the sitting used for the workhorse.

| Item | Question | Verdict | What the build does with it |
|---|---|---|---|
| 1 | Can the script and the login agent be installed and started over ssh, and do desks started that way keep sign-ins? | Pass | Task 13 installs over ssh as planned |
| 2 | Which way of opening a tab works in iTerm2 and in Terminal, and what does macOS ask? | Pass, with one finding | Task 16 uses the iTerm2 form as tested. In Terminal a desk opens in a new window, not a tab |
| 3 | Does mosh take the pinned host key and the one-week timeout? | Pass | Task 15 builds the mosh line as tested |
| 4 | Does Tabs mode come back by itself after the Wi-Fi drops? | Pass | Task 15 keeps the retry loop |

## Item 1: login agent installed and started over ssh

**What was run.** Over ssh from the Air: copy `host/macmosh-host` (version 0.3.0) to `~/.macmosh/` on the workhorse, run `macmosh-host install-agent`, read `macmosh-host status`, make a desk called `probe`, stop MacMosh's desk server (`tmux -L macmosh kill-server`), then run `macmosh-host attach probe`.

**What was seen.**

- ssh signed in with the key already on the Air. Nothing asked for a password.
- `install-agent` printed nothing and exited 0. The status report straight after it said `server up`, `signins ok` and `agent installed`: installing the login agent over ssh also started the desk server, in the login session.
- After the desk server was stopped, the report said `server down` and `signins unknown`, and still listed the desk `probe` as saved.
- `attach probe` started the server again by itself and opened the desk. The report after it said `server up` and `signins ok`.
- The workhorse runs macOS 27.3, with mosh-server 1.4.0 and tmux 3.8 from Homebrew.
- Shariq left the desk with `exit` instead of detaching, and did not run `gh auth status` inside it.
- **Checked afterwards:** from inside MacMosh's desk server (`tmux -L macmosh run-shell`), the keychain check passed and `gh auth status` reported a signed-in account.

**Verdict: pass.** Task 13 writes `HostInstaller` as planned.

## Item 2: opening a tab from a script (iTerm2 and Terminal)

**What was run.** From iTerm2 on the Air, five ways of starting the line `<stand-in script> connect mbp website`. The stand-in prints its arguments, sets the tab's title to its third argument and waits for Enter.

| Way | What opened | Showed the line | Title `website` | What macOS asked |
|---|---|---|---|---|
| iTerm2, AppleScript `create tab with default profile command` | A new tab | Yes | Yes | Nothing |
| Terminal, AppleScript `do script` | A new window | Yes | Not checked | The prompt below |
| Terminal, AppleScript `do script … in new tab` | Nothing: a syntax error (-2741) | No | No | Nothing |
| A `.command` file opened with `open -a iTerm` | A new tab | Yes | Yes | Nothing |
| The same file opened with `open -a Terminal` | A new window | Yes | No name shown | Nothing |

The prompt, the first time iTerm2 ran the Terminal script (the button names were not written down):

> “iTerm.app” wants access to control “Terminal.app”. Allowing control will provide access to documents and data in “Terminal.app”, and to perform actions within that app.

What this means:

- **iTerm2:** the AppleScript form in the design works. A tab opens, runs the line and takes the desk's name.
- **Terminal opens a window, not a tab.** The third way failed because the script in the runbook was wrong, not because of anything Terminal did. `do script` can be told to run in a tab or window that already exists, and it has nothing that asks for a new tab. **Checked afterwards** in Terminal's scripting dictionary on macOS 27.3 (`sdef /System/Applications/Utilities/Terminal.app`).
- **The `.command` file asks for nothing** in either terminal, so it stays the fallback for when the Automation permission is refused.
- **No prompt for iTerm2 here does not mean no prompt for the app.** These scripts were run from iTerm2, so iTerm2 was controlling itself. When MacMosh.app sends the same script, macOS asks about MacMosh. That prompt is read at the app's first run (Task 20).
- **Terminal showed no name for the window.** The stand-in sets the title with `ESC ] 1 ; <title> BEL`, which iTerm2 shows on the tab. Whether Terminal shows it anywhere is not settled.

**Verdict: pass.** Task 16 uses the iTerm2 form as tested, `do script` for Terminal, and the `.command` file as the fallback.

## Item 3: mosh with a pinned key and a one-week timeout

**What was run.** `ssh-keyscan` for the workhorse's ed25519 key, saved under the name `macmosh-sitting` in a known-hosts file inside `~/Library/Application Support/MacMosh/` (a path with a space in it). Then mosh, with that file and name passed through `--ssh` and the timeout through `--server`:

```
mosh --ssh="ssh -o HostKeyAlias=macmosh-sitting -o 'UserKnownHostsFile=\"<file>\"' -o StrictHostKeyChecking=yes -o ControlPath=none" \
     --server='MOSH_SERVER_NETWORK_TMOUT=604800 PATH="$PATH:/opt/homebrew/bin:/usr/local/bin" mosh-server' \
     mbp -- /bin/sh -c 'exec "$HOME/.macmosh/macmosh-host" attach "$1"' macmosh-host probe
```

Then `ssh-copy-id -n` (a dry run) with a new test key and the same options.

**What was seen.**

- The key and its fingerprint were saved and printed.
- mosh opened the desk `probe` with no host-key error. The path with a space, quoted as above, works.
- Shariq did not run the `ps` line inside the desk, so the timeout was not read during the sitting.
- **Checked afterwards:** the same mosh command, run from the Air with a one-line command in place of the desk, reported `MOSH_SERVER_NETWORK_TMOUT=604800` from under mosh-server on the workhorse. No mosh-server was left running.
- `ssh-copy-id -n` printed the one key it would add, with no host-key error.

**Verdict: pass.** Task 15 builds the mosh line as tested.

## Item 4: Tabs mode reconnects after Wi-Fi drops

**What was run.** In an iTerm2 tab: ssh with `ServerAliveInterval=5` and `ServerAliveCountMax=2`, running `macmosh-host attach --cc probe`, inside a loop that runs it again after 3 seconds whenever ssh ends with exit code 255. Then Wi-Fi off and on.

**What was seen.**

- The desk's tab came back by itself, with nothing typed. Shariq did not see the loop's "Connection lost" line.
- The workhorse's log shows the loop at work: `attach probe` at 11:08:56, and again at 11:09:39.

**Verdict: pass.** Task 15 keeps the retry loop.

## Not settled by this sitting

- What macOS asks when MacMosh.app, not iTerm2, opens a tab, and what the buttons say. Read at the app's first run (Task 20).
- Whether Terminal shows a desk's name anywhere.
- What macOS asks when the app first reaches the home address. This was item 5 until 2026-11-19 and is now part of Task 20.

## What the sitting left in place

- **On the workhorse:** `~/.macmosh/` (the script, an empty desk list, MacMosh's tmux settings and its log) and the login agent `io.github.shariqh.macmosh.host`. MacMosh's desk server is running with no desks. This is the install Shariq agreed to on 2026-11-19. His own tmux sessions were not touched.
- **On the Air:** the folder `~/macmosh-sitting-1/` (the record, the stand-in script and a test key that was never installed anywhere) and the pinned-key file in `~/Library/Application Support/MacMosh/sitting/`. macOS now lets iTerm2 control Terminal there.

## The helper's record

This is `~/macmosh-sitting-1/results.txt` from the Air, with the placeholders above. The answers after `->` are Shariq's, as typed.

<details>
<summary>The full record</summary>

````
MacMosh sitting 1: results
Started: 2026-11-20 10:59:26
Workhorse: mbp
Helper: scripts/sitting-1.sh

-- Setup, step 1: Read the real host name, port and user
$ ssh -G mbp | grep -E '^(hostname|port|user) '
exit status: 0
output:
    user alex
    hostname workhorse
    port 22
what you saw:
  Do the host name, port and user look right? -> yes

Resolved by ssh -G: user alex, host workhorse, port 22

==============================================================
ITEM 1: Install the script and the login agent over ssh

-- Item 1, step 1: Sign in once
$ ssh -o ControlMaster=auto -o ControlPersist=60m -o ControlPath="$HOME/macmosh-sitting-1/cm-%C" mbp true
exit status: 0
(interactive step: its output was not recorded)
what you saw:
  Did it return to the prompt without asking for anything? (If ssh asked for a password, say so.) -> yes

-- Item 1, step 2: Copy the script to the workhorse
$ ssh -o ControlMaster=auto -o ControlPersist=60m -o ControlPath="$HOME/macmosh-sitting-1/cm-%C" mbp 'mkdir -p ~/.macmosh && cat > ~/.macmosh/macmosh-host && chmod 755 ~/.macmosh/macmosh-host' < host/macmosh-host
exit status: 0
output:
what you saw:
  Did it finish without an error message? -> yes

-- Item 1, step 3: Install the login agent
$ ssh -o ControlMaster=auto -o ControlPersist=60m -o ControlPath="$HOME/macmosh-sitting-1/cm-%C" mbp '~/.macmosh/macmosh-host install-agent'
exit status: 0
output:
what you saw:
  What did it print? Was there an error? -> preinted nothing, no error

-- Item 1, step 4: Read the status report
$ ssh -o ControlMaster=auto -o ControlPersist=60m -o ControlPath="$HOME/macmosh-sitting-1/cm-%C" mbp '~/.macmosh/macmosh-host status'
exit status: 0
output:
    macmosh-host	1	0.3.0
    os	27.3	arm64
    console	alex
    server	up
    signins	ok
    (seven lines about the disk, power, battery, addresses and sharing are left out)
    agent	installed
    tool	brew	/opt/homebrew/bin/brew	-
    tool	mosh-server	/opt/homebrew/bin/mosh-server	1.4.0
    tool	tmux	/opt/homebrew/bin/tmux	3.8
    end
what you saw:
  Do you see server up, signins ok and agent installed? Write what you see for each. -> yes to all 3

-- Item 1, step 5: Make the probe desk
$ ssh -o ControlMaster=auto -o ControlPersist=60m -o ControlPath="$HOME/macmosh-sitting-1/cm-%C" mbp '~/.macmosh/macmosh-host desk-new probe "$HOME"'
exit status: 0
output:
what you saw:
  Did it finish without an error message? -> yes

-- Item 1, step 6: Stop MacMosh's own desk server
$ ssh -o ControlMaster=auto -o ControlPersist=60m -o ControlPath="$HOME/macmosh-sitting-1/cm-%C" mbp 'PATH="$PATH:/opt/homebrew/bin:/usr/local/bin" tmux -L macmosh kill-server'
exit status: 0
output:
what you saw:
  Did it finish without an error message? -> yes

-- Item 1, step 7: Read the status report again
$ ssh -o ControlMaster=auto -o ControlPersist=60m -o ControlPath="$HOME/macmosh-sitting-1/cm-%C" mbp '~/.macmosh/macmosh-host status'
exit status: 0
output:
    macmosh-host	1	0.3.0
    os	27.3	arm64
    console	alex
    server	down
    signins	unknown
    (seven lines about the disk, power, battery, addresses and sharing are left out)
    agent	installed
    tool	brew	/opt/homebrew/bin/brew	-
    tool	mosh-server	/opt/homebrew/bin/mosh-server	1.4.0
    tool	tmux	/opt/homebrew/bin/tmux	3.8
    def	probe	0	0	/Users/alex
    end
what you saw:
  Does it say server down? -> yes

-- Item 1, step 8: Attach to the probe desk
$ ssh -t -o ControlMaster=auto -o ControlPersist=60m -o ControlPath="$HOME/macmosh-sitting-1/cm-%C" mbp '~/.macmosh/macmosh-host attach probe'
exit status: 0
(interactive step: its output was not recorded)
what you saw:
  Did the desk open? What did gh auth status say? (If attach printed an error, copy it.) -> yes opened, oops i didn't run gh auth :) and i exited the desk instead of detaching

-- Item 1, step 9: Read the status report a third time
$ ssh -o ControlMaster=auto -o ControlPersist=60m -o ControlPath="$HOME/macmosh-sitting-1/cm-%C" mbp '~/.macmosh/macmosh-host status'
exit status: 0
output:
    macmosh-host	1	0.3.0
    os	27.3	arm64
    console	alex
    server	up
    signins	ok
    (seven lines about the disk, power, battery, addresses and sharing are left out)
    agent	installed
    tool	brew	/opt/homebrew/bin/brew	-
    tool	mosh-server	/opt/homebrew/bin/mosh-server	1.4.0
    tool	tmux	/opt/homebrew/bin/tmux	3.8
    def	probe	0	0	/Users/alex
    end
what you saw:
  Do you see server up and signins ok? -> yes
Verdict: pass

==============================================================
ITEM 2: Opening a tab from a script, in iTerm2 and in Terminal

-- Item 2, step 1: Write the stand-in script
$ cat > "/Users/alex/macmosh-sitting-1/fake-macmosh" <<'FAKE'
#!/bin/sh
echo "hello from macmosh: $*"
printf '\033]1;%s\007' "$3"
echo "Press Enter to close this tab."
read dummy
FAKE
chmod 755 "/Users/alex/macmosh-sitting-1/fake-macmosh"
exit status: 0
output:
what you saw:
  Did it finish without an error message? -> yes

-- Item 2, step 2: iTerm2: create tab with default profile command
$ osascript - '/Users/alex/macmosh-sitting-1/fake-macmosh connect mbp website' <<'APPLESCRIPT'
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
exit status: 0
output:
    tab 11 of window id 2691
what you saw:
  Did a tab or a new window open? Which? -> yes new tab
  Did it show: hello from macmosh: connect mbp website -> yes
  Is the tab's title: website -> yes
  Write down the exact words of any macOS permission prompt, including the button names. -> no prompts came up

-- Item 2, step 3: Terminal: do script
$ osascript - '/Users/alex/macmosh-sitting-1/fake-macmosh connect mbp website' <<'APPLESCRIPT'
on run argv
    tell application "Terminal"
        activate
        do script (item 1 of argv)
    end tell
end run
APPLESCRIPT
exit status: 0
output:
    tab 1 of window id 11063
what you saw:
  Did a tab or a new window open? Which? -> new window
  Did it show: hello from macmosh: connect mbp website -> yes
  Is the tab's title: website -> ugh didn't really check
  Write down the exact words of any macOS permission prompt, including the button names. -> “iTerm.app” wants access to control “Terminal.app”. Allowing control will provide access to documents and data in “Terminal.app”, and to perform actions within that app.

-- Item 2, step 4: Terminal: do script in new tab
$ osascript - '/Users/alex/macmosh-sitting-1/fake-macmosh connect mbp website' <<'APPLESCRIPT'
on run argv
    tell application "Terminal"
        activate
        do script (item 1 of argv) in new tab
    end tell
end run
APPLESCRIPT
exit status: 1
output:
    103:106: syntax error: Expected end of line, etc. but found class name. (-2741)
what you saw:
  Did a tab or a new window open? Which? -> no we got a syntax error?
  Did it show: hello from macmosh: connect mbp website -> no
  Is the tab's title: website -> no
  Write down the exact words of any macOS permission prompt, including the button names. -> na

-- Item 2, step 5: A .command file opened with iTerm2
$ printf '#!/bin/sh\n/Users/alex/macmosh-sitting-1/fake-macmosh connect mbp website\n' > "$HOME/macmosh-sitting-1/hello.command" && chmod +x "$HOME/macmosh-sitting-1/hello.command" && open -a iTerm "$HOME/macmosh-sitting-1/hello.command"
exit status: 0
output:
what you saw:
  Did a tab or a new window open? Which? -> yes tab
  Did it show: hello from macmosh: connect mbp website -> yes
  Is the tab's title: website -> yes
  Write down the exact words of any macOS permission prompt, including the button names. -> none

-- Item 2, step 6: The same .command file opened with Terminal
$ open -a Terminal "$HOME/macmosh-sitting-1/hello.command"
exit status: 0
output:
what you saw:
  Did a tab or a new window open? Which? -> window
  Did it show: hello from macmosh: connect mbp website -> yes
  Is the tab's title: website -> terminal didn't really show a name.
  Write down the exact words of any macOS permission prompt, including the button names. -> none
Verdict: pass

==============================================================
ITEM 3: mosh with a pinned host key and a one-week timeout

-- Item 3, step 1: Pin the workhorse's host key
$ mkdir -p "/Users/alex/Library/Application Support/MacMosh/sitting" && ssh-keyscan -t ed25519 -p 22 workhorse 2>/dev/null | awk 'NF >= 3 && $1 !~ /^#/ { $1 = "macmosh-sitting"; print }' > "/Users/alex/Library/Application Support/MacMosh/sitting/known_hosts" && test -s "/Users/alex/Library/Application Support/MacMosh/sitting/known_hosts" && cat "/Users/alex/Library/Application Support/MacMosh/sitting/known_hosts" && ssh-keygen -lf "/Users/alex/Library/Application Support/MacMosh/sitting/known_hosts"
exit status: 0
output:
    macmosh-sitting ssh-ed25519 <key>
    256 SHA256:<fingerprint> macmosh-sitting (ED25519)
what you saw:
  Did it print a key and a fingerprint? -> yes

-- Item 3, step 2: Open the probe desk with mosh
$ mosh --ssh="ssh -o HostKeyAlias=macmosh-sitting -o 'UserKnownHostsFile=\"/Users/alex/Library/Application Support/MacMosh/sitting/known_hosts\"' -o StrictHostKeyChecking=yes -o ControlPath=none" --server='MOSH_SERVER_NETWORK_TMOUT=604800 PATH="$PATH:/opt/homebrew/bin:/usr/local/bin" mosh-server' mbp -- /bin/sh -c 'exec "$HOME/.macmosh/macmosh-host" attach "$1"' macmosh-host probe
exit status: 0
(interactive step: its output was not recorded)
what you saw:
  Did the desk open? Was there a host-key error? Did the ps line show MOSH_SERVER_NETWORK_TMOUT=604800? -> yes opened, no errors i didn't run PS oops

-- Item 3, step 3: Read back what the ps line found
$ ssh -o ControlMaster=auto -o ControlPersist=60m -o ControlPath="$HOME/macmosh-sitting-1/cm-%C" mbp 'cat ~/.macmosh/sitting-3-ps.txt'
exit status: 1
output:
    cat: /Users/alex/.macmosh/sitting-3-ps.txt: No such file or directory
what you saw:
  Does it say MOSH_SERVER_NETWORK_TMOUT=604800? -> uhm

-- Item 3, step 4: Try ssh-copy-id as a dry run
$ ssh-keygen -q -t ed25519 -N '' -f "$HOME/macmosh-sitting-1/test_key" < /dev/null; ssh-copy-id -n -i "$HOME/macmosh-sitting-1/test_key.pub" -o HostKeyAlias=macmosh-sitting -o 'UserKnownHostsFile="/Users/alex/Library/Application Support/MacMosh/sitting/known_hosts"' -o StrictHostKeyChecking=yes -o ControlPath=none mbp
exit status: 0
output:
    /usr/bin/ssh-copy-id: INFO: Source of key(s) to be installed: "/Users/alex/macmosh-sitting-1/test_key.pub"
    /usr/bin/ssh-copy-id: INFO: attempting to log in with the new key(s), to filter out any that are already installed
    /usr/bin/ssh-copy-id: INFO: 1 key(s) remain to be installed -- if you are prompted now it is to install the new keys
    =-=-=-=-=-=-=-=
    Would have added the following key(s):

    ssh-ed25519 <key> alex@daily-mac
    =-=-=-=-=-=-=-=
what you saw:
  Did it print the key it would install? Was there a host-key error? -> yes printed
Verdict: pass

==============================================================
ITEM 4: Tabs mode that reconnects by itself

-- Item 4, step 1: Attach in Tabs mode, then drop Wi-Fi
$ while true; do
    ssh -t -o ControlPath=none -o ServerAliveInterval=5 -o ServerAliveCountMax=2 mbp '~/.macmosh/macmosh-host attach --cc probe'
    rc=$?
    [ "$rc" -eq 255 ] || break
    echo 'Connection lost. Trying again in 3 seconds...'
    sleep 3
done
exit "$rc"
exit status: 0
(interactive step: its output was not recorded)
what you saw:
  Did the loop print Connection lost? Did the tabs come back by themselves? Did ssh ask for a password? -> i didn't see it preint anything but the tab did auto reappear
Verdict: pass

==============================================================
CLEAN UP

-- Clean up, step 1: Remove the probe desk
$ ssh -o ControlMaster=auto -o ControlPersist=60m -o ControlPath="$HOME/macmosh-sitting-1/cm-%C" mbp '~/.macmosh/macmosh-host desk-remove probe --kill; rc=$?; rm -f ~/.macmosh/sitting-3-ps.txt; exit $rc'
exit status: 0
output:
what you saw:
  Did it finish without an error message? -> yes

-- Clean up, step 2: Close the shared ssh connection
$ ssh -o ControlPath="$HOME/macmosh-sitting-1/cm-%C" -O exit mbp
exit status: 0
output:
    Exit request sent.
what you saw:
  Did it finish without an error message? -> yes
````

</details>
