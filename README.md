<img src="App/AppIcon.iconset/icon_128x128@2x.png" width="96" height="96" alt="The MacMosh icon: a letter M made of orange squares on a light tile">

# MacMosh

MacMosh turns a spare Mac into a workhorse: a machine that stays on, stays reachable, and runs long jobs. You drive it from your daily Mac using a menu-bar icon instead of memorised commands.

> [!NOTE]
> MacMosh is a working preview that its author uses every day. There is no download yet: the first signed release is being prepared. Today you can [build it from source](#build-it-from-source).

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/images/window-dark.png">
  <source media="(prefers-color-scheme: light)" srcset="docs/images/window-light.png">
  <img alt="The MacMosh window. The sidebar lists sample workhorses in different states: Ready, Locked after a restart, Can't reach it, Checking and Ready, sign-ins off. The chosen one, Workhorse, is Ready and lists six desks (api, blog, garden, notes, shop, website), each with an Open button." src="docs/images/window-light.png">
</picture>

The pictures show made-up sample data. The menu, which opens from the M in the menu bar, shows each workhorse's state and desks too.

## Words used here

- **The workhorse** is the spare Mac that stays on and runs your work.
- **The daily Mac** is the Mac you sit at. MacMosh runs here.
- **A desk** is one named terminal session on the workhorse that keeps running when you disconnect. Each desk opens as a terminal tab.

## What it does

- **Desks that keep running.** [mosh](https://mosh.org) (a replacement for the ssh terminal connection that survives Wi-Fi drops and a closed lid) carries the connection. [tmux](https://github.com/tmux/tmux/wiki) (a program on the workhorse that keeps each desk alive while nobody is connected) keeps the work going. A desk can come back by itself after the workhorse restarts and someone logs in.
- **The workhorse's state in plain words**, in the menu and the window: `Ready`, `Ready, sign-ins off`, `Waiting for login`, `Locked after a restart`, `Can't verify it` or `Can't reach it`, with a short line under it when it needs one, such as `Tailscale is off on this Mac.`
- **Getting back in after a restart.** `Unlock disk…` opens a terminal tab where you type the Mac's password into ssh. MacMosh never sees it. Unlocking over the network needs a workhorse with Apple silicon and macOS 26 or later; on an older or Intel Mac, MacMosh says so and you unlock it at the Mac. Then `Log in…` opens Screen Sharing at the login window.
- **Lid-closed mode** for a laptop workhorse. It changes a power setting Apple doesn't document. The setting was tested by hand on one MacBook Pro: with the lid closed, on power and with no display, it stayed awake and reachable for 43 minutes. The menu button itself was not part of that test. Read [docs/lid-closed.md](docs/lid-closed.md) before you depend on it.
- **Adding a Mac, and a checklist that sets it up.** At the other Mac you turn on Remote Login and Screen Sharing. `Add a Mac…` opens a terminal tab that shows the workhorse's key fingerprint to compare, then installs MacMosh's own ssh key there; you type the workhorse's password once. The checklist then checks both Macs and fixes what it can: it installs mosh and tmux with Homebrew and puts MacMosh's small script on the workhorse. Anything that needs a password, such as keeping the workhorse awake on power, opens a terminal tab that shows the command first.
- **Three ways to connect**, chosen per workhorse in Settings under Connection.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/images/settings-dark.png">
  <source media="(prefers-color-scheme: light)" srcset="docs/images/settings-light.png">
  <img alt="MacMosh's Settings page. This Mac's Terminal choice is Pick for me. The sample workhorse Attic has Connection set to Mosh, with the line: One terminal tab per desk. When the Wi-Fi drops or the lid closes, the tab picks up by itself when the network returns. Needs mosh on both Macs. Below are Typing prediction, Projects folder, Run the checklist and Remove MacMosh from this workhorse." src="docs/images/settings-light.png">
</picture>

### Which connection do I use?

The lines are the ones the app shows under Connection.

| Connection | What you get, and what happens when the Wi-Fi drops or the lid closes | Needs |
|---|---|---|
| **Mosh** (the default) | One terminal tab per desk. The tab picks up by itself when the network returns. | mosh on both Macs |
| **Tabs** | Every window of a desk as a real iTerm2 tab. The tabs close; your work keeps running, and reconnecting brings the tabs back. | iTerm2. In Terminal, Mosh is used instead. |
| **Plain ssh** | One terminal tab per desk. The tab ends; your work keeps running. | Nothing extra |

Use Mosh unless you have a reason not to. Use Plain ssh if mosh is blocked, for example by the workhorse's firewall.

## What you need

- **Two Macs**: the daily Mac and the workhorse.
- **The daily Mac**: macOS 15 or later.
- **The workhorse**: macOS 15 or later on Apple silicon. Unlocking after a restart over ssh also needs macOS 26 or later. Intel Macs may work but are not tested.
- **[Homebrew](https://brew.sh)**, the package manager mosh and tmux come from. MacMosh installs mosh on the daily Mac, and mosh and tmux on the workhorse, with Homebrew. On the daily Mac you install Homebrew yourself; on the workhorse, its installer runs in a terminal tab and asks for the Mac's password.
- **A terminal**: [iTerm2](https://iterm2.com) (a terminal app for macOS) is optional; Apple's Terminal works. In Terminal, each desk opens in a window of its own.
- **[Tailscale](https://tailscale.com)** (a private network between your own devices) is optional: it lets you reach the workhorse away from home. At home, MacMosh uses the home network.
- **FileVault** (macOS disk encryption) can stay on. MacMosh never changes it. With FileVault on, a restarted workhorse is `Locked after a restart` until someone types its password.

## What it is not

- It is for one person with one or two spare Macs, not a fleet.
- It is not a remote desktop. It opens terminal tabs, and Apple's Screen Sharing when you need to see the screen.
- It has no automatic updates.
- It has no telemetry, no account and no cloud service. The network calls the app makes: ssh to your workhorses, and the local `tailscale` command. Nothing else.
- It never types, stores or sees a password.
- It is not tied to any AI tool.

## Build it from source

You need a Mac with Xcode (Swift 6 or later) and [Homebrew](https://brew.sh).

1. **Install the two tools the checks use.** Run `brew install tmux shellcheck`. tmux runs in the tests; shellcheck checks the shell scripts.
2. **Clone the repository.** Run `git clone https://github.com/shariqh/macmosh.git`, then `cd macmosh`.
3. **Build.** Run `swift build`. The first build also fetches Apple's swift-argument-parser package.
4. **Run the checks.** Run `scripts/check.sh`. It builds, runs the tests and checks the scripts, and stops at the first failure. The last line is `check.sh: all checks passed`.
5. **Build the app.** Run `scripts/build-app.sh --adhoc`. It signs the app ad hoc (with no developer certificate). The last line is `build-app.sh: built dist/MacMosh.app (ad hoc)`.
6. **Open it.** Move `dist/MacMosh.app` to your Applications folder and open it. No window opens: look for the M in the menu bar. Its menu says `No workhorses yet` and offers `Add a Mac…`. `Open MacMosh` opens the window.
7. **Allow what macOS asks.** The first time MacMosh opens a tab in a terminal app, macOS asks whether MacMosh may control it. The first time it reaches the workhorse on your home network, macOS asks about the local network. Choose Allow both times.

### If something's off

- **`check.sh` stops at a `shellcheck` line**: shellcheck isn't installed. Run `brew install shellcheck`.
- **macOS asks for the permissions again**: this is expected after a rebuild. `build-app.sh` says so: `macOS will ask for the app's permissions again after every rebuild.`
- **A desk won't open with mosh** and the checklist says the workhorse's firewall is on: switch that workhorse to Plain ssh in Settings, or allow mosh-server in the firewall's options at the workhorse.

## How it is built

MacMosh is built in the open, one GitHub issue and one pull request per change. An AI coding agent does the building under the author's direction, and [docs/build-log.md](docs/build-log.md) records what was done, in order, with the decisions and the surprises. The design is [docs/superpowers/specs/2026-11-18-macmosh-v1-design.md](docs/superpowers/specs/2026-11-18-macmosh-v1-design.md).

## Licence

MIT. See [LICENSE](LICENSE).

Mac and macOS are trademarks of Apple Inc., registered in the U.S. and other countries and regions.

MacMosh is an independent project, not affiliated with Apple or with the mosh project.
