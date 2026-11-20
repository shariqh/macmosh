# First run: MacMosh on your Macs

This is the first time the MacMosh app runs on real Macs. It takes about ten minutes on the MacBook Air.

The build agent copies the signed app into the Applications folder on the Air and checks it before you start. While you go through the steps, it reads the logs on both Macs, so there is nothing to write down.

Two things are on the board row for you to copy:

- **The MacBook Pro's user name.** The Air's is different, and the app offers the Air's by default.
- **The MacBook Pro's fingerprint.** This is a short code that identifies that Mac, so you know you are connecting to the right one.

## Steps

1. **Open MacMosh** from the Applications folder.
   You should see a new icon in the menu bar. Click it: the menu says `No workhorses yet`.

2. **Click `Add a Mac…`.**
   macOS asks whether MacMosh may control iTerm. Take a screenshot (Shift-Command-3), then click **Allow**. A terminal tab opens and lists the Macs on your Tailscale network.
   - Pick the MacBook Pro's number.
   - At `User name on the workhorse`, type the user name from the board row.
   - The tab shows a fingerprint. Compare it with the one on the board row, and type `yes` only if they match.
   - If ssh asks for a password, it is the MacBook Pro's login password. You are typing into ssh, and MacMosh can't see it.

   You should see `Paired.` in the tab, and the MacBook Pro in the menu.

3. **Click `Finish setting up…`** if the menu shows it under the MacBook Pro. If it doesn't, click `Run the checklist…`.
   A tab runs the setup checklist. Every line should end up `✓` (fine) or `•` (for your information).

4. **If macOS asks whether MacMosh may find devices on your local network,** take a screenshot, then click **Allow**.
   This can come at any point after step 2. The menu should still show the MacBook Pro as ready afterwards.

5. **Click `New desk…`.** A desk is one named workspace on the MacBook Pro; it keeps running when its tab closes.
   The tab asks for a name and a folder on the MacBook Pro, then opens the new desk. Close the Air's lid for a minute and open it again: the tab picks up by itself.

6. **Don't click `Restart…` yet.** It restarts the MacBook Pro, and that test waits until you say.

After that, use it for a few days in place of `rmosh` and the cheat sheet. When something gets in the way, tell the agent in chat or on the board row, in your own words.

## If something's off

| What you see | What to do |
|---|---|
| macOS says MacMosh can't be opened | Don't override it. Tell the agent what it said. |
| No terminal tab opens after `Add a Mac…` | The first line of the menu says why. Tell the agent what it says. |
| The fingerprints don't match | Type anything but `yes`. Nothing is saved. Tell the agent. |
| A checklist line starts with `✗` | The line under it says how to fix it. If that isn't clear, tell the agent. |
| The menu shows a state other than ready | The line under the state says what to do next. |

## To undo all of it

`macmosh` below is the command inside the app: `/Applications/MacMosh.app/Contents/Helpers/macmosh`.

1. `macmosh list` shows the id MacMosh gave the MacBook Pro.
2. `macmosh remove <id>` takes MacMosh's key, script and login agent off the MacBook Pro. It lists what it takes off and asks before it does anything. Desks that are open keep running until you close them, and your own tmux sessions are not touched.
3. Quit MacMosh from its menu, and move it from Applications to the Trash.
