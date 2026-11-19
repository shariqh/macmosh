# Build log: MacMosh

This is raw material for a blog post and a YouTube video about building MacMosh. Each entry records (times with ≈ are estimates; the others were read from `date` or command output):

- the time (PT);
- which machine;
- who did it (Shariq or the agent);
- what was done, with the command where there was one;
- what happened, including the surprises.

Design: `superpowers/specs/2026-11-18-macmosh-v1-design.md`. Plan: `superpowers/plans/` (written after the design is approved).

## The setup

- **Workhorse:** 16" MacBook Pro, M1 Max, 64 GB, macOS 27.3 beta. It is plugged in, FileVault is on, and it already runs Shariq's terminal sessions.
- **Daily driver:** MacBook Air, M5, 24 GB, macOS 27.2.1.
- **Network:** both Macs are on Tailscale. Two always-on Linux boxes at home relay to the workhorse when it is locked after a restart.
- **Already installed on the workhorse:** mosh 1.4.0, tmux 3.8, iTerm2 3.6.11, Tailscale 1.102.4, Xcode 27.2 with Swift 6.4.2.

## How we got here (2026-11-15 to 2026-11-18)

- **15–17 Nov:** Shariq and an agent turned the MacBook Pro into an always-on workhorse by hand, driven from the Air (dev-setup #45). It took two days of commands and gotchas:
  - a VPN client that hijacked Tailscale's routes on every Wi-Fi change;
  - logins that vanish over SSH, because an SSH session can't read the macOS login keychain;
  - a restart that leaves the Mac off the network until someone logs in.
- **17 Nov, 11:36:** with the setup working, Shariq asked: "Is there a way to package all this as a desktop app to help manage? We had to do A LOT and now I have a lot of steps I have to remember."
- **17 Nov, 11:40:** the first sketch was a command plus a menu-bar icon, or a panel inside Agent Inbox. Shariq: "Honestly even just a way to use 'buttons' to manage everything so we never have to use these commands, and also we can distribute to others (probably as open source)." And on whether it belongs in Agent Inbox: "They seem like different jobs, 'cause one is for AI, sure, but what we've set up doesn't have to lend to AI at all, right? Just accessing any Mac as a workhorse."
- **17 Nov:** a prior-art check found pieces but not the whole job. VibeTunnel puts a Mac's terminals in a browser. SwitchBored lists machines in the menu bar with one-click SSH. Neither prepares the workhorse or gets you back in after a restart.
- **17 Nov, decisions:**
  - Who it's for: one person with one or two spare Macs. "Definitely A today."
  - After a restart: "Home out of the box, away optional. Also def needs a macOS toolbar icon."
  - How it's built: "Native Mac app, prototype first. Can we also solve for the MacBook lid being closed as a setting in that app?"
  - The lid: "We can also offer the dummy HDMI plug then in the app... that can be a smart way to monetize with an affiliate link or something. We can test the pmset thing first."
- **17 Nov, the name:** the agent proposed "Stablehand", the helper who keeps a workhorse fed. Shariq: "Heh, Stablehand is kinda funny. But maybe too whimsical."
- **18 Nov, 08:45:** Shariq: "What if we just called the workhorse app rmosh? Or macmosh?"
  - `rmosh` is taken: a Rust rewrite of mosh already uses it on GitHub, and it is also the name of Shariq's own shell helper.
  - "MacInMosh would be so good though..." It would. Apple's trademark guidelines bar takeoffs of its marks "for any purpose", and their own example of a name that isn't acceptable is "Jackintosh". So the pun stays a joke for the video, not the product's name.
  - **MacMosh** it is. Apple allows "Mac" plus another word as long as "Mac" is never shown more prominently than the rest.
- **18 Nov, 08:56:** the connection default flipped. The first plan had iTerm2's native tmux tabs over plain ssh as the default and mosh as the backup. Shariq: "Yeah, mosh should be the default so we can provide the most reliability."

## Log

| Time (PT) | Machine | Who | What | Result |
|---|---|---|---|---|
| 11-18 17:45 | MBP | Shariq | `mkdir ~/Development/macmosh`, then a fresh Claude Code session in it, pointed at the kickoff note from the earlier session | An empty folder and a new agent. The agent read the kickoff, the #45 design, plan and build log, the `rmosh` helper, and the brainstorm. |
| 17:49 | MBP | agent | Registered the project `macmosh` in Agent Inbox and created the board "MacMosh v1" | Eight rows: repo, design doc, builder check, Shariq's approval, plan, issues, going public, hand-off to the build agent. |
| 17:52 | MBP | agent | Read-only inventory: `sw_vers`, `mosh --version`, `tmux -V`, `pmset -g`, `fdesetup status`, `brew info --cask swiftbar` | mosh 1.4.0, tmux 3.8, iTerm2 3.6.11, Tailscale 1.102.4, Xcode 27.2. SwiftBar 2.1.1 is in Homebrew but not installed here. FileVault is on. On power the Mac never sleeps (`sleep 0`, `womp 1`); on battery it does (`sleep 1`). A Developer ID signing certificate is already in the keychain, so signing the app needs no new Apple account. |
| 17:52 | MBP | agent | `launchctl managername`, run inside the tmux session this agent lives in | **Surprise:** it prints `Background`, yet this tmux can read the keychain (`gh` is signed in from it). So that command can't tell a tmux that keeps logins from one that doesn't. The app needs a different check. |
| 17:55 | MBP | agent | Started three read-only research agents: the terminal stack (mosh, tmux, iTerm2, SwiftBar); macOS behaviour (`pmset`, FileVault, Screen Sharing, launchd); Tailscale, Homebrew, notarization, trademark and affiliate rules | Project rule: every outside fact in the design is checked against current vendor docs and cited, never taken from memory. |
| 17:58 | MBP | agent | README stub, edited by the local unslop pass | No warnings. |

## Shot list (video)

- The two-day cheat sheet of commands on one side, one menu-bar icon on the other.
- "I almost called it MacInMosh": the trademark rule and Apple's "Jackintosh" example.
- The lid-closed test on the MacBook Pro (to come).
