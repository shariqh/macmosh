# Sitting 1: five short tests

This sitting checks whether five things MacMosh depends on work on your two Macs. A helper script runs each one, asks what you saw, and writes it all down.

Nothing here restarts the MacBook Pro, logs it out, or changes a power, sleep, or security setting. Your own tmux sessions on it are not touched.

## What you need

- The MacBook Air (the "Air").
- The MacBook Pro's login password. ssh asks for it, not the helper. The helper never sees it.
- About 45 minutes.
- iTerm2 on the Air, for item 4.

## Two things to do first

On the Air:

1. Get the repository: `git clone https://github.com/shariqh/macmosh`
2. Install SwiftBar, needed for item 5: `brew install --cask swiftbar`

SwiftBar is a small app that puts the output of a script in the menu bar. It is how the first version of MacMosh will show the MacBook Pro's state.

Open SwiftBar once from Applications. If it asks for a plugin folder, make a folder (say `~/swiftbar-plugins`) and choose it.

## Start the helper

Open iTerm2 on the Air. Then run these. Put your login name and the MacBook Pro's name or address where the angle brackets are:

```
cd macmosh
scripts/sitting-1.sh --dry-run <you>@<workhorse>
scripts/sitting-1.sh <you>@<workhorse>
```

The first run is a dry run. It only prints what the helper would do, so you can read it. It runs nothing and makes no files. The second run is the real one.

The "workhorse" is the Mac that stays on and holds your work. Here that is the MacBook Pro.

At each step the helper shows a command and waits. Press Enter to run it, or type `s` and Enter to skip that step. After a step it asks what you saw. Type a short answer. At the end of each item it asks for a verdict: `p` for pass, `f` for fail, `s` to skip.

If a step fails, the helper carries on. A failure is a result. Write down what you saw and go on.

The helper keeps one ssh connection open, so ssh asks for the password once at the start. mosh and the item 4 loop make their own connections, so they ask again.

If ssh asks "Are you sure you want to continue connecting?", type `yes` only if you expect this Mac. If ssh warns that a host key has changed, stop and tell the build agent.

## Item 1: put the script and login agent on the MacBook Pro

**What it tests.** A "login agent" is a small job macOS starts each time you log in. MacMosh needs one on the MacBook Pro to start its own tmux server. tmux is the program that keeps your desks alive. Can the install happen over ssh, with nobody touching the MacBook Pro?

**What it does.** It copies the script over, installs the agent, creates a desk named `probe`, then stops MacMosh's own new tmux server and attaches again. Attaching should make the login agent start the server. The server it stops is MacMosh's own (`tmux -L macmosh`, which holds only the `probe` desk). Your tmux sessions run on a different server and are not touched.

**What to run.** The helper's item 1 steps. In step 8 you land inside the desk. Type `gh auth status`, look at what it says, then press Ctrl-b, let go, and press `d` to leave.

**What you should see.** The status report says `server up`, `signins ok` and `agent installed` after the install. It says `server down` after the server is stopped. After `attach` it says `server up` and `signins ok` again. `gh auth status` inside the desk shows you signed in.

**If it fails.** Write down what you saw and go on to the next item. **Don't log out of the MacBook Pro to fix it**, because that ends every running session there. A failed item 1 is something to bring to the build agent, not to repair yourself.

## Item 2: open a terminal tab from a script

**What it tests.** MacMosh will open terminal tabs for you. macOS asks permission when one app controls another. Which way of opening a tab works best in iTerm2 and in Terminal, and what do the prompts say?

**What to run.** The helper's item 2 steps. Each one opens a tab that prints `hello from macmosh` and waits for Enter. The first three use AppleScript (macOS's built-in way for one app to drive another). The last two open a small `.command` file, which is the fallback when permission is refused. Press Enter in each new tab, and close it.

**What you should see.** A tab opens and shows the text. macOS may ask something like "iTerm2 wants to control Terminal". **Copy the exact words** of each prompt, including the button names, into your answer. Note which form opened a tab in an existing window and which opened a new window.

**If it fails.** If you click Don't Allow, write down what happened and go on. Macs remember that answer, so the next steps may fail without asking again. That is useful to know, so write it down.

## Item 3: mosh with a pinned key and a one-week timeout

**What it tests.** mosh is a replacement for the ssh terminal connection that survives Wi-Fi drops and a closed lid. MacMosh will give it a file holding the workhorse's host key, so it knows it is talking to the right Mac. It will also tell the workhorse to wait a week before giving up on a lost connection. Does mosh accept both?

**What to run.** The helper's item 3 steps:

1. It saves the workhorse's host key under the name `macmosh-sitting`, in `~/Library/Application Support/MacMosh/sitting/`. The folder name has a space in it, on purpose.
2. It opens the `probe` desk with mosh. Inside, type the `ps` line the helper prints, then press Ctrl-b, let go, and press `d`. That line looks for the one-week setting in mosh's environment on the workhorse.
3. It reads that line back.
4. It makes a throwaway test key and runs `ssh-copy-id -n`, a dry run that prints the key it would install and installs nothing.

**What you should see.** The desk opens. The `ps` line shows `MOSH_SERVER_NETWORK_TMOUT=604800`. The dry run prints a key and no host-key error.

**If it fails.** If the Air says `mosh: command not found`, run `brew install mosh` and try the step again. Otherwise write down what you saw, the error text included, and go on.

## Item 4: tabs that come back by themselves

**What it tests.** iTerm2 can show each desk as its own tab ("Tabs mode"). When Wi-Fi drops, will a retry loop bring the tabs back without help?

**What to run.** The helper's item 4 step. Run it from iTerm2. Type the password when asked. When the tabs appear, turn Wi-Fi off for 20 seconds, then on again. Watch the tab where the helper is running.

**What you should see.** The loop prints "Connection lost. Trying again in 3 seconds..." and tries again. ssh asks for the password again, because no key is installed yet. Type it. The tabs come back.

To finish, press Esc in the first tab, or choose Shell > tmux > Detach. Ctrl-C ends the loop.

**If it fails.** Write down what you saw. Say whether the loop printed its message, whether the tabs came back, and whether anything was stuck. Go on.

## Item 5: what macOS asks about the home network

**What it tests.** Since macOS 15, an app needs permission to talk to other devices on your home network. SwiftBar will run MacMosh's checks, so it needs that permission. What does macOS ask, and does it work after you allow it?

**What to run.** The helper's item 5 steps. It reads the MacBook Pro's home address from its status report, puts a small test plugin in SwiftBar's folder, and tries ssh to that address every 10 seconds. SwiftBar must be open.

1. Wait up to 15 seconds. macOS should ask whether SwiftBar may find and connect to devices on your local network. **Don't click Allow yet.** Click SwiftBar's icon in the menu bar and read it. Copy the exact words of the prompt.
2. Click Allow. Wait 15 seconds and read the menu again.

**What you should see.** Before Allow, the menu says `No route to host`. After Allow, it doesn't. `ssh exit 0` or `Permission denied` both count as a pass: either one means the home network is reachable.

**If it fails.** If no prompt appears, say so. The permission may be set already. Write down what the menu said, and go on.

## Finish

The helper removes the `probe` desk and closes its ssh connection. It says that the script and the login agent stay installed on the workhorse, as agreed. They live in the MacBook Pro's `~/.macmosh` folder and `~/Library/LaunchAgents`, and only in your home folder. Neither one changes how your own sessions work.

## Send the results back

Your answers are in `~/macmosh-sitting-1/results.txt` on the Air. Tell the build agent when you are done and paste or attach that file. It has addresses and host names in it. The build agent replaces those with placeholders before anything is committed. Please don't commit it yourself.

Keep `~/macmosh-sitting-1` until the build agent confirms it has the file. Afterwards you can delete it, and the pinned-key folder `~/Library/Application Support/MacMosh/sitting` too.

## Undo the install

You don't need to. If you want the script and login agent gone, run this on the Air. No key was installed this sitting, so there is no key to remove.

```
ssh <you>@<workhorse> 'launchctl bootout gui/$(id -u)/io.github.shariqh.macmosh.host; rm ~/Library/LaunchAgents/io.github.shariqh.macmosh.host.plist; rm -r ~/.macmosh'
```

That unloads the login agent, deletes its file, and deletes the `~/.macmosh` folder. The tmux server and any open desk keep running until you close them or the Mac restarts.
