# MacMosh

MacMosh turns a spare Mac into a workhorse: a machine that stays on, stays reachable, and runs long jobs. You drive it from your daily Mac using a menu-bar icon instead of memorised commands.

**Status: early.** The design is approved and the build plan is written. The build has not started, and there is nothing to install yet.

## What it will do

- Open a terminal on the workhorse that survives Wi-Fi drops or a closed laptop lid. [mosh](https://mosh.org) carries the connection, and [tmux](https://github.com/tmux/tmux/wiki) keeps each session running on the workhorse while you are away.
- Show in the menu bar whether the workhorse is ready, waiting for a login, or locked after a restart.
- Get you back in after a restart from your other Mac, on your home network.
- Keep a MacBook working with its lid closed, where macOS allows it.

It is for one person with one or two spare Macs, and it is not tied to any AI tool.

## Where things are

- [`docs/build-log.md`](docs/build-log.md): what was done, in order, with the decisions and the surprises.
- [`docs/superpowers/specs/2026-11-18-macmosh-v1-design.md`](docs/superpowers/specs/2026-11-18-macmosh-v1-design.md): the design for version 1.
- [`docs/superpowers/plans/2026-11-19-macmosh-v1.md`](docs/superpowers/plans/2026-11-19-macmosh-v1.md): the build plan, one task per GitHub issue.

## Licence

MIT. See [`LICENSE`](LICENSE).

MacMosh is an independent project. It is not affiliated with or endorsed by Apple Inc. Mac and macOS are trademarks of Apple Inc.
