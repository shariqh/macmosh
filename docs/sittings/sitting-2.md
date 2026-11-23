# Sitting 2: the lid, then one restart

This sitting answers two questions that no document settles (design section 9, questions 6 and 7):

- Does the MacBook Pro stay reachable with its lid closed, once one hidden power setting is on?
- After a restart, can you get it back from the Air with MacMosh alone: unlock the disk, log in, and find your desk again?

You do the things that need hands, eyes or a password. A recorder on the Air writes down everything else, so you take no notes. The build agent reads the record afterwards.

It takes about 45 minutes. Most of it is waiting.

**This sitting ran on 2026-11-22 and both parts passed.** The results are in `sitting-2-results.md`.

## Before you start

Check these five things. If one is not true, wait until it is.

1. **Nothing you still need is running on the MacBook Pro.** The restart stops everything on it: your agents, every terminal session, MacMosh's desks, and the build agent. Let your agents finish or stop them first. The lid test can also pause the Mac for up to 15 minutes if the setting turns out not to work.
2. **Both Macs are at home, on the home Wi-Fi.** The unlock after the restart only works on the home network.
3. **The MacBook Pro is on power, with no display plugged in.**
4. **MacMosh's menu on the Air says `Ready`** for the MacBook Pro.
5. **You know the MacBook Pro's login password.** You type it four or five times. MacMosh never sees it: you type into `sudo`, into ssh, or into Screen Sharing.

## What you will use

| Thing | What it is | Ours or theirs |
|---|---|---|
| `start.sh` | Starts the recorder and opens a desk called `sitting-2` on the MacBook Pro | Our helper, in `~/macmosh-sitting-2` on the Air |
| `record.sh` | The recorder. Every 20 seconds it notes what MacMosh says and what ssh sees. It only reads | Our helper |
| `restart.sh` | Runs one MacMosh command: `macmosh restart <workhorse> --full` | Our helper |
| `pmset` | macOS's own command for power settings. `disablesleep` is a setting it accepts and Apple doesn't document | macOS |
| Screen Sharing | Apple's app for seeing another Mac's screen. MacMosh opens it for you | macOS |
| The MacMosh menu | The icon in the Air's menu bar | MacMosh |

The helpers are copies of the files in `scripts/sitting-2/` of this repository. Read them first if you like; each is short.

## Part 1: the lid (about 20 minutes)

1. **On the Air, in iTerm, run:**

   ```
   bash ~/macmosh-sitting-2/start.sh
   ```

   You should see three lines that say it is recording, and then a prompt on the MacBook Pro. That tab is the desk `sitting-2`. Keep it open.

2. **In that tab, turn the setting on:**

   ```
   sudo pmset -a disablesleep 1
   ```

   It asks for the MacBook Pro's password and prints nothing else.

3. **Close the MacBook Pro's lid. Leave it closed for 15 minutes.**

   Now and then, press Enter in the desk tab. The prompt should answer at once, as if the lid were open.

4. **Open the lid.** Two things only you can tell, so look and feel:
   - Was the screen lit as you opened it, or dark?
   - Is the Mac warmer than usual?

## Part 2: the restart (about 20 minutes)

The recorder stops two hours after step 1. If more time than that has passed, start it again before step 5: `bash ~/macmosh-sitting-2/record.sh`

5. **On the Air, open a new iTerm tab and run:**

   ```
   bash ~/macmosh-sitting-2/restart.sh
   ```

   MacMosh names the desks that will close and says: `After this restart the disk will be locked. You unlock it with Unlock disk…` Type `restart` and press Enter. Then ssh asks for the MacBook Pro's password. The MacBook Pro restarts, and every tab that was connected to it stops answering. Close those tabs.

6. **Watch the MacMosh menu on the Air.** Open it and click `Check now` every half minute or so. It goes from `Can't reach it` to `Locked after a restart`, usually within two minutes.

   Click `Unlock disk…  (you type the Mac's password)`. A tab opens and says you are about to type the password into ssh. Type it. The connection closes by itself, and the tab then says `Waiting for login`.

7. **Click `Log in…  (opens Screen Sharing)` in the menu.** Screen Sharing shows the MacBook Pro's login window. Log in as you would at the Mac.

8. **Wait for `Ready`.** It takes a minute or two after you log in, and `Check now` hurries it. The desk `sitting-2` should be in the menu again. Click it: it opens in a tab.

9. **In that tab, turn the setting off again:**

   ```
   sudo pmset -a disablesleep 0
   ```

   Leave it on if you mean to keep using the MacBook Pro with its lid closed. While it is on, the Mac also stays awake with the lid closed on battery, in a bag included.

10. **Start the build agent again** on the MacBook Pro, in `~/Development/macmosh`, and tell it: sitting 2 is done. Tell it the two things from step 4 as well. It reads the record from the Air by itself.

## What you should have seen

| When | The menu says |
|---|---|
| Before the restart | `Ready` |
| Just after `restart.sh` | `Can't reach it` |
| The Mac is at its disk-unlock screen | `Locked after a restart` |
| After `Unlock disk…` | `Waiting for login` |
| After you log in | `Ready`, with `sitting-2` listed |

## If something's off

- **`start.sh` says MacMosh has no saved workhorse, or no desk opens.** Stop here and tell the build agent what the tab says. Nothing has changed.
- **With the lid closed, the desk tab stops answering.** That is a result: the setting did not keep the Mac awake. Open the lid after the 15 minutes anyway. The tab picks up by itself. Go on to Part 2.
- **The menu still says `Can't reach it` five minutes after the restart.** The Mac isn't answering before the unlock. Go to the MacBook Pro and type the password at its own screen. That is a result too. Carry on from step 8.
- **The menu says `Can't verify it`.** Stop. Don't type a password into any tab. Unlock and log in at the MacBook Pro's own keyboard, and tell the build agent.
- **`Unlock disk…` doesn't take the password.** Try once more, in case of a typo. If it still fails, unlock at the MacBook Pro's own keyboard and carry on from step 7.
- **Screen Sharing doesn't connect, or shows nothing.** Log in at the MacBook Pro's own keyboard and carry on from step 8.
- **`Ready` doesn't come back five minutes after you logged in.** Click `Run the checklist…` and tell the build agent what it says.
- **You want to stop part-way.** You can, after any step: both Macs stay usable. If you ran step 2, run step 9's command before you leave it.

## What the recorder writes down

Every 20 seconds, for two hours at most, into `~/macmosh-sitting-2/record.log` on the Air:

- what `macmosh status` says about the MacBook Pro;
- for each of its three addresses (the Tailscale name, the home address, the `.local` name): whether ssh gets in with MacMosh's key, which sign-in methods the Mac offers there, and whether the host key is the one MacMosh pinned;
- when ssh gets in: the MacBook Pro's own status report, and what `pmset` prints about the lid setting.

It types no password and changes nothing on either Mac. While it runs it keeps the Air from going to sleep by itself; that ends when it does.

The record holds real names, addresses and key fingerprints, so it stays on the Air. The results file in this repository uses placeholders.

## Afterwards

- **The lid setting.** Step 9 turns it off, unless you chose to leave it on. The build agent reads `pmset -g` on the MacBook Pro afterwards and tells you which it is.
- **The recorder** ends by itself after two hours. To end it sooner: `bash ~/macmosh-sitting-2/record.sh --stop`
- **The desk `sitting-2`** stays until you remove it. On the Air:

  ```
  /Applications/MacMosh.app/Contents/Helpers/macmosh desk remove <the workhorse's name in the menu> sitting-2
  ```

- **Keep `~/macmosh-sitting-2`** on the Air until the build agent says it has read the record.

## What the results answer

The build agent writes `docs/sittings/sitting-2-results.md` from the record:

- **Question 6.** What each check sees at the disk-unlock screen, at the login window and after login; whether the host key is the same at all three; whether the `.local` name answers before the unlock. Those are the facts behind `Unlock disk…` and `Log in…`.
- **Question 7.** Whether the Mac stayed reachable for 15 minutes with the lid closed, where the setting shows up in `pmset`, and whether it was still on after the restart. That decides whether the lid-closed switch is built or left out.
