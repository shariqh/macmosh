# First run: notes

Kept by the build agent during Task 20: what Shariq says gets in the way, and what the agent saw in the logs. Names, addresses and keys are placeholders, as everywhere in this repo.

## Before the first run

- The app was built and signed on the workhorse on 2026-11-20, from `main` after Task 27: version 0.1.0, hardened runtime, not notarized. It has not been started on either Mac.
- The daily Mac runs macOS 27.2.1 and has iTerm2 and mosh. It has no MacMosh app and no MacMosh key yet.
- The workhorse already has script version 0.3.0 and the login agent, from sitting 1. So the first run does not exercise the script install (`HostInstaller`); the menu should go straight to ready after pairing.

## To look at during the first run

- The exact words of the two macOS prompts: controlling the terminal, and the local network. Neither was recorded: the first was allowed without a screenshot, and the second never came.
- Whether the menu checks again each time it is opened. Answered at the first click: it didn't (see 18:46 below, and issue #79).
- Whether indented menu lines keep their leading spaces.
- Whether Terminal, if he tries it, shows a desk's name anywhere.

## What Shariq said

- **19:05,** on the board row: "done and connected". He had paired the daily Mac with the workhorse. The logs show the rest (below), so he was not asked to describe it.
- **19:28,** on the board row, after two questions no log could answer: "i think i was just messing around and clicked it twice. no local device notifs were sent. closed and opened the lid and it all is connected".

## What the agent saw

- **13:06.** Shariq opened the app on the daily Mac. It opened and stayed open. It is signed, and a file copied over ssh carries no quarantine flag, so Gatekeeper's notarization check was not expected to run. Whether macOS showed a dialog first isn't known yet.
- **14:30.** Not paired: no MacMosh key, no saved workhorse, nothing new in the workhorse's `host.log`. The daily Mac's system log shows no `osascript` run since the app opened, so `Add a Mac…` had not opened a tab. As a control, the same log has 134 lines from `osascript` during sitting 1.
- **The app wrote nothing of its own.** Whether the menu had left `Checking…`, and whether it had been opened or clicked, could not be read from outside. The app now keeps a log (`MenuLog`), and CI starts the app and waits for the line that means the menu loaded. To read it on the daily Mac:

  ```
  /usr/bin/log show --last 1h --predicate 'subsystem == "io.github.shariqh.macmosh"'
  ```

  `log` on its own is a zsh builtin, so the full path matters.
- **14:53.** The agent swapped in the build that keeps a log and reopened it. The Mac had been idle for 15 minutes, MacMosh had saved nothing, and no `macmosh` command was running. The old copy is in the Trash. The daily Mac's log then read:

  ```
  14:53:38.469  MacMosh 0.1.0 started
  14:53:38.587  menu refreshed: symbol=plus.circle workhorses=0 lines=2
  14:53:38.590  menu opened
  ```

  So on the daily Mac the menu goes from `Checking…` to `No workhorses yet` 0.12 seconds after the app starts. It was not stuck: `Add a Mac…` had not been clicked yet.
- **`menu opened` is written when the app starts,** with nobody at the keyboard. SwiftUI builds the menu's contents at launch and runs `onAppear` then. Whether it runs again on each open is still to be seen (issue #79).
- **18:46 to 18:48, the pairing.** The daily Mac's log:

  ```
  18:46:47.423  menu action: tab pair
  18:46:49.653  menu action done: tab pair: tab opened
  18:47:14.792  menu action: tab pair
  18:47:15.038  menu action done: tab pair: tab opened
  18:47:33.093  menu refreshed: symbol=wrench.and.screwdriver workhorses=1 lines=7
  18:48:05.682  menu refreshed: symbol=checkmark.circle workhorses=1 lines=10
  ```

  - **The prompt about controlling the terminal came once and was allowed.** macOS's own log (`com.apple.TCC`) shows iTerm2 asking at 18:46:47.57 whether MacMosh may control it, and the answer, yes, 1.95 seconds later. At the second click the answer came in 0.02 seconds: macOS remembered. No screenshot was taken, so the prompt's wording is still not recorded.
  - **`Add a Mac…` was clicked twice,** 27 seconds apart, and each click opened a tab. The second tab did the pairing. What happened in the first one is not in any log.
  - **For one check the menu showed the workhorse as not set up** (the wrench): it was saved, and its key was still being installed. The next check, 32 seconds later, made it Ready.
  - **On the workhorse:** one MacMosh key line in `authorized_keys`, and `host.log` has `status ok` at 18:48:05 and about every 32 seconds after that.
  - **`macmosh status` on the daily Mac:** Ready, no desks yet, sign-ins working, awake on power.
- **No `menu opened` line at either click.** The menu was opened at 18:46:47 and again at 18:47:14, and the log has the line only from when the app started. So macOS runs the menu content's `onAppear` once, at launch, and the check on open never ran (issue #79). The app now listens for AppKit's menu-tracking notification, and CI clicks the icon on macOS 15 and 26 to prove the line follows. The daily Mac gets that build at the next swap.
- **No sign of a local network prompt.** The system log has no local-network line that names MacMosh, though the pairing command looked names up at 18:47:24. A log can't prove a prompt never showed.
- **Nothing was clicked after the pairing:** no `New desk…`, no checklist. The workhorse has no desk. The board row now asks only for `New desk…` and the lid.
- **19:08. Nothing in the menu sets the projects folder.** `macmosh folders` answered "No projects folder is set", so `New desk…` would have asked for a path with no list to pick from. The agent set it on the daily Mac (`macmosh set workhorse projects-folder '~/Development'`), and `macmosh folders` then listed the folders. The design has you choose this folder once per workhorse (7.3); until the Settings window exists (Task 29) nothing in the app does. One for the review (Task 21).
- **19:17 to 19:22. After the daily Mac woke, the menu was wrong for half a minute.** The Mac went to idle sleep at 19:17:26 and was woken at 19:21:28 (`pmset -g log`). The first check after that said the workhorse couldn't be reached, and the next one said Ready:

  ```
  19:21:43.208  menu refreshed: symbol=wifi.slash workhorses=1 lines=6
  19:22:15.835  menu refreshed: symbol=checkmark.circle workhorses=1 lines=10
  ```

  The workhorse was fine; the daily Mac's network was not back yet (issue #83).
- **19:22. `New desk…` made a desk and opened it.**

  ```
  19:22:19.642  menu action: tab desk
  19:22:19.920  menu action done: tab desk: tab opened
  19:23:20.926  menu refreshed: symbol=checkmark.circle workhorses=1 lines=12
  ```

  The workhorse's `host.log` has `folders ok` at 19:22:30, `desk-new created test` at 19:22:51 and `attach test` at 19:22:53. The folder list came from the projects folder set at 19:08.
- **19:23:22 to 19:24:23. The lid was closed for 61 seconds, and the desk's connection lived through it.** `pmset -g log` on the daily Mac has the "Clamshell Sleep" and the wake. Afterwards the same two mosh processes were still running: the client started at 19:22:52 on the daily Mac and the server started at 19:22:53 on the workhorse. The workhorse logged no new `attach` for that tab, and its status report says the desk has one tab attached. Shariq: "it all is connected".
- **19:24:40. He opened the same desk again from the menu** (`menu action: tab connect`, `tab opened`; `attach test` at 19:24:42 on the workhorse). That second tab was closed again within a minute.
- **No local network prompt, and the home address answers.** Since the pairing, every check makes one more ssh call to the workhorse's home address. Shariq saw no prompt, the system log has no denial that names MacMosh, and `macmosh status --json` on the daily Mac says `homeReachable: true`. That last check ran over ssh and not from the app, and the app's log doesn't say what the app itself got.
- **A false alarm from the agent's own check.** A `ps … | grep` for mosh processes matched the shell that ran it, because the command's own text held the words it searched for. For a minute it looked as if a new mosh connection started every 30 seconds. Listing the processes by pid with their parents showed one connection.

## What the first run settled

| Question | Answer |
|---|---|
| Does the app open on the daily Mac, signed and not notarized? | Yes. |
| Does `Add a Mac…` open a tab and pair? | Yes, after one prompt about controlling iTerm2. |
| Does the menu go straight to Ready after pairing? | Yes, at the second check. For one check it showed the workhorse as not set up. |
| Does `New desk…` make and open a desk over mosh? | Yes. |
| Does the desk pick up after a closed lid? | Yes, after 61 seconds closed. |
| Does macOS ask about the local network? | No. |
| Does the menu check again when it is opened? | It didn't. Fixed (issue #79). |

## Still open after the first run

- The prompt's wording (controlling the terminal).
- Leading spaces in indented menu lines, and Terminal as the terminal app: nobody looked.
- Nothing in the menu sets the projects folder (for Task 21 and Task 29).
- Nothing in the menu removes a desk. The first run's desk can only be removed with `macmosh desk remove workhorse test` (for Task 21). The agent first told Shariq the menu could do it, and corrected that on the board.
- The daily Mac still runs the build from 14:53. The build with the menu-open fix and the locale fix is unpacked beside it, and swaps in when the Mac is idle with no MacMosh tab open.
- The menu is wrong for a moment after the daily Mac wakes (issue #83). The app now looks a second time, five seconds later, before it says "Can't reach it". Whether that is long enough after a wake shows the next time the daily Mac wakes: its log should have no `wifi.slash` line then.
- The script install (`HostInstaller`) has still not run for real: the workhorse had the script from sitting 1.
