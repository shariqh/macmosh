# Sitting 2: results

**In progress.** Part 1 (the lid) ran on 2026-11-22 and is written up below. Part 2 (the restart) has not run yet when this was saved; this file is pushed now because the restart ends the build agent's session.

Shariq asked the build agent to do everything that needs no password and no hands. So the agent started the recorder and made the desk over ssh, and watched the workhorse's lid from the workhorse itself. Shariq typed one `sudo` command and closed and opened the lid.

Every user name, host name, address and key in this file is a placeholder: `alex`, `workhorse`, `daily-mac`, `192.168.1.20` and `SHA256:<fingerprint>`. Times are Pacific Time.

## Part 1: the lid

**What was run.**

| Time | Who | What |
|---|---|---|
| 10:00 | agent, over ssh to the daily Mac | `record.sh` started; `macmosh desk new workhorse sitting-2 --folder '~' --reopen` |
| 10:02:38 | Shariq, in the desk `sitting-2` opened from the menu | `sudo pmset -a disablesleep 1` |
| 10:05:00 | Shariq | closed the workhorse's lid (on power, no display plugged in) |
| 10:20:04 | | the lid had been closed for 15 minutes |

**What was seen.**

- **The workhorse did not sleep.** `pmset -g log` has no `Sleep`, `Wake` or `DarkWake` entry between 10:00 and 10:20. A loop on the workhorse that looked at the lid every 10 seconds never saw more than 60 seconds pass between two looks.
- **The daily Mac reached it the whole time.** Between 10:05 and 10:20 the recorder made 40 rounds. In every one, `macmosh status` exited 0 with the state `ready`, and ssh to the main, the home and the `.local` address each exited 0 with the pinned key.
- **The workhorse's own log has no gap.** `host.log` has 109 status lines between 10:05 and 10:20 and no two are more than 45 seconds apart.
- **The agent's own session on the workhorse kept answering** messages sent from the daily Mac at 10:05 and 10:06, with the lid closed.
- **Where the setting shows.** After the command, `pmset -g` has a new line, `SleepDisabled` followed by two tabs and `1`. Before it, `pmset -g` had no such line. `pmset -g custom` has no line for it, before or after.
- **MacMosh's report does not see it.** The workhorse's status report still says `disablesleep=-` with the setting on, because it reads `pmset -g custom`.
- `ioreg` showed `AppleClamshellState = Yes` from 10:05:00. `AppleClamshellCausesSleep` stayed `Yes` before and after the command and with the lid closed, so it says nothing about the setting.
- What held the workhorse awake at 10:05, from `pmset -g assertions`: only idle-sleep holds (`PreventUserIdleSystemSleep` from `caffeinate` and `powerd`); `PreventSystemSleep` was 0. Apple's `IOPMLib.h` says of that kind of hold: "The system may still sleep for lid close, Apple menu, low battery, or other sleep reasons."
- **Screen and heat when the lid was opened:** not written down yet.

**Not shown by this run.** Whether the same lid close, with the setting off and a remote session connected, puts the workhorse to sleep. Its power log has two earlier `Clamshell Sleep` entries (16 and 17 November), both on battery. A one-minute control with the setting off is planned for the end of the sitting.

**Verdict so far: pass.** The workhorse stayed awake and reachable for 15 minutes with the lid closed.

**What the build does with it.**

- The lid-closed switch (Task 25) can be built on `disablesleep`.
- The status report has to read `SleepDisabled` from `pmset -g`, not from `pmset -g custom`.

## Found while starting

`scripts/sitting-2/start.sh` makes the desk but would not have opened it. `macmosh desk new` with a name and a folder creates the desk and returns; it opens the desk only when it had to ask for one of them. The runbook's step 1 says the tab becomes a prompt on the workhorse. Fix the helper and the runbook with this file's pull request.

## Part 2: the restart

Not run yet.
