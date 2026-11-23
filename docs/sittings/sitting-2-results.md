# Sitting 2: results

Sitting 2 ran on 2026-11-22 and both parts passed.

- **The lid.** The workhorse stayed awake and reachable for 43 minutes with its lid closed.
- **The restart.** After a full restart, Shariq unlocked the disk and logged in from the MacMosh menu on the daily Mac. The menu said `Ready` 4 minutes and 21 seconds after the restart command, and the desk marked to come back was there again.

Shariq asked the build agent to do everything that needs no password and no hands. So the agent started the recorder and made the desk over ssh, and watched the workhorse's lid from the workhorse itself. Shariq typed one `sudo` command, closed and opened the lid, and did the restart, the unlock and the login.

Every user name, host name, address and key in this file is a placeholder: `alex`, `workhorse`, `daily-mac`, `192.168.1.20` and `SHA256:<fingerprint>`. Times are Pacific Time.

## Part 1: the lid

**What was run.**

| Time | Who | What |
|---|---|---|
| 10:00 | agent, over ssh to the daily Mac | `record.sh` started; `macmosh desk new workhorse sitting-2 --folder '~' --reopen` |
| 10:02:38 | Shariq, in the desk `sitting-2` opened from the menu | `sudo pmset -a disablesleep 1` |
| 10:05:00 | Shariq | closed the workhorse's lid (on power, no display plugged in) |
| 10:20:04 | | the lid had been closed for 15 minutes |
| 10:48:16 | Shariq | opened the lid, after 43 minutes closed (he had stepped away) |

**What was seen.**

- **The workhorse did not sleep.** `pmset -g log` has no `Sleep`, `Wake` or `DarkWake` entry between 10:00 and 10:49. A loop on the workhorse that looked at the lid every 10 seconds, until 10:20, never saw more than 60 seconds pass between two looks. The power log's first entry about the lid is `com.apple.powermanagement.lidopen` at 10:48:16.
- **The daily Mac reached it the whole time.** Between 10:05 and 10:20 the recorder made 40 rounds, and between 10:20 and 10:49 another 77 complete ones. In every one, `macmosh status` exited 0, and ssh to the main, the home and the `.local` address each exited 0. The key was the pinned one every time.
- **The workhorse's own log has no gap.** `host.log` has 317 status lines between 10:05 and 10:49 and no two are more than 45 seconds apart.
- **The agent's own session on the workhorse kept answering** messages sent from the daily Mac at 10:05 and 10:06, with the lid closed.
- **Where the setting shows.** After the command, `pmset -g` has a new line, `SleepDisabled` followed by two tabs and `1`. Before it, `pmset -g` had no such line. `pmset -g custom` has no line for it, before or after.
- **MacMosh's report does not see it.** The workhorse's status report still says `disablesleep=-` with the setting on, because it reads `pmset -g custom`.
- `ioreg` showed `AppleClamshellState = Yes` from 10:05:00. `AppleClamshellCausesSleep` stayed `Yes` before and after the command and with the lid closed, so it says nothing about the setting.
- What held the workhorse awake at 10:05, from `pmset -g assertions`: only idle-sleep holds (`PreventUserIdleSystemSleep` from `caffeinate` and `powerd`); `PreventSystemSleep` was 0. Apple's `IOPMLib.h` says of that kind of hold: "The system may still sleep for lid close, Apple menu, low battery, or other sleep reasons."
- **Screen and heat when the lid was opened,** in Shariq's words: "not much warmer no" and "screen was on ye". `pmset -g therm` at 10:49 said no thermal warning level, performance warning level or CPU power status had been recorded. Whether the screen was lit while the lid was closed is not known.
- **What Shariq wants next,** in his words: "we can keep a check on the temps as i think that will be my default mode for now".

**Not shown by this run.** Whether the same lid close, with the setting off and a remote session connected, puts the workhorse to sleep. Its power log has two earlier `Clamshell Sleep` entries (16 and 17 November), both on battery. The one-minute control with the setting off was not run: Shariq means to keep the lid closed from now on, and the setting was still on when the sitting ended.

**Verdict: pass.** The workhorse stayed awake and reachable for 43 minutes with the lid closed.

## Part 2: the restart

**What was run.** The restart came at 17:48, seven hours after Part 1. The recorder had ended by itself at 11:59:53, at its two-hour limit, so it recorded none of this. The times below come from four other places: the MacMosh app's log on the daily Mac, the workhorse's own log (`host.log`), the workhorse's boot time, and the start times of its processes.

| Time | Who | What |
|---|---|---|
| 17:48:43 | Shariq, on the daily Mac | `bash ~/macmosh-sitting-2/restart.sh`, which runs `macmosh restart workhorse --full`. He typed `restart`, then the workhorse's password |
| 17:48:44 | | the last line in the workhorse's log before the restart |
| 17:49:37 | | the menu says `Can't reach it` |
| 17:49:39 | | the workhorse starts (its boot time) |
| 17:50:04 | | the menu says `Locked after a restart`, 25 seconds after the start |
| 17:50:42 | Shariq | clicked `Unlock disk…`. A tab opened and he typed the password into ssh |
| 17:51:12 | | the menu says `Waiting for login`. The workhorse's log has its first line since the restart |
| 17:51:23 | Shariq | clicked `Log in…`. Screen Sharing was open six seconds later, and he logged in |
| 17:52:35 | | the menu says `Desk server is off` |
| 17:52:46 to 17:52:51 | the workhorse's login agent | started MacMosh's desk server, made the desk `sitting-2` again and wrote `start` in the log |
| 17:53:04 | | the menu says `Ready`, and has 12 lines where it had 7 |

**What was seen.**

- **Every step worked from the menu.** Shariq's words afterwards: "done looks like it all worked", and "the tests themselfes worked great".
- **The states could be told apart.** The menu went from `Can't reach it` to `Locked after a restart` to `Waiting for login` to `Ready`, in that order, and offered the right button at each.
- **No key warning.** The app says `Can't verify it` when an address answers with a key other than the pinned one. It never said that.
- **The unlock over ssh worked on Wi-Fi.** The workhorse's default route is its Wi-Fi interface. The menu said `Waiting for login` 30 seconds after the click on `Unlock disk…`.
- **After the unlock the workhorse stopped at the login window.** Its report said nobody was logged in, which is what `Waiting for login` means.
- **Screen Sharing could log in at the login window.**
- **The desk marked to come back came back by itself.** At 18:01 the workhorse's report listed `sitting-2` with one window and nobody attached. It is a new shell in the desk's folder. Whatever ran in the old one ended with the restart.
- **The lid setting survived the restart.** At 18:01 `pmset -g` on the workhorse still had `SleepDisabled` followed by `1`.
- **The menu was wrong for half a minute after the login.** Between the login and the login agent starting the desk server, the menu said `Desk server is off`, gave the hint `Run: macmosh prepare workhorse --fix` and offered `Finish setting up…`. Nothing needed fixing, and the next check said `Ready` (issue #88).
- **Every other session on the workhorse ended and stayed ended.** Shariq's working sessions are plain tmux sessions made by his own helper, not MacMosh desks, so nothing made them again. His words: "it killed off all my rmosh sessions and i had to start a new one". He started two again by hand, at 17:58 and 18:00.
- **`tmux ls` does not list desks.** Shariq looked for `sitting-2` with a plain `tmux ls` over ssh and did not see it. MacMosh's desks are in their own tmux server, so the command that lists them is `tmux -L macmosh ls`. The menu lists them too.

**Not shown by this run.**

- What each of the three addresses offered at the disk-unlock screen, which host key each one showed in each state, and whether the `.local` name answers before the unlock. The recorder would have written these down, and it had stopped. The next time the workhorse is restarted for some other reason, the recorder can be started first with `bash ~/macmosh-sitting-2/record.sh`. Nobody restarts it only for this.
- A restart with the lid closed. Shariq said afterwards that the lid was open during this one.
- A desk with a startup command coming back. `sitting-2` had no command.
- The menu's own `Restart…`, which skips the unlock. This run used `--full` so that `Unlock disk…` was tried.

**Verdict: pass.** Shariq got the workhorse back after a real restart with MacMosh's buttons only.

## What the build does with it

- **The lid-closed switch (Task 25) can be built on `disablesleep`.** The setting keeps the workhorse awake with the lid closed and survives a restart.
- **The status report has to read `SleepDisabled` from `pmset -g`,** not from `pmset -g custom`.
- **Heat.** Shariq means to run with the lid closed by default, so a way to see the workhorse's temperature or thermal state goes on the list for his review (Task 21).
- **Restart recovery (Task 24) has its real restart.** The fixtures that were to come from the recorder are still missing, as listed above.
- **The half minute after the login** is issue #88.
- **The guide has to say where desks are.** A plain `tmux ls` on the workhorse doesn't list them, and `tmux -L macmosh ls` does.
- **Desks made from the menu do not come back.** `New desk…` asks for a name and a folder and never marks the desk to come back after a restart. Only `macmosh desk new … --reopen` does. Whether that changes is Shariq's decision (issue #89). It also adds to issue #87: after a restart, every desk that was not marked has a name that stays taken and no line in the menu.

## Found while starting

`scripts/sitting-2/start.sh` made the desk but would not have opened it. `macmosh desk new` with a name and a folder creates the desk and returns. It opens the desk only when it had to ask for one of them. The runbook's step 1 says the tab becomes a prompt on the workhorse. On the day, the agent made the desk over ssh and Shariq opened it from the menu, so the bug was never met.

The helper now opens the desk after making it. Tried against a stand-in for the `macmosh` command: a first start makes the desk and then connects to it, a second start only connects, and a start whose `desk new` fails stops there.

The runbook also says now that the recorder stops after two hours and how to start it again before the restart.
