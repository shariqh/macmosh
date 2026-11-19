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
| 17:58 | MBP | agent | `git init -b main`, first commit, then `gh repo create shariqh/macmosh --private --source . --push` | The repo exists and is **private**. It goes public only after Shariq approves the design and says yes. |
| 18:02 | MBP and Air | agent | Looked for a read-only way to tell whether a terminal session can use the login keychain: `security show-keychain-info ~/Library/Keychains/login.keychain-db`, run inside the workhorse's tmux and again over plain SSH on the Air | **It works as a probe.** Inside the tmux that was started at login it prints `Keychain "…" no-timeout`. Over SSH it prints `User interaction is not allowed.` It reads no secret. This becomes the app's "sign-ins work" light. |
| 18:02 | Air (over SSH) | agent | Versions on the Air | macOS 27.2.1, iTerm2 3.7.7 (the MacBook Pro has 3.6.11), mosh 1.4.0, tmux 3.8. |
| ≈18:05 | MBP | agent | The three research agents reported, each with quotes and links | Things that changed the design: |
| | | | mosh | 1.4.0 is from October 2022 and is still the latest release. A mosh server whose laptop never comes back waits forever unless it is given a timeout, so abandoned connections pile up on the workhorse. MacMosh will set a one-week timeout. |
| | | | iTerm2's native tmux tabs over mosh | Still unsupported. iTerm2's author: mosh "literally drops parts of the output", which tmux integration "can't accept". The matching mosh issue has been open since 2019. So native tabs stay an ssh-only extra, as Shariq decided. |
| | | | iTerm2 | A new stable version, 3.7.8, came out today. Its AppleScript commands still work but are "no longer receiving improvements", its link scheme always shows a confirm dialog, and its Python API is off by default. |
| | | | FileVault | Apple's own `man fdesetup` has a section called "REMOTE UNLOCKING VIA SSH". Only a password works before the unlock, because ssh's settings and keys sit on the locked disk. Apple doesn't say where the Mac ends up afterwards; on this Mac it was the login window. |
| | | | Screen Sharing | "In macOS 12.1 or later, Screen Sharing can't be enabled by the kickstart command-line tool." So the app can't switch it on: the user flips it once at the workhorse. |
| | | | The lid | `disablesleep` is not in the `pmset` manual at all, though the program accepts it. Four write-ups say it keeps an Apple-silicon MacBook awake with the lid closed; one says it stopped working. Only a test on the MacBook Pro settles it. |
| | | | The dummy-plug link | **Surprise:** Amazon's Associates rules ban affiliate links, and any link to Amazon, "on or in connection with any client-side software application". The link can't be in the app. It has to live on Shariq's own site, with a disclosure. |
| | | | Homebrew | A personal tap has no popularity bar. Since Homebrew 6.0, people have to trust a third-party tap before Homebrew will load it (`brew trust`). |
| | | | Tailscale | Only the open-source `tailscaled` runs before login. The normal Mac app doesn't, which is why a restarted workhorse is off the tailnet until someone logs in. Apple TVs and Macs can act as the relay at home. |
| | | | macOS privacy | From macOS 15 an app needs the Local Network permission to reach an address on the home network, and an `ssh` it starts counts as the app. Tools run from Terminal are exempt. |
| ≈18:09 | MBP | agent | Wrote the design: `docs/superpowers/specs/2026-11-18-macmosh-v1-design.md` | The main calls: the app runs only on the daily Mac; the workhorse gets one readable shell script and a login agent; desks live in their own tmux server so nothing can start it the wrong way; every terminal tab runs a `macmosh` subcommand; the prototype uses the real engine. Nine things are listed to test on the real Macs before code depends on them. |
| ≈18:10 | MBP | agent | First-pass read of the design by the local model on the homelab box (`ask.sh`) | Twelve points, five worth fixing. The best one: if the router hands the workhorse a different address during a restart, the app can't find it while it is locked. The design now also remembers the Mac's `.local` name, and says to reserve the address. |
| 18:11 | MBP | agent | Builder check: a fresh reader, with no context, reads the design as someone who has to plan the build | Five questions came back. Two were the agent's to settle, three are Shariq's. |
| | | | The best catch | The first draft told "locked after a restart" by "the Mac refuses my ssh key". But a key with a passphrase that isn't loaded is refused too, so the app would have shown Locked, and offered an unlock, for a disk that wasn't locked. Now MacMosh has an ssh key of its own with no passphrase, and Locked is decided by what sign-in methods the Mac offers. |
| | | | The second catch | "Sign-ins off → Fix" would have restarted the desk server, which closes every open desk. It now lists the desks and asks first. |
| | | | Also settled | MacMosh runs beside the hand-built setup on the MacBook Pro and takes nothing over. Tests run against a throwaway tmux socket, never the live one. |
| 18:16 | MBP | agent | Opened PR #1 with the design, and put four decisions on the Agent Inbox board for Shariq | Waiting on him: approve the design; allow MacMosh on the MacBook Pro and two test sittings; choose the signing certificate; choose when the repo goes public. The plan and the issues come after his approval. |
| 11-19 08:33 | Agent Inbox | Shariq | Answered the first of the four: when the repo goes public | "Public after design approval." The build will happen in the open. The other three are still open. |
| 08:36 | MBP | agent | Privacy check ahead of going public: searched the files, every commit in the git history and PR #1 for addresses, host names, tokens, file paths and private project names | No tokens, host names, network names or file paths. Swapped the two real project names in the menu sketch for generic ones. The repo stays private until the design is approved. |
| 08:38 | Agent Inbox | Shariq | Answered the second: which Apple certificate signs the app | The company Developer ID already on the MacBook Pro, so no second $99-a-year membership. The design now records both answers as his decisions. Still open: approving the design, and the go-ahead for the MacBook Pro. |

## Shot list (video)

- The two-day cheat sheet of commands on one side, one menu-bar icon on the other.
- "I almost called it MacInMosh": the trademark rule and Apple's "Jackintosh" example.
- The lid-closed test on the MacBook Pro (to come).
