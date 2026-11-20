# First run: notes

Kept by the build agent during Task 20: what Shariq says gets in the way, and what the agent saw in the logs. Names, addresses and keys are placeholders, as everywhere in this repo.

## Before the first run

- The app was built and signed on the workhorse on 2026-11-20, from `main` after Task 27: version 0.1.0, hardened runtime, not notarized. It has not been started on either Mac.
- The daily Mac runs macOS 27.2.1 and has iTerm2 and mosh. It has no MacMosh app and no MacMosh key yet.
- The workhorse already has script version 0.3.0 and the login agent, from sitting 1. So the first run does not exercise the script install (`HostInstaller`); the menu should go straight to ready after pairing.

## To look at during the first run

- The exact words of the two macOS prompts: controlling the terminal, and the local network.
- Whether the menu checks again each time it is opened. The app's log writes `menu opened` once when the app starts (see below). If the line also appears just before the first `menu action` line, it runs on every open; if not, only the 30-second schedule and `Check now` keep the menu fresh (issue #79).
- Whether indented menu lines keep their leading spaces.
- Whether Terminal, if he tries it, shows a desk's name anywhere.

## What Shariq said

Nothing yet.

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
