# MacMosh main window design

Status: approved by Shariq on 2026-11-23 ("Approve; build after my review of the menu"). The same day he chose "Start the window now, alongside the menu", so it is built now, beside the menu's changes (amended 2026-11-23; this line read "a proposal for Shariq to approve. Nothing here is built until he does."). Written: 2026-11-23. Issue: #94. Repo: `shariqh/macmosh`.

This document adds to the v1 design (`docs/superpowers/specs/2026-11-18-macmosh-v1-design.md`, called "the v1 design" below). It changes nothing in it yet. Where the two would disagree once this is approved, section 7.7 says which parts of the v1 design and plan change.

## Changes since approval (2026-11-23)

Shariq approved this design on 2026-11-23 with "Approve; build after my review of the menu" (issue #94). The recommended answers stand for decisions 2 to 5, so decision 6 does not arise. Later that day his requests changed the five points below. Each is amended in place and marked "(amended 2026-11-23)"; nothing else is rewritten.

1. **When it is built.** On the board he chose "Start the window now, alongside the menu", which replaces "build after my review of the menu". (The status line above.)
2. **The menu gets submenus and a line per window.** About the menu he wrote: "the menubar is kinda messy once i have things running. can we do submenu items where it makes sense? and some of that stuff can move into the desktop app where it makes sense as you get that ready." (issue #107). About tabs: "build it and also update the menubar to show each tab in a session as a line item so i can click on it and it takes me to the right tab" (issue #105). So the menu no longer keeps every line word for word. Its design is `docs/superpowers/specs/2026-11-23-menu-submenus-design.md`, called "the menu spec" below. (Section 7.6, its first and last paragraphs.)
3. **The submenu per desk of v1 call 35 is now in the menu itself**, for the same two requests. (Section 7.7, the row about call 35.)
4. **Step 1 was built as written (issue #108, merged as pull request #109 on 2026-11-23)**, because of "Start the window now, alongside the menu". Its tree is also the groundwork for the submenus, and the window's steps and the menu's steps now run side by side. Step 0's documents PR came after step 1, not before it. (Section 8, step 1.)
5. **Script versions.** To build "update the menubar to show each tab in a session as a line item" (issue #105), pull request #106 (merged on 2026-11-23) made the workhorse script 0.7.0 (views), and the menu spec's labels make it 0.8.0. So `desk-set` takes the next free version. (Section 8, step 7, and section 10, decision 6.)

Where sections 1, 4 and 7.1 A say the menu stays as it is plus one line, that now holds for step 1 and for this window's own steps. The menu's other changes are the menu spec's. Item 2 also applies to section 4's "Breaking the menu" and to decision 5's "It keeps the menu word for word". Where step 0, section 7.7's last paragraph and section 12 say the documents PR comes before step 1, item 4 applies. Section 5.2's "The current script is 0.6.0" was true when this was written; since pull request #106 it is 0.7.0 (item 5).

## 1. The short version

MacMosh gets one window, called **MacMosh**, opened from a new line in the menu. It is a board of desks. When he opens it, he sees the workhorse's state in one line and then every desk as a short row: its name, what runs in it, whether a terminal tab is open on it, its folder, and an **Open** button.

The things he does most each take one click or one short form:

- open a desk;
- open every desk that has no tab, after the daily Mac restarts;
- make a desk for a new project that starts his agent;
- bring back a desk whose last shell exited, and choose there whether it stays next time.

The rest sits in the same window: the menu's buttons for the rarer states (Locked, Can't reach it, Not set up), a Settings page that takes over what issue #32 planned, and an Add a Mac page.

The window runs no checks of its own. It shows what the menu's checks already found, so the workhorse does no extra work and the window always agrees with the menu. Anything that needs a password still opens a terminal tab or Screen Sharing. Desk actions that use only MacMosh's key (new desk, rename, remove, start again) run inside the window as forms, with no questions typed into a terminal.

The menu stays as it is, plus one line. Nothing new is installed on the workhorse. Two optional later steps change the existing workhorse script, and only if Shariq says yes (section 10, decisions 3 and 5).

## 2. Words used

The v1 design's words (section 2 there) still hold. This design adds three rules, because "window" already means something:

| Word | Meaning here |
|---|---|
| **The MacMosh window** | The app's new window. On screen it is only ever called "MacMosh" (its title and the menu line "Open MacMosh"), never "the window", so it can't be confused with a desk's windows. |
| **Window** (inside a desk) | A tmux window inside a desk, as today: "2 windows", "New window in website". |
| **Tab** | A terminal tab (or, in Apple's Terminal, a terminal window) that MacMosh opens on a desk or for a password. |
| **Ended desk** | A desk that was not permanent and whose last shell exited, so the workhorse removed it (v1 design, calls 27 and 28). |

## 3. Why

On 2026-11-22, after the sitting-2 restart ended his nine hand-made desks, Shariq wrote in issue #94:

> "i think it's worth having a desktop app as well that we can use to configure/see what's going on and set target/workhorses."

The same day he said, about desks: "once we have a desktop app the user can decied if the desk is ephemeral or permanant after exits". He asked for a way to rename a desk, said yes to the New desk form asking for a command to start, and put "a cli/mcp to let AI manage/create desks and states for you" on the backlog (issue #99).

He runs an AI coding agent in most desks, with four to nine desks open on one workhorse, one per project. A menu alone is a poor fit for that:

- **It is flat and long.** Each open desk takes four lines (the desk, `New window in…`, `Rename…`, `Remove…`). Nine desks make about 36 lines before the workhorse's own buttons. Design call 35 already says a submenu per desk "belongs with the app's windows".
- **It shows little about each desk.** The report carries each desk's folder, startup command and whether it comes back after a restart. The menu shows none of them (they are parsed and unused).
- **It closes when he looks away.** A menu can't stay on screen while he works through his desks.
- **Everything that needs typing opens a terminal tab with questions.** New desk asks three questions, Rename one, Remove a typed `yes`. He finds long question-and-answer flows cumbersome.
- **Some settings have no home in the app.** Nothing in the app sets a workhorse's projects folder (`docs/first-run-notes.md`), and the terminal choice is only on the command line (`macmosh settings terminal`).
- **There is no way back for an ended desk.** Once an ordinary desk's last shell exits, it is gone from the menu, with no "make it again".

## 4. Goals, non-goals, anti-goals

### Goals

1. **See everything in one place.** Every workhorse with its state and the reason, in the menu's exact words. Under it, every desk with its windows, its open tabs, its folder, its startup command, whether it comes back after a restart, and whether it stays when its last shell exits.
2. **The menu's buttons, doing what the menu's do.** Every state shows the same buttons as the menu, through the same code.
3. **Desk work without terminal questions.** New desk, Rename and Remove become forms and one confirm click in the window.
4. **Decide after an exit.** An ended desk can be started again, as it was or kept from then on.
5. **One place to configure.** A Settings page for the terminal choice and each workhorse's settings, in the same window.
6. **Meet issue #94's "done when"**, with one correction: the tests build the window's data from recorded workhorse reports, not from `--json` output (section 5.2 says why).

### Non-goals for this design

- A terminal inside the window. Desks still open in iTerm2 or Apple's Terminal (v1 design, non-goals).
- Telling whether an agent in a desk is working or waiting. That needs reading a desk's screen, which issue #99 question 4 leaves open as "a much larger step".
- The guided Add a Mac (Task 28, issue #31) and the checklist window (Task 29). This window gives them a place to land later; it does not build them.
- A Dock icon or app-switcher entry while the window is open, unless the first trial shows it is needed (section 11).
- Fleets: bulk actions across Macs, drag to reorder. The app still handles one or two workhorses.
- The command line and MCP server for agents (issue #99).
- Notifications (Task 30), a heat reading (issue #91), and "practise a restart".
- Tests that draw the views. Only the models, forms and rules behind them are tested, as with the menu today.

### Anti-goals: failures even if it works

- **A password field anywhere in the window.** Every password is typed into ssh, `sudo` or Screen Sharing.
- **Anything new running on the workhorse.** No app, daemon or listening service. The window reads the same report the menu reads.
- **More load on the workhorse.** The window adds no timer of its own. Each check runs several system commands on the workhorse, so a second poller would double that work.
- **A window that disagrees with the menu.** Same states, same hints, same buttons, from one set of rules.
- **A window that blanks or jumps while a check runs.** It keeps what it showed and says "Checking…".
- **Breaking the menu.** The menu's lines stay word for word as today, proven by its existing tests.
- **Losing the Remove safeguard.** Remove still names the desk and the windows that will close, and still needs an explicit yes.
- **Names in the system log.** Window log lines are fixed words, like the menu's.

## 5. Constraints

### 5.1 What Shariq has ruled

| Ruling | His words, where recorded | What it means for the window |
|---|---|---|
| No third-party app or library a user must install | "i don't want third party dependency can we not make a native menu bar item instead" (2026-11-19) | SwiftUI and AppKit only. No new package in the app. |
| MacMosh never runs as root and never sees a password | v1 design, sections 1 and 4 | Unlock, pair, restart, the lid-closed switch and Homebrew stay terminal tabs. Log in stays Screen Sharing. |
| The workhorse runs only a plain shell script; nothing new is installed there | v1 design, section 6 and approach 3 | No workhorse app or service. A change to the script itself is allowed only with his yes. |
| Plain words in everything the person reads | v1 design, section 11 | Short labels; the state names and hints come from the same code as the menu's. |
| Long question-and-answer flows are cumbersome | Build log, sitting 1 ("this is pretty cumbersome") | Forms with good defaults, not a wizard. |
| Every new desk comes back after a restart; a desk is ephemeral unless permanent | v1 design, section 13 (#89, #87) | The New desk form defaults to "comes back" ticked and "Remove the desk" when it exits. |
| `--permanent` is kept because the desktop version will use it | Issue #89 | The form's "Keep it, closed" choice sets that same stored field. |
| Desks can be renamed | "the ability to rename a desk would be importnat where possible" (#95) | Rename is in the window. |
| New desk asks for a command to start | "Yes, add the question" (#98) | The form has a "Command to start" field. |
| One person with one or two spare Macs | v1 design, section 13 | The window is sized for desks, not for a fleet. |

### 5.2 What the code imposes

Read from the repository at the commit this document starts from.

- **One scene today.** `MacMoshApp` has a single `MenuBarExtra { … } label: { … }` and no `Window` (`Sources/MacMoshApp/MacMoshApp.swift`). `App/Info.plist` sets `LSUIElement`, so there is no Dock icon and no app menu bar. The entitlements file holds only the Apple events entitlement, and a test enforces that (`Tests/MacMoshKitTests/AppBundleTests.swift`). A window needs no new entitlement or plist key.
- **The data is already in memory, then thrown away.** `MenuRefresher` gathers a full `CheckResult` per workhorse (state, `HostStatus` with desks, windows, definitions, power and battery), builds the flat menu with `MenuModel.build`, and keeps only the menu. While a check runs long, `.stillChecking` replaces a workhorse's whole block with "Still checking…" (`MenuModel.swift`). A window built the same way would blank every time.
- **`--json` is too thin for issue #94.** `macmosh status --json` and `macmosh desks --json` carry only a desk's name, window count and attached tabs. Folder, startup command, reopen, keep and permanent are in `HostStatus.Definition` but in no JSON. So the window reads the in-process `CheckResult`, and its tests use recorded report text parsed by `HostStatus.parse`, like `Tests/MacMoshKitTests/Fixtures/status/full.txt`. That fixture's `def` line is in the old form without the permanent field, so a new fixture is needed.
- **What runs in a desk.** The report gives each tmux window's name (`#{window_name}`), the number of tabs attached, and the saved startup command. It has no process, no agent state and no last-activity time. The script makes sessions and windows without a name, so tmux's automatic rename usually names each window after the program running in it (`man tmux`, `automatic-rename`: the window is renamed unless "a name is specified at creation").
- **Every menu action goes through the bundled helper.** `MenuAction` is `.tab([args])` (a terminal tab runs `Contents/Helpers/macmosh` with those arguments) or `.run([args])` (the helper runs in the background). Every argument must be plain characters (letters, digits and `@%+=:,./_-`), checked by `TabCommand`. So a startup command with spaces can't go through that path. It must go in-process through `DeskFlow` and `HostCommands`, where `SSHInvocation.hostCommand` quotes each argument once.
- **Desk actions already work in-process.** `DeskFlow.newDesk` takes a `NewDeskRequest` (name, folder, reopen, keep, permanent, command) and asks nothing when name and folder are given. `renameDesk(from:to:)`, `newWindow` and `removeDesk(kill:)` ask nothing either. Each is one key-only ssh call with a 15-second limit.
- **Nothing changes an existing desk's flags.** The workhorse script has no subcommand that changes `permanent`, `reopen` or the startup command after a desk is made.
- **An ended desk's definition is removed.** When an ordinary desk's last shell exits, the script's `desk-closed` hook removes its definition about a minute later (v1 design, call 28; `host/macmosh-host`, `cmd_desk_closed`). The app still holds the report from before the exit.
- **The menu-open signal has no filter.** The app refreshes and logs `menu opened` on every `NSMenu.didBeginTrackingNotification`. The source comment says: "Once the app has windows of its own, a popup button in one would count too, and this needs to tell them apart." CI checks that `menu opened` is absent before its test click.
- **Refreshes never overlap.** One asked for during a check runs once after it. A button's follow-up check can wait up to the 20-second budget, plus a 5-second second look, plus its own run.
- **A likely name clash.** MacMoshKit has a type called `Menu`, and so does SwiftUI. A view that uses both would be ambiguous. This was not built to confirm it.
- **No test target for the app.** Logic lives in MacMoshKit and is tested there with swift-testing. Views stay thin.
- **The helper path.** Tab and run buttons need `dist/MacMosh.app` built by `scripts/build-app.sh`, in a folder with no space in its path. They fail under `swift run`.
- **No default workhorse.** Nothing in the code or the v1 design is called a default workhorse or a target.
- **Which script version each desk control needs.** The report's header gives the script's version (`HostStatus.scriptVersion`). `desk-rename` first appears in script 0.6.0 (commit f71fe3a, #100). The permanent field and `--permanent` first appear in 0.5.0 (commit c954f29, #96). `--command` is older than both. The current script is 0.6.0 (`host/macmosh-host`, `MACMOSH_HOST_VERSION`).
- **A newer script with the same protocol leaves a workhorse Ready.** `StateResolver` gives "Needs setting up" (`.notSetUp(.hostScriptOutdated)`) only when the report's protocol number differs (rule 4, `.unsupportedProtocol`). Only the checklist compares script versions (`Checklist.swift` through `WorkhorseChecks`, which calls `HostInstaller.decide`). Decision 6 in section 10 is about this.
- **The report carries no home folder.** `HostStatus.home` is the workhorse's home network address (address, prefix and local name), not a folder, and `cmd_status` prints no `$HOME`. Definitions store full paths, because `cmd_desk_new` expands a leading `~` (`mm_expand_tilde`) before saving.
- **What the script counts as a taken desk name.** `cmd_desk_new` refuses a name only when a session with that name is open, or a permanent definition holds it; any other leftover line with that name is replaced. `cmd_desk_rename` uses the same rule while the desk server is up.
- **When a definition goes.** After a desk's last shell exits, the `desk-closed` hook waits `MM_HOOK_DELAY` (60 seconds by default) before removing a non-permanent definition. When the whole server goes away, as at a restart, `cmd_start` drops no lines, so a desk without reopen keeps its line and gets no session.
- **The menu's notice can't be set from outside.** `MenuRefresher` declares `public private(set) var notice`, and only `perform(_:using:)` sets it, clearing it first.
- **A check reports every workhorse at once.** `MenuData.gather` returns nothing until every workhorse has answered or its 20-second budget has run out.
- **The background save touches only report fields.** `WorkhorseStore.absorb` (`StatusChecker.swift`) updates, under the store's lock, only the seven fields a report fills: home address, home prefix, local name, macOS version, chip, last seen and last key accepted. Name, connection, typing prediction, projects folder and ssh key file are left alone.

### 5.3 What Apple's frameworks impose

Read on developer.apple.com (through its documentation data endpoint) for this design, on 2026-11-23.

| Fact | Apple's words | Source |
|---|---|---|
| The initializer the menu uses today must not be mixed with other scenes | "When this item is removed from the system menu bar by the user, the application will be automatically quit. As such, it should not be used in conjunction with other scene types in your App." | [1] |
| The other initializer reports removal instead of quitting | "If the user removes the item from the menu bar, the binding will be set to false." | [2] |
| A `Window` is single, and opening it again brings it forward | "A scene that presents its content in a single, unique window." … "If the window is already open when you call this action, the action brings the open window to the front." | [3] |
| A `Window` as the main scene quits the app on close | "If your app uses a single window as its primary scene, the app quits when the window closes." | [3] |
| A window can be kept from opening at launch | "The scene will not present itself in the absence of any previously restored scenes." (macOS 15.0) | [4] |
| An `LSUIElement` app has no Dock icon and no menu bar | "The application doesn't appear in the Dock and doesn't have a menu bar, but it may be activated programmatically or by clicking on one of its windows." | [5] |
| Bringing the app forward is only a request | "calling this method doesn't guarantee app activation." | [6] |
| Changing the Dock setting at runtime is only an attempt | "Attempts to modify the app's activation policy." | [7] |
| The Settings scene works through an app menu | "Passing a view as the argument to a settings scene in the App declaration causes SwiftUI to enable the app's Settings menu item." | [8] |
| The menu-tracking signal names no menu-bar-item object | "Posted when menu tracking begins." … "The notification object is the main menu bar … or the root menu of a popup button." | [9] |
| A toolbar can grow its own menu | "If not all items fit in the available space, an overflow menu may be created" | [10] |
| A view's task stops when the view goes | "If the task doesn't finish before SwiftUI removes the view or the view changes identity, SwiftUI cancels the task." | [11] |

**The app's minimum macOS is 15.0**: `Package.swift` sets `platforms: [.macOS(.v15)]`, `App/Info.plist` sets `LSMinimumSystemVersion` to 15.0, and `AppBundleTests` checks it. Every API this design names is available there. `defaultLaunchBehavior(_:)` with `.suppressed` and `restorationBehavior(_:)` came in macOS 15.0 [4], and `NSApplication.activate()` in macOS 14.0 [6] (availability re-read on Apple's data endpoint for this revision).

Two consequences follow. A Settings scene would have no menu to open it from, because the app has no menu bar, so settings belong in the window. And because the menu-tracking signal can't yet tell the menu-bar menu from a menu in the window, the window must not contain one (section 7.2).

Apple's pages do not say whether `openWindow` from a menu-bar app with no Dock icon brings the window in front of other apps, whether paste and other edit shortcuts work in its text fields without an app menu, or how a Dock icon shown only while a window is open behaves. Section 11 says how each is settled.

## 6. Approaches considered

Three designs were drawn up and judged against the code and Apple's pages.

1. **The menu, laid out in a window (smallest).** One scrolling column with a block per workhorse and the menu's own buttons on every desk row (Open, New window, Rename…, Remove…). New desk and per-workhorse settings become sheets; Rename and Remove stay terminal tabs. Its first step proves the menu is unchanged.
   - For: the safest build, and every claim in it is true. No extra polling, no change to the menu, no change to the workhorse.
   - Against: it answers "see" more than "configure". Nine desks with four buttons each make about forty buttons. It has nothing for his commonest moves: opening every desk without a tab, or bringing back a desk that just ended. "Ephemeral or permanent after exits" is not addressed.
2. **One home for everything (home).** A sidebar window with Desks, Checklist and Settings tabs per workhorse. Every terminal form becomes a window form, including the checklist, Fix, removing MacMosh from a workhorse and a guided Add a Mac. The menu's New desk, Rename, Remove and Run the checklist would open the window instead of tabs.
   - For: it answers his words most fully, and has several good details (below).
   - Against: about eight PRs and 2,500 to 3,500 lines by its own estimate. It rewrites Tasks 28 and 29 before his review of them, gives every flow two faces whose wording can drift, and changes the menu. Its per-desk "⋯" is a menu, which would set off the menu-open signal.
3. **A desk board (his day, recommended).** Built around the desks he goes back to: short rows, details on click, "Open the 2 not in a tab", an Ended list with "Start again" and "Start again and keep it", and Settings as a page of the same window.
   - For: it fits how he works with four to nine agent desks, it answers "decide after exits" with no workhorse change, and it stays plain.
   - Against: more moving parts than the smallest (the Ended list, per-action progress). As first drawn it let the app run with no menu-bar icon and checked again on every focus change; both are dropped below.

| | Smallest | Home | Desk board |
|---|---|---|---|
| Answers "see what's going on" | Yes | Yes | Yes |
| Answers "configure" | Partly (sheets) | Fully | Mostly (Settings page) |
| "Decide after exits" | No | Only with a script change | Yes, with no script change; a switch later with one |
| Fits nine agent desks | Busy (about 40 buttons) | Busy (tabs and "⋯" menus) | Short rows, details on click |
| Size | Five small PRs | About eight PRs | Six PRs, two more optional |
| Changes the menu | One line | Reroutes four lines | One line |
| Changes the workhorse | No | Optional | Optional |
| Risk to the menu-open signal | None | "⋯" menus trip it | None, with the control rules below |

**Recommended: the desk board, built in the smallest design's order and with its safety rules.** The smallest design is the safest but answers only half of what he asked. The home design answers everything but is two to three times the work, gets ahead of his Task 21 review, and changes the menu. The desk board fits his day best and is moderate in size when it is built in steps, with a first step that changes nothing he can see.

Taken from the smallest design:

- The first PR splits `MenuModel.build` into a structured model and a step that flattens it back into the menu, with a test that the menu is unchanged for every sample state and the 44 existing `MenuModelTests` passing with their bodies unchanged (section 8, step 1, says how).
- Quit when the icon is removed, as today: the `isInserted` binding's setter calls `terminate`.
- No polling of its own: one check when the window opens, then the menu's schedule.
- A strict list of controls: no pop-up button, context menu, SwiftUI `Menu` or toolbar.
- The window never opens at launch and is never restored.

Taken from the home design:

- Rename MacMoshKit's `Menu` type to `MenuLines` first, and log, in fixed words, which kind of object the menu-tracking signal carries, so a later filter can tell the menu-bar menu from anything else.
- The Remove confirmation reuses the exact sentence `removeDeskAsking` prints today, with a button named "Remove website".
- Under Locked, a greyed list of the desks from the last good check.
- Hide any control that needs a newer workhorse script until the report's script version is new enough.
- A CI check that no `window opened` line appears at launch.
- Try paste in a text field on the first day the window exists.

Dropped: home's "⋯" menus, its rerouting of menu lines, its in-window checklist, Fix and guided Add a Mac (they belong to issues #31 and #32 after his review), and its default-workhorse field before he says what a default does. Also dropped: the desk board's first idea of keeping the app running with no icon, its extra check on every focus change, and the smallest design's four buttons on every row.

## 7. The recommended design

### 7.1 What he sees

All names below are examples: a workhorse called **Attic**, and desks called api, blog, garden, notes, recipes and website.

#### A. Opening it

The menu gets one new line, **Open MacMosh**, just above **Quit MacMosh**. He clicks it. The window comes to the front, titled "MacMosh", showing what the menu last knew at once. One check starts, and "Checking…" shows beside the time until it lands.

```
┌─ MacMosh ──────────────────────────────────────────────────────────────────────┐
│                   │ Attic · Ready                                  [Check now]  │
│ ✓ Attic           │ Sign-ins working · Awake on power · Lid-closed mode on ·    │
│                   │ On power, 100%                              Checked 14:02   │
│ + Add a Mac…      │                                                             │
│                   │ Desks               [Open the 2 not in a tab] [New desk…]   │
│ ⚙ Settings        │ ─────────────────────────────────────────────────────────── │
│                   │ api        claude                  In 1 tab       [Open]    │
│                   │            ~/Development/api                                │
│                   │ blog       claude, zsh             In 1 tab       [Open]    │
│                   │            ~/Development/blog                               │
│                   │ garden     claude                  No tab         [Open]    │
│                   │            ~/Development/garden · Kept when it exits        │
│                   │ website    claude, zsh, vim        In 2 tabs      [Open]    │
│                   │    Folder:                     ~/Development/website        │
│                   │    Starts with:                claude --continue            │
│                   │    After a restart:            Comes back                   │
│                   │    When its last shell exits:  Remove the desk              │
│                   │    [New window]  [Rename…]  [Remove…]                       │
│                   │ notes      (closed)                               [Open]    │
│                   │            ~/notes · Kept when it exits                     │
│                   │ recipes    zsh                     No tab         [Open]    │
│                   │            ~/Development/recipes                            │
│                   │ ─────────────────────────────────────────────────────────── │
│                   │ [Share screen]  [Restart…]  [Turn off lid-closed mode…]     │
│                   │ [Run the checklist…]  Home address reachable from here: yes │
└───────────────────┴─────────────────────────────────────────────────────────────┘
```

- **The sidebar** lists each workhorse with its state symbol (the same symbol as the menu icon uses for that state), then "Add a Mac…", then "Settings". The first workhorse is selected. With no workhorses saved, the Add a Mac page is selected (agent's call, section 12).
- **The header** is the menu's headline (`Attic · Ready`), the menu's summary line, "Checked 14:02" and **Check now**.
- **Each desk row** shows the name, its window names (usually the program in each window), "In 1 tab", "In 2 tabs" or "No tab", and **Open**. The second line shows the folder, plus "Kept when it exits" for a permanent desk or "Doesn't come back after a restart" for the rare desk without reopen. The usual case is left unsaid, so rows stay short. Rows are in name order, with closed desks among them.
- **Clicking a row** (not its button) opens a detail strip under it with the folder, "Starts with", "After a restart", "When its last shell exits", "Keeps its command running" for a desk with the keep flag (the menu's ", kept running"), and **New window**, **Rename…** and **Remove…**. One row is open at a time.
- **Folders** are shown with `~` when they start with `/Users/<the workhorse's saved user>/`, and in full otherwise. The report has no home folder (section 5.2), so this needs no script change (agent's call, section 12).
- **A permanent desk with no session** shows "(closed)" and **Open**, which starts it again, exactly like the menu's `notes (closed)` line.
- **A desk not made with MacMosh** (no saved definition) shows "Not made with MacMosh: folder and restart not known" on its second line and the same buttons the menu gives it.
- **"Open the 2 not in a tab"** opens a tab on every running desk with no tab attached, one after another. It is hidden when every desk has a tab. In Apple's Terminal each one is a new terminal window (v1 design, call 20).
- **The rarer buttons** sit at the foot, in the menu's order and with the menu's words.
- **While a check runs**, everything stays as it was and "Checking…" shows beside the time. It never goes blank.

Closing the window changes nothing else. The menu and its checks carry on.

#### B. Making a desk for a new project that starts his agent

He clicks **New desk…**. A sheet opens.

```
┌─ New desk on Attic ─────────────────────────────────────────────────┐
│ Folder in ~/Development                          [Filter          ] │
│    api                          (has a desk)                        │
│    blog                         (has a desk)                        │
│  ▶ garden-planner                                                   │
│    recipes                      (has a desk)                        │
│    website                      (has a desk)                        │
│ Or a path, full or starting with ~:  [                            ] │
│                                                                     │
│ Name                [garden-planner                ]                │
│                     Letters, digits, - and _ only.                  │
│ Command to start    [claude --continue             ]                │
│                     Leave it empty for a plain shell.               │
│ After a restart     [✓] Comes back                                  │
│ When its last shell exits   (•) Remove the desk                     │
│                             ( ) Keep it, closed                     │
│ [✓] Open it in a tab now                                            │
│                                             [Cancel]  [Make desk]   │
└─────────────────────────────────────────────────────────────────────┘
```

He clicks "garden-planner". The name fills itself in. "Command to start" already holds the last command he used for a new desk on Attic. He presses Return. The button reads "Making…" for a second or two, the sheet closes, the row appears with "Updating…" until the next check lands, and a tab opens on the desk with his agent starting.

If the workhorse refuses, the sheet stays open with the reason under the button, for example "Attic already has a desk with that name. Pick another name." Section 7.5 has every field and default.

#### C. A desk he exited

He quits the agent and the shell in recipes, an ordinary desk. The workhorse removes it. At the next check its row leaves the list and an **Ended** group appears under the desks:

```
│ Desks               [Open the 1 not in a tab] [New desk…]   │
│ ─────────────────────────────────────────────────────────── │
│ api        claude                  In 1 tab       [Open]    │
│ …                                                            │
│ notes      (closed)                               [Open]    │
│            ~/notes · Kept when it exits                     │
│                                                             │
│ Ended                                                       │
│ recipes    ended about 15:10                                │
│            ~/Development/recipes · started with claude      │
│            [Start again]  [Start again and keep it]  [Forget]│
```

A desk counts as ended as soon as its session is gone, if it was open and not permanent in the previous Ready report. The window does not wait the minute until the script removes its definition (section 5.2). Rows already hide a non-permanent definition with no session, as the menu's `readyItems` does, so the desk moves from the list to Ended at one check. A desk without reopen that a workhorse restart closed also shows under Ended, which is useful; **Forget** clears it. (Agent's call, section 12.)

- **Start again** makes the same desk (same name, folder, command, "comes back" and "keep running" flags) and opens a tab on it. The script replaces a leftover line with the same name, so this works even before the definition is removed. It is off, with a one-line reason, when the name is taken by the script's rule (section 7.5).
- **Start again and keep it** does the same and marks it permanent, so the next exit leaves it closed instead of removing it. This is his "decide if the desk is ephemeral or permanent after exits", with no change on the workhorse.
- **Forget** takes the line away.

A permanent desk that exits stays in the list as "(closed)" with **Open**, as today. Changing a running desk between "removed" and "kept" before it exits needs a workhorse script change; that is decision 3 in section 10.

The Ended group lives in the app's memory only. It starts empty when MacMosh starts, so a desk that ended while MacMosh was not running is not listed. Desks he removes or renames from the window never show as ended. A desk removed with the menu's **Remove…** does show as ended: that line opens a terminal tab, and the app never learns whether he typed `yes`. The same is true of `macmosh desk remove` typed on the command line. Both false entries are accepted, **Forget** clears them, and section 11 watches for them (agent's call, section 12).

#### D. The workhorse locked after a restart

```
┌─ MacMosh ──────────────────────────────────────────────────────────────────────┐
│ 🔒 Attic          │ Attic · Locked after a restart                [Check now]   │
│                   │ The disk is locked until someone types the Mac's password.  │
│ + Add a Mac…      │                                                             │
│                   │ [Unlock disk…]  Opens a terminal tab. You type the Mac's    │
│ ⚙ Settings        │                 password there; MacMosh never sees it.      │
│                   │ [Run the checklist…]                        Checked 09:12   │
│                   │                                                             │
│                   │ Desks before the restart (checked 08:57)                    │
│                   │ These come back once it is unlocked and logged in:          │
│                   │ api, blog, garden, notes, website.                          │
│                   │ This one doesn't come back: recipes.                        │
└───────────────────┴─────────────────────────────────────────────────────────────┘
```

The hint is the menu's. When the Mac can't be unlocked over ssh, **Unlock disk…** is left out and the hint ends "Unlock it at the Mac.", as in the menu. Under "Can't verify it" there is no unlock button and no password line. The greyed list comes from the last check that found Attic Ready, held in memory; with none since MacMosh started, the list is left out.

The greyed list shows under every state other than Ready, whenever such a check exists (agent's call, section 12). Its heading fits the state. Under Locked it is the one drawn above. Under Waiting for login it reads "Desks before the restart (checked hh:mm)" and "These come back once someone logs in:". Under every other state it reads "Desks at the last good check (hh:mm)", with no promise about coming back. After the unlock, the page moves through "Waiting for login" (with **Log in…**, which opens Screen Sharing) and "Waiting for the desk server" to Ready by itself, as the menu does.

#### E. Adding a second workhorse

He clicks **Add a Mac…** in the sidebar. The page says what to switch on at the other Mac (Remote Login, and Screen Sharing for logging in after a restart) and has one button, **Add a Mac…**. In this design that button opens the same terminal tab as the menu (`macmosh pair`), because the first ssh asks for the other Mac's password. When pairing finishes, the next check adds the new Mac to the sidebar, for example "Not paired" with **Pair…** or "Needs setting up" with **Finish setting up…**, each opening the menu's tab. Task 28 later turns this page into its guided steps.

#### F. Changing a setting

```
│ ⚙ Settings │ This Mac                                                      │
│            │   Terminal            (•) Pick for me  ( ) iTerm2  ( ) Terminal│
│            │                                                               │
│            │ Attic                                                         │
│            │   Name                [Attic                      ]           │
│            │   Connection          (•) Mosh   ( ) Tabs   ( ) Plain ssh     │
│            │                       Mosh keeps a desk open through sleep    │
│            │                       and network changes. Use it unless it   │
│            │                       is blocked.                             │
│            │   Typing prediction   (•) Adaptive ( ) Always ( ) Never       │
│            │                       ( ) Experimental                        │
│            │   Projects folder     [~/Development              ]           │
│            │                       Saved. Used by the next New desk.       │
│            │   ▸ Advanced                                                  │
│            │   [Run the checklist…]  [Remove MacMosh from this workhorse…] │
```

Each change is saved when he leaves the field, through the same checks as `macmosh set`, with a grey line under it ("Saved. Used by the next New desk.") or a plain sentence saying what is wrong. Nothing here uses ssh. A save can't be lost to a background check that finishes at the same moment. Both go through `WorkhorseStore.update` under the store's lock, and the check's `absorb` writes only the seven report fields (section 5.2), never a setting from this page or `lastDeskCommand`. "Advanced" holds a different ssh key file. Under each connection choice is one line from the v1 design's "which one do I use?" table (section 5.4 there). **Run the checklist…** and **Remove MacMosh from this workhorse…** open the same terminal tabs as today (`prepare <id> --pause` and `remove <id>`), which list what they do and ask first.

### 7.2 Structure

#### Scenes (`Sources/MacMoshApp/MacMoshApp.swift`)

1. **The `MenuBarExtra` stays the first scene** but moves to the `isInserted` initializer [2], because Apple says the current one "should not be used in conjunction with other scene types" [1]. The binding's setter calls `NSApplication.shared.terminate(nil)` when it turns false, so removing the icon still quits the app, as today. The label's background-check task and the menu-tracking listener stay where they are.
2. **A new `Window("MacMosh", id: "main")`**, second, with `.defaultLaunchBehavior(.suppressed)` [4], `.restorationBehavior(.disabled)`, `.defaultSize` and `.windowResizability(.contentMinSize)`. It never appears at launch or login, only when asked for.
3. **No `Settings` scene and no `WindowGroup`.** No change to `LSUIElement`, the entitlements or the plist.

The **Open MacMosh** line in `MenuContent` is a plain SwiftUI `Button`, like Quit, not a `MenuItem`. It calls `openWindow(id: "main")` and then `NSApp.activate()` [6]. Because it is not a `MenuItem`, the CI log line `menu refreshed: symbol=plus.circle workhorses=0 lines=2` does not change: `MenuLog.refreshed` counts only `menu.items`, and Quit is not one of them either.

#### Controls allowed

Button, Text, TextField, Toggle, radio-group or segmented `Picker`, and `List`. **Not allowed** until the menu-tracking signal can be told apart: pop-up pickers, `contextMenu`, SwiftUI `Menu` and `.toolbar` (a toolbar "may" grow an overflow menu [10]). The layout is a sidebar list beside a detail page; the builder uses `NavigationSplitView` only if it adds no toolbar menu, otherwise a plain split of two views. A right-click in a text field still shows the system's edit menu; that causes one extra check and a misleading `menu opened` log line, not a wrong state, and the groundwork log line (section 8, PR 1) is what lets a later filter remove it.

#### Views (`Sources/MacMoshApp/Window/`, kept thin)

| View | What it shows |
|---|---|
| `MainWindow` | Sidebar plus the page for the selection (a workhorse id, Add a Mac, or Settings). The selection is remembered per viewer as a convenience; a lost value is harmless. |
| `Sidebar` | `Board.workhorses` (name and symbol), "Add a Mac…", "Settings". |
| `WorkhorsePage` | `StateHeader`, `DeskList`, `EndedDesks`, `StaleDesks` when not Ready and a last Ready result exists (headings in section 7.1 D), and `MoreButtons` (the rarer buttons, in the menu's order). |
| `StateHeader` | Headline, hint, summary line, "Checked hh:mm", "Checking…", Check now, and the last action's result line for this workhorse. |
| `DeskRow`, `DeskDetail` | The short row and the detail strip. |
| `NewDeskSheet`, `RenameSheet` | The two forms. |
| Remove | A `confirmationDialog`, not a view of its own (below). |
| `SettingsPage`, `AddMacPage` | Sections F and E. |

**Remove** shows the sentence `removeDeskAsking` prints today, for example "This removes the desk website and closes its 3 windows (claude, zsh, vim), with whatever is running in them.", with a destructive button "Remove website" and Cancel. Pressing "Remove website" is the explicit yes that the typed `yes` was. It then calls `DeskFlow.removeDesk(kill: true)`, which is what the menu's Remove does after a `yes`.

**Rename** is a sheet with one field, "New name for website", filled with the old name, and Rename and Cancel. It calls `DeskFlow.renameDesk(from:to:)`.

#### Data (`Sources/MacMoshKit/Board/`, pure and tested)

- `Board { workhorses: [BoardWorkhorse], symbol }`.
- `BoardWorkhorse { id, name, symbol, headline, hint, checkedAt, isChecking, summary, homeReachable, desks: [BoardDesk], ended: [EndedDesk], lastReadyDesks: [BoardDesk]?, lastReadyAt, buttons: [BoardButton], result: String? }`.
- `BoardDesk { name, isOpen, windowNames, windowCount, tabsOpen, folder?, command?, reopen?, keep?, permanent?, madeByMacMosh, buttons }`. Folder and flags come from `HostStatus.Definition`; a desk with none gets nil and `madeByMacMosh` false. The report has no home folder, so a folder that starts with `/Users/<Workhorse.user>/` is shown with `~/` in its place, and any other folder in full.
- `EndedDesk { name, folder, command?, reopen, keep, endedAt }`, so Start again can pass every flag back.
- `BoardButton { title, note?, action: BoardAction }`, where `BoardAction` is `.menu(MenuItem)` for anything the menu does (the menu's item, so it runs through `MenuRefresher.perform` exactly as the menu's does) or `.window(WindowAction)` for `newDesk`, `rename`, `remove`, `startAgain(keep:)`, `forget` and `openAllWithoutTab`.
- `ButtonRules`: the "which buttons for which state" rules moved out of `MenuModel.block` and `readyItems`. `MenuModel` and `BoardModel` both read them, so the menu and the window can't drift apart.
- `BoardModel.build(latest:, lastReady:, checking:, order:, waitingForDeskServer:, ended:, results:, now:, timeZone:) -> Board`. Pure, built from the same `CheckResult` the menu uses.
- `EndedDeskTracker`: compares a workhorse's previous Ready check with the new one. A desk whose session was open, whose definition was not permanent in the previous report, and whose session is now gone, is ended, whether or not its definition is still there (section 7.1 C). It keeps the name, folder, command, reopen, keep and the time it was first missed. It leaves out desks the window itself removed or renamed, and treats a new desk with the same folder and command as a rename made elsewhere. Memory only.
- `NewDeskForm`: the folder list with "(has a desk)" marks, the name made from the folder, `DeskName` validation, the taken-name check by the script's rule (section 7.5), the defaults, and the `NewDeskRequest` it produces.

#### Where the data comes from, and how often

There is still one `MenuRefresher` (the `@StateObject` in `MacMoshApp`), one schedule and one loop. It gains:

- `@Published latest: [String: CheckResult]`: the last real result per workhorse id, not replaced when a check comes back `.stillChecking`;
- `@Published lastReady: [String: CheckResult]`: the last Ready result per id, for the greyed list under Locked;
- `@Published checking: Set<String>` and `@Published isRefreshing`. `MenuData.gather` reports every workhorse at once (section 5.2), so every id goes into `checking` when a refresh starts. A workhorse leaves the set when it comes back `.checked`; one that comes back `.stillChecking` stays in it (agent's call, section 12);
- `@Published waitingForDeskServer: Set<String>`, read from today's private `DeskServerWait`;
- `@Published board: Board`, built beside the menu after each check.

The schedule stays the menu's: every 30 seconds while every workhorse answers; then 60, 120 and 300 seconds after misses; a second look 5 seconds after a first miss; one check at a time; a check when the menu opens and after every action. The window adds exactly one check, when it opens (`.task { await refresher.refresh() }` on `MainWindow`), plus **Check now**. It adds none on focus changes.

#### Actions in the window

A new `WindowActionRunner` in MacMoshKit runs the `.window` actions. It calls `DeskFlow` with a `QuietInteraction` (collects what `say` prints, answers every `ask` with nothing, ignores `waitForKey`), so nothing can wait on a question. Each action is one key-only, BatchMode ssh with stdin closed and a 15-second limit, to the address that last answered. While it runs, the button reads "Making…", "Renaming…" or "Removing…". When it ends, the runner:

1. writes one fixed-words log line;
2. calls a new refresher method, `finishWindowAction(id:result:)`, which sets that workhorse's result line (for example "Created the desk garden-planner on Attic.") and the menu's `notice`, so the menu shows it too if the window was closed meanwhile. `notice` stays `private(set)`; this method is the only other place that sets it (agent's call, section 12);
3. asks the refresher to check, and marks the row "Updating…" until that check lands.

The runner and the refresher belong to the App, not the window, so an action started just before the window closes still finishes.

**One action per desk at a time.** While a desk's action runs, that desk's buttons are off; other desks stay usable. One New desk runs per workhorse at a time, which the sheet already enforces. Actions on different desks may run together; each is its own key-only ssh call with a 15-second limit (agent's call, section 12).

**Controls that need a newer workhorse script** are hidden until the report's `scriptVersion` is new enough: **Rename…** needs 0.6.0, and "Keep it, closed" and **Start again and keep it** need 0.5.0 (section 5.2). The startup command needs no newer script.

#### When the window is closed

SwiftUI removes the views and cancels their task. Nothing else changes: the menu, its checks, `latest`, `lastReady` and the Ended list stay in the app. Reopening shows the last state at once and runs one check. An open sheet is lost with the window. Closing the window never quits the app, because the menu-bar item stays the first scene (to be confirmed on the daily Mac, section 11).

### 7.3 What is reused and what is new

**Reused unchanged:** `StatusChecker`, `CheckResult`, `MenuData.gather` and its 20-second budget, `PollSchedule`, `StateResolver`, `WorkhorseState`, `HostStatus` (desks, windows, definitions, power, battery), `StatusFormat.headline`, `hint` and `summaryLine`, `MenuModel.symbol(for:)` and `mostUrgent`, `Workhorse.canUnlockOverSSH`, the `MenuAction` and `MenuItem` vocabulary, `MenuActionRunner`, `AppTabs`, `TabOpener` and `TabCommand` with the iTerm2, Terminal and `.command`-file paths, `MenuRefresher.perform`, `HostCommands`, `DeskFlow` (`newDesk`, `renameDesk`, `removeDesk`, `newWindow`, `folders`), `NewDeskRequest`, `DeskName`, `WorkhorseStore` (`update` under its lock, `loadSettings`, `saveSettings`), `WorkhorseSetting.apply` and `applyTerminal`, `AppSettings`, `MenuLog` and its fixed-words rule, and the test stand-ins `FakeRunner`, `RecordingTabs`, `ScriptedInteraction`, `CheckResult.sampleReady()`, `HostStatus.sampleWithDesk` and `everySampleMenu()` (whose return type follows the rename to `MenuLines`). On the workhorse: nothing changes.

**New in MacMoshKit (tested with swift-testing):**

| File | What |
|---|---|
| `Menu/MenuLines.swift` | The model type `Menu` renamed `MenuLines` |
| `Board/ButtonRules.swift` | The state-to-buttons rules, read by `MenuModel` and `BoardModel` |
| `Board/Board.swift`, `Board/BoardModel.swift` | The window's model and its builder |
| `Board/EndedDeskTracker.swift` | Ended desks, in memory |
| `Board/NewDeskForm.swift` | The New desk form's rules |
| `Board/WindowActionRunner.swift` | In-window desk actions and settings writes |
| `Run/QuietInteraction.swift` | An `Interaction` that never waits |
| Changes to `Menu/MenuRefresher.swift` | `latest`, `lastReady`, `checking`, `isRefreshing`, `waitingForDeskServer`, `board`, and `finishWindowAction(id:result:)` |
| Changes to `Format/DeskFormat.swift` | Window wording without the `macmosh` command (for example "Pick another name." instead of "…remove it with: macmosh desk remove…"), and the Remove sentence moved out of `removeDeskAsking` so both use one function |
| Changes to `Model/Workhorse.swift` | `lastDeskCommand: String?`, optional, so older files still load. After each New desk made from the window's form, it is set to the command the form sent, and an empty command is saved as nil, so the next form opens empty. Start again does not change it. Used as the next form's default. Never logged. (Agent's call, section 12.) |
| Changes to `Menu/MenuLog.swift` | `window opened`; `window action: <kind> <result>`, the kind one of `newDesk`, `rename`, `remove`, `startAgain`, `setting` and `openAll`, the result `ok` or `failed`; `menu tracking: object=<kind>`, where the kind is one of four fixed words: `mainMenu` (the object is `NSApp.mainMenu`), `statusMenu` (the menu-bar item's menu), `popUp` (a pop-up button's menu) and `other`. It is chosen from the object's class and its relation to `NSApp.mainMenu`, never from a title. How the menu-bar item's menu is recognised is read on the daily Mac in step 3; until then it logs `other`. (Agent's call, section 12.) |

**New in the app target:** `Sources/MacMoshApp/Window/` with the views in section 7.2; the `Window` scene and the `isInserted` binding in `MacMoshApp.swift`; the **Open MacMosh** line in `MenuContent.swift`.

**New tests:**

- `BoardModelTests`, built from recorded reports through `HostStatus.parse`.
- `ButtonRulesTests`: for every sample state, the buttons the menu and the window share have the same titles in the same order. The menu's tab actions for `desk new`, `desk rename` and `desk remove --ask` are mapped to their `.window` counterparts (`newDesk`, `rename`, `remove`). The window-only buttons (Open the N not in a tab, Start again, Start again and keep it, Forget) are listed by name in the test, so a new one can't slip in unnoticed. (Agent's call, section 12.)
- A test that the flattened menu equals today's for every `everySampleMenu()` case, against a stored copy (section 8, step 1).
- `EndedDeskTrackerTests` (including a desk whose definition is still there, a no-reopen desk lost to a restart, and a permanent desk that closes), `NewDeskFormTests` (including the script's taken-name rule), `WindowActionRunnerTests` (`FakeRunner` shows the exact ssh arguments, including a startup command with spaces and quotes, and the keep flag passed through on Start again), `MenuRefresherTests` for keeping the last result while checking and for the `checking` set, and `MenuLogTests` with one case for each new line and each `menu tracking` word. A new fixture, `Tests/MacMoshKitTests/Fixtures/status/desks-board.txt`, has six desks, a permanent closed desk, a desk without reopen, a desk made by hand with no definition, and `def` lines in the current form with the permanent field.

**CI:** the smoke test keeps `lines=2`, and adds a check that no `window opened` line appears at launch.

### 7.4 Window, terminal tab or Screen Sharing

| Action | Where | Why |
|---|---|---|
| Open a desk, "Open the N not in a tab", Open a closed permanent desk | Terminal tab (`connect`) | The tab is the desk itself, run by mosh or ssh |
| Add a Mac…, Pair… | Terminal tab (`pair`) | The first ssh asks for the other Mac's password |
| Unlock disk… | Terminal tab (`unlock`) | The Mac's password goes to ssh |
| Restart… | Terminal tab (`restart`) | `sudo` on the workhorse asks for the password |
| Turn on or off lid-closed mode… | Terminal tab (`power … lid`) | `sudo pmset` asks for the password |
| Finish setting up…, Run the checklist… | Terminal tab (`prepare`) | Some fixes need a password or Homebrew's own installer; the checklist window is Task 29 |
| Fix… (Ready, sign-ins off) | Terminal tab (`prepare --restart-desk-server`) | No password, but it keeps the menu's "these desks will close" question until the checklist page exists |
| Remove MacMosh from this workhorse… | Terminal tab (`remove`) | It lists what goes and asks first; rare and destructive, so it stays as it is |
| Log in…, Share screen | Screen Sharing (`screen`) | The login password is typed into Screen Sharing |
| New window | Background helper (`desk window`), as the menu does | No password, no questions |
| New desk, Rename, Remove, Start again, Start again and keep it, Forget | In the window | Key-only ssh, nothing to type into a terminal; free text such as a startup command must take this path |
| Every setting, the terminal choice, Check now | In the window | Files on the daily Mac only, no ssh |

No window field ever takes a password, and MacMosh still never runs as root.

### 7.5 The New desk form

Title: "New desk on <workhorse>". It opens only from a Ready workhorse; for any other state the button is off and the state's hint says why. Fields, in order:

| Field | Default | Rules |
|---|---|---|
| **Folder**: the folders inside the workhorse's projects folder (`DeskFlow.folders`), with a filter box. Folders that already have a desk are marked "(has a desk)" but can be chosen. Below: "Or a path, full or starting with ~:" | Nothing chosen | Make desk stays off until a folder is chosen or typed. A typed path wins over the list. With no projects folder saved, the list is replaced by "Projects folder on Attic: [~/Development] [Save]", which saves the setting and fills the list. `DeskFlow.folders` and `HostCommands.folders` read the folder from the check's `CheckResult`, which was loaded before the save, so after Save the form hands `DeskFlow` a copy of that `CheckResult` whose workhorse is reloaded from `WorkhorseStore` (agent's call, section 12). If the list can't be fetched, the `DeskFormat` sentence shows and the path field remains. |
| **Name** | The folder's last part, made to fit: characters other than letters, digits, `-` and `_` become `-`, at most 64 | Checked as he types against `DeskName`, and against the last report by the script's own rule: a name is taken when a desk with that name is open, or a permanent desk holds it ("Attic already has a desk called api."). A leftover definition of an ended desk does not count, because the script replaces it (section 5.2). Start again uses the same rule. (Agent's call, section 12.) Help line: "Letters, digits, - and _ only." |
| **Command to start** | The last command this form sent for a new desk on this workhorse (`Workhorse.lastDeskCommand`), empty the first time or after a plain-shell desk | Sent exactly as typed, spaces and quotes included, through `NewDeskRequest.command`. Tabs and new lines are refused, as the script refuses them. Help line: "Leave it empty for a plain shell." |
| **After a restart: Comes back** | Ticked (his ruling: every new desk comes back) | Unticked sends reopen off (`--no-reopen`). |
| **When its last shell exits**: "Remove the desk" or "Keep it, closed" | Remove the desk (his ruling: ephemeral unless permanent) | "Keep it, closed" sets permanent (`--permanent`). |
| **Open it in a tab now** | Ticked | Afterwards the window runs the menu's `connect <id> <name>` tab. |

Not shown: "keep running" (`--keep`), whose command-line help still says "not active yet"; the form sends keep off. Start again still passes a desk's keep flag through, and the detail strip shows it.

"Keep it, closed" is hidden on a workhorse whose script is older than 0.5.0 (section 7.2).

Buttons: **Cancel** and **Make desk**; Return presses Make desk. While the desk is made, the sheet can't be dismissed and the button reads "Making…". On success the sheet closes. On failure it stays open with the reason under the button, and nothing is made.

The menu's `New desk…` keeps its terminal form; only the window uses this sheet.

### 7.6 How it relates to the menu

The menu stays. It is still the quick glance and the one-click actions, and it is how the window is opened. It gains the **Open MacMosh** line above **Quit MacMosh**, and it no longer keeps every other line word for word: it gets a submenu per desk (issue #107) and a line per window of a desk (issue #105), as the menu spec (`docs/superpowers/specs/2026-11-23-menu-submenus-design.md`) sets out. The first PR still proves with the existing tests that the menu is unchanged before those steps start. (Amended 2026-11-23; it read: "Its only change is the **Open MacMosh** line above **Quit MacMosh**. Every other line stays word for word, which the first PR proves with the existing tests.")

Both faces read one refresher and one set of button rules, so they always show the same state and the same buttons. Where they differ, the window does more: it shows folder, command and flags; it has forms where the menu has terminal questions; it keeps a desk's row while a check runs; and it has the Ended list and Settings.

Whether the menu's `New desk…`, `Rename…` and `Remove…` should later open the window's forms instead of terminal tabs is left until he has used both. (Amended 2026-11-23: after his request that "some of that stuff can move into the desktop app", the menu spec (section 6.5) has `Rename…` and `Remove…` leave the menu once this window's forms exist, with `New desk…` staying in it. Whether the menu's `New desk…` opens this window's form is still left until he has used both.)

### 7.7 How it relates to the plan, issue #99 and his review

| Item | What changes |
|---|---|
| **Task 21, his review (issue #24)** | This design goes into that review rather than past it. The v1 design says phases 3 to 5 "are checked again after Shariq's review of the first menu-bar item", and Tasks 28 and 29 are outlines whose steps that review writes. |
| **Task 29 (issue #32): Settings, New desk and the checklist window** | If decision 2 is "in this window", Settings becomes the window's Settings page and the New desk sheet becomes the window's form (section 7.5), so those parts of Task 29 are done here. The checklist window and "practise a restart" stay in Task 29, and later land as a page of this window. Task 29's outline of the New desk sheet ("a name and a folder") is out of date; section 7.5 replaces it. |
| **Task 28 (issue #31): Add a Mac** | Unchanged in content. Its guided steps later replace the single button on the Add a Mac page (section 7.1 E). Its two open points (pictures of the switches, practise a restart) stay with it. |
| **Task 30 (issue #33): notifications** | Unchanged and independent. |
| **Task 31 (issue #34): icon, About box and wording** | Its one pass over every word the app shows must include the window, so it comes after this work. |
| **v1 design, call 35** | The submenu per desk is now in the menu itself (issues #107 and #105, the menu spec). The window's detail strip still holds a desk's details and forms. (Amended 2026-11-23; it read: "The submenu per desk "belongs with the app's windows". The window's detail strip is that, so the menu needs no submenu.") |
| **Issue #99, a command line and MCP for agents** | Not built here. The pieces this adds to MacMoshKit (`Board`, `NewDeskForm`, `WindowActionRunner`, `QuietInteraction`) ask no questions, so a later agent command line can reuse them. Which actions an agent may take alone stays an issue #99 question. |
| **Issue #89's comment, bringing hand-made desks into MacMosh** | Not built. Such desks show as "Not made with MacMosh". Adopting them is a separate issue. |

**When the v1 text changes:** the agent coordinating the build makes these changes to the v1 plan and design (Task 29's New desk outline, call 35, and the order of Tasks 28 to 31) in one docs-only PR right after Shariq approves this design, before step 1, so each step's issue links to the updated plan (agent's call, section 12).

## 8. Order of work

Each step is one issue and one PR, tests first, with a build-log entry, as the plan requires.

0. **Before step 1, docs only:** the v1 plan and design changes listed in section 7.7.
1. **Groundwork, no visible change.** First, in a commit of its own before any refactor, store today's `MenuModel.build` output for every `everySampleMenu()` case as an expectation (titles, indents, actions and symbol, in a fixture or a literal). Then rename `Menu` to `MenuLines`, move the button rules into `ButtonRules`, and build the menu from a structured model plus a flatten step. Tests: the flattened menu equals the stored copy for every case, and the 44 tests in `MenuModelTests` pass with their bodies unchanged. The rename does touch test files: four helper signatures at the top of `MenuModelTests.swift` and `everySampleMenu()` in `Tests/MacMoshKitTests/Support/MenuSamples.swift` name the `Menu` type, and change to `MenuLines`. `MenuRefresher` publishes `latest`, `lastReady`, `checking`, `isRefreshing` and `waitingForDeskServer`, and keeps the last result while a check is still running. Add the `menu tracking: object=<kind>` log line. (Amended 2026-11-23: built as written, as issue #108, and merged as pull request #109, since Shariq chose "Start the window now, alongside the menu". Its tree is also the groundwork for the menu's submenus. Step 0's documents PR came after it, not before it. After it, the menu's steps (the script's labels, the submenus, then a line per window; menu spec, section 10) run beside steps 2 to 6 here. The submenus wait for step 1, and the menu lines that move into this window leave the menu only once steps 4 and 6 exist.)
2. **The board model, in MacMoshKit only.** `Board`, `BoardModel.build`, the new fixture, `BoardModelTests` and `ButtonRulesTests`. Still nothing visible.
3. **The window, read and click.** The `Window` scene (suppressed at launch, not restored), the `isInserted` initializer with quit on removal, **Open MacMosh** with `NSApp.activate()`, the sidebar, the workhorse page, short rows and the detail strip, "Open the N not in a tab", the greyed list under every non-Ready state (section 7.1 D), and every button through the menu's `MenuItem`. No pop-up, context menu, `Menu` or toolbar. The `window opened` log line and its CI check. **One sitting on the daily Mac** (section 11): it comes to the front, takes the keyboard, pastes into a text field, closing it keeps the menu running, and the tracking log line shows what object the menu-bar menu sends. This step alone meets issue #94's "done when", with the test correction in section 5.2.
4. **Desk forms in the window.** Starts only after step 3's sitting has shown that the window comes to the front and that paste works in its text fields, or after Shariq has chosen a fallback (section 11). `WindowActionRunner`, `QuietInteraction`, the New desk sheet (with `lastDeskCommand` and the inline projects folder), the Rename sheet, the Remove confirmation, per-action progress and result lines, and the window wording in `DeskFormat`.
5. **Ended desks.** `EndedDeskTracker`, the Ended group, Start again, Start again and keep it, Forget.
6. **The Settings page** (if decision 2 says so). The terminal choice and each workhorse's name, connection with its "which one do I use?" lines, typing prediction, projects folder and Advanced ssh key, saved through `WorkhorseSetting` and `WorkhorseStore.update`. Run the checklist… and Remove MacMosh from this workhorse… as today's tabs. "Show this Mac first" only if decision 4 asks for it.
7. **Only if decision 3 says so: switches on a running desk.** A `desk-set <name> [--permanent|--no-permanent] [--reopen|--no-reopen] [--command <text>]` subcommand in `host/macmosh-host` and its embedded copy, rewriting one `desks.tsv` line under the existing lock; the script's version goes to the next free version (amended 2026-11-23: this read "0.7.0", which is now the views of pull request #106, and 0.8.0 is the menu spec's labels); host tests against the throwaway tmux socket; `HostCommands.setDesk`; and in the detail strip, the "When its last shell exits" and "After a restart" choices and a "Change…" for the startup command. They show as plain text on a workhorse whose report says an older script. How that workhorse gets the new script is decision 6: today's code leaves it Ready, because the protocol number does not change (section 5.2).
8. **Only if decision 5 says so: a quiet-time line.** One added report record per tmux window carrying tmux's `window_activity` ("Time of window last activity", `man tmux`), and a line such as "Quiet for 12 min" per window. The parser already ignores record types it doesn't know, so an older app is unaffected. The new script reaches each workhorse as decision 6 says; if steps 7 and 8 are both wanted, they ship together as one script version.

Later, already filed: Add a Mac's guided steps (Task 28) and the checklist page (Task 29), as pages of this window.

## 9. Left to the builder

- The exact layout, spacing, column widths and window size, within the controls allowed in section 7.2.
- `NavigationSplitView` or a plain two-view split, whichever adds no toolbar menu.
- How the selected workhorse and the open detail row are remembered between openings (per viewer, harmless when lost).
- The exact symbol for each sidebar row, reusing the menu's symbols.
- How "Open the N not in a tab" spaces out its tabs, so iTerm2 or Terminal is not flooded.
- The wording of window-only lines (help lines, "Updating…", result lines), within plain words. Task 31's wording pass reviews them.
- How the Ended tracker matches a rename made outside the window, within the rule in section 7.2.
- Whether `.windowResizability(.contentMinSize)` or a fixed minimum suits the content.

## 10. Decisions for Shariq

Six questions, most important first. Each one changes what gets built. The first two are the ones issue #94 leaves open, and the sixth matters only if he picks 3b or 5b. Smaller points were settled by the agent and are listed in section 12 for him to check.

**1. Is this design approved, and when is it built?** (Issue #94: "Whether this goes in v1, after #31 and #32, or comes first after v1.") The v1 design says phases 3 to 5 "are checked again after Shariq's review of the first menu-bar item" (Task 21, issue #24), and the build log still lists that review as to come. The answer sets the order of the work, and whether Task 29's Settings and New desk parts are built here or as separate windows.

| Choice | What it means |
|---|---|
| **a. Approve; build after the Task 21 review, before issues #31 and #32 (recommended)** | This design goes into the Task 21 review as its main input. After the review, step 0 and steps 1 to 6 come next. Task 29's Settings and New desk parts become pages of this window; the checklist and Add a Mac land in it later. Nothing is built twice. |
| b. Approve; start steps 1 and 2 now, the rest after the Task 21 review | Steps 1 and 2 change nothing he can see (groundwork and the board model), so they can't get ahead of the review. Step 3 onward waits for it. Still before #31 and #32. |
| c. In v1, after #31 and #32 | Add a Mac and Settings are built as their own windows first, then the main window follows, and the Settings window is folded in or kept beside it. |
| d. First thing after v1 | v1 ships with the menu and the separate windows of Tasks 28 and 29; this waits. |

Recommended: a. His daily use is desks, which the window is built around, and adding a Mac happens once or twice in total. Waiting for the review keeps the plan's own rule; b is a fair choice if he wants the groundwork moving sooner.

**2. Settings: a page of this window, or a window of its own?** (Issue #94: "Whether Settings (#32) becomes part of this window instead of a window of its own.")

| Choice | What it means |
|---|---|
| **a. A page of this window (recommended)** | "Settings" in the sidebar, with the terminal choice and a section per workhorse (section 7.1 F). |
| b. A window of its own | A second window to find and bring forward, in an app with no Dock icon. A SwiftUI Settings scene would have no menu to open it from [8], so it would be another `Window` opened from a menu line. |

Recommended: a. He asked for one place to "configure/see what's going on", and each workhorse's settings sit beside its desks.

**3. "Decide ephemeral or permanent after exits": how far?**

| Choice | What it means |
|---|---|
| **a. The Ended list only (recommended for now)** | Start again, or Start again and keep it, after a desk ends. No workhorse change. Ended desks are remembered only while MacMosh runs. |
| b. The Ended list, plus a switch on each running desk | Step 7: a new `desk-set` subcommand in the workhorse script, with host tests, and a script update on each workhorse (how it gets there is decision 6). Also lets him change a desk's startup command and "comes back" later. |
| c. The Ended list, remembered across MacMosh restarts | Ended desks are saved in a small file on the daily Mac, so one that ended overnight is still listed in the morning. No workhorse change, but it replaces the "memory only" rule in section 7.1 C. |

Recommended: a first, then b if he finds he wants to decide before the exit rather than after it.

**4. "Set target" and "the default workhorse": what should it do?**

| Choice | What it means |
|---|---|
| **a. Nothing yet (recommended while there is one workhorse)** | With one workhorse there is nothing to choose. The question comes back when he adds a second. |
| b. Which Mac is shown first | "Show this Mac first" in Settings: the window opens on it and the menu lists it first. It rewrites the saved list's order, so it changes the menu's order too. |
| c. Also the Mac the `macmosh` command uses when none is named | b, plus a saved default and changes to the commands (for example `macmosh connect website` with no workhorse). |

Recommended: a, then b when a second workhorse arrives.

**5. "What's running": how deep?**

| Choice | What it means |
|---|---|
| **a. Window names and the startup command (recommended)** | What the report already carries. A window's name is usually the program running in it. No workhorse change. |
| b. Also a quiet-time line per window | Step 8: "Busy now" or "Quiet for 12 min" from tmux's last-activity time, to spot an agent waiting for him. One new report record and a script update on each workhorse (decision 6). |

Seeing whether an agent is working or waiting for certain is not offered either way; that means reading a desk's screen, which issue #99 leaves open.

Recommended: a, and b later if he finds himself checking desks for a waiting agent.

**6. Only if he picks 3b or 5b: how does a workhorse with the older script get the new one?** Steps 7 and 8 keep protocol 1, and today a workhorse is "Needs setting up" only when the protocol number differs (section 5.2). So with today's code, a workhorse running a script without `desk-set` stays Ready after the app ships the version that has it, and only the checklist notices the older version. (Amended 2026-11-23: this read "script 0.6.0" and "0.7.0"; 0.7.0 is now the views of pull request #106 and 0.8.0 the menu spec's labels.) The choice changes what he sees in the menu, so it is his.

| Choice | What it means |
|---|---|
| **a. Keep today's rule; the window says what to do (recommended)** | The menu does not change. On a workhorse with the older script, the new switches show as plain text with one line under them: "These need a newer workhorse script." and an **Update the script…** button. It opens the same tab as the menu's Finish setting up… (`prepare <id> --fix --pause`), whose automatic fixes replace an older script and say so first. |
| b. A version rule in `StateResolver` | A report from a script older than the one built into the app makes the workhorse "Needs setting up", with **Finish setting up…** in the menu and the window. Every later script update then shows in the menu once, on every workhorse, until it is installed. |

Recommended: a. It keeps the menu word for word (an anti-goal in section 4), and the switches are only a convenience. Choose b if he would rather be told in the menu whenever a workhorse has an older script.

## 11. What is not known yet

| Unknown | Why it matters | How it is settled |
|---|---|---|
| Whether `openWindow` plus `NSApp.activate()` brings the window in front of iTerm2 and gives it the keyboard, in an app with no Dock icon | Apple says activation is only a request [6] | Tried on the daily Mac in step 3, before any form work. If it stays behind, the fallback is showing a Dock icon while the window is open (`setActivationPolicy` [7]), which Apple does not document as a pattern; that becomes a question for Shariq then. |
| Whether paste, copy and close shortcuts work in the window's text fields without an app menu bar | Pasting a startup command matters | Tried in the same sitting. Same fallback. |
| Whether closing the window keeps the app running | Apple says a `Window` as the primary scene quits the app on close [3], and does not say how the primary scene is chosen | Tried in the same sitting. The menu-bar item is the first scene, which is expected to keep the app running. |
| What object `NSMenu.didBeginTrackingNotification` carries for the menu-bar menu | Needed to filter out menus inside the window | The step 1 log line, read on the daily Mac. A filter follows in its own small PR; until then the control rules in section 7.2 apply. |
| Whether `MacMoshKit.Menu` clashes with SwiftUI's `Menu` | A build failure in the first view | Avoided by renaming it in step 1. |
| What tmux names a window running his agent (for example `claude`, or the name of the program underneath it) | The rows show it | Read from the report on the workhorse during step 3, read-only. If the name is unhelpful, the row can fall back to the startup command. |
| Whether `removeDesk(kill: true)` after the window's confirmation matches `--ask` in every case (for example a desk that closed between the check and the click) | Remove must never hit the wrong desk | `WindowActionRunnerTests`, and the script already addresses desks by session id (v1 design, call 38). |
| Whether the Ended tracker shows false entries in real use (a desk removed with the menu's Remove… or from the command line, where the app can't tell whether he typed `yes`) | A wrong "ended" line is confusing | Watched during his first days with step 5; "Forget" clears one. If they are common, skipping a desk whose menu Remove… was clicked in the last few minutes is a small follow-up. |
| Whether the `isInserted` setter is called when the icon is dragged out of the menu bar | Quit on removal depends on it | Tried in step 3. |

## 12. Smaller calls the agent made, for Shariq to check

A builder's review raised these points. None changes what gets built enough to need his decision, so the agent settled each one in the sections named. Each is marked "agent's call" there. Any he disagrees with is a one-line change to this document.

| Point | The call | Where |
|---|---|---|
| What counts as an ended desk | Its session is gone and it was not permanent in the previous Ready report; the window does not wait for the script to remove its definition. A no-reopen desk lost to a restart shows as ended too. | 7.1 C, 7.2 Data |
| A desk removed with the menu's Remove… | Shows as ended, because the app can't tell whether he typed `yes`. Forget clears it; section 11 watches for it. | 7.1 C, 11 |
| Shortening folders with `~` | Replace a leading `/Users/<the workhorse's saved user>/` with `~/`; otherwise show the full path. No script change. | 7.1 A, 7.2 Data |
| Which desk names are taken | The script's rule: an open desk, or a permanent one. Used by New desk and Start again. | 7.5 |
| The folder list after the inline projects-folder Save | DeskFlow gets a copy of the check with the workhorse reloaded from the saved list. | 7.5 |
| Setting the menu's notice from the window | A new refresher method, `finishWindowAction(id:result:)`. | 7.2 Actions |
| What `ButtonRulesTests` compares | The shared buttons' titles and order; the menu's tab forms of New desk, Rename and Remove map to the window's forms; window-only buttons listed by name. | 7.3 |
| The greyed list of desks | Under every non-Ready state that has a last Ready result, with a heading that fits the state. | 7.1 D, 7.2 Views |
| The keep-running flag | Shown in the detail strip as "Keeps its command running", and passed through by Start again. The New desk form still sends it off. | 7.1 A, 7.2 Data, 7.5 |
| What `lastDeskCommand` saves | What the form sent, with an empty command saved as nil. Start again does not change it. | 7.3 |
| Proving the menu is unchanged in step 1 | Store today's output in a commit before the refactor, and compare against that copy. | 8, step 1 |
| The window with no workhorses | It selects the Add a Mac page. | 7.1 A |
| The per-workhorse "Checking…" | Every id when a refresh starts; each leaves when it comes back checked. | 7.2 Data |
| Two window actions at once | One per desk; that desk's buttons are off while it runs, the others stay usable. | 7.2 Actions |
| The words in `menu tracking: object=<kind>` | `mainMenu`, `statusMenu`, `popUp` and `other`, never a title, one test each. | 7.3 |
| When the v1 plan and design text change | A docs-only PR right after approval, before step 1. | 7.7, 8 |

## 13. Sources

Apple pages were read on 2026-11-23 through the data endpoint behind each page (`https://developer.apple.com/tutorials/data/documentation/<path>.json`).

1. MenuBarExtra `init(content:label:)`: https://developer.apple.com/documentation/swiftui/menubarextra/init(content:label:)
2. MenuBarExtra `init(isInserted:content:label:)`: https://developer.apple.com/documentation/swiftui/menubarextra/init(isinserted:content:label:) ; MenuBarExtra: https://developer.apple.com/documentation/swiftui/menubarextra
3. Window: https://developer.apple.com/documentation/swiftui/window ; openWindow: https://developer.apple.com/documentation/swiftui/environmentvalues/openwindow
4. Scene launch behaviour, suppressed: https://developer.apple.com/documentation/swiftui/scenelaunchbehavior/suppressed ; defaultLaunchBehavior: https://developer.apple.com/documentation/swiftui/scene/defaultlaunchbehavior(_:) ; restorationBehavior: https://developer.apple.com/documentation/swiftui/scene/restorationbehavior(_:)
5. Activation policy, accessory: https://developer.apple.com/documentation/appkit/nsapplication/activationpolicy-swift.enum/accessory ; LSUIElement: https://developer.apple.com/documentation/bundleresources/information-property-list/lsuielement
6. NSApplication `activate()`: https://developer.apple.com/documentation/appkit/nsapplication/activate()
7. NSApplication `setActivationPolicy(_:)`: https://developer.apple.com/documentation/appkit/nsapplication/setactivationpolicy(_:)
8. Settings scene: https://developer.apple.com/documentation/swiftui/settings
9. NSMenu `didBeginTrackingNotification`: https://developer.apple.com/documentation/appkit/nsmenu/didbegintrackingnotification
10. Toolbar item placement: https://developer.apple.com/documentation/swiftui/toolbaritemplacement
11. View `task`: https://developer.apple.com/documentation/swiftui/view/task(name:priority:file:line:_:)
12. Confirmation dialog: https://developer.apple.com/documentation/swiftui/view/confirmationdialog(_:ispresented:titlevisibility:actions:message:)
13. tmux: local `man tmux`, options `automatic-rename` and format `window_activity`.
14. Issues: #94 (this window), #99 (a command line and MCP for agents), #89 and #87 (desks that come back, ephemeral desks), #93, #95 and #98 (Remove, Rename, the command question), #24 (Task 21 review), #31 (Task 28), #32 (Task 29), #33 (Task 30), #34 (Task 31), #91 (heat).
15. The v1 design: `docs/superpowers/specs/2026-11-18-macmosh-v1-design.md`, sections 1 to 7, 12 and 13 (calls 20, 26 to 39). The v1 plan: `docs/superpowers/plans/2026-11-19-macmosh-v1.md`, Tasks 21 and 28 to 31. `docs/first-run-notes.md`.
16. Code read for this design: `Sources/MacMoshApp/MacMoshApp.swift`, `MenuContent.swift`; `Sources/MacMoshKit/Menu/` (`MenuModel`, `MenuRefresher`, `MenuActionRunner`, `MenuLog`, `PollSchedule`, `MenuData`); `Sources/MacMoshKit/Host/` (`HostStatus`, `HostCommands`, `DeskFlow`); `Sources/MacMoshKit/Format/` (`StatusFormat`, `DeskFormat`); `Sources/MacMoshKit/Model/` (`Workhorse`, `WorkhorseStore`, `AppSettings`); `Sources/MacMoshKit/Setup/WorkhorseSetting.swift`; `Sources/MacMoshKit/Terminal/TabCommand.swift`; `Sources/MacMoshKit/SSH/SSHInvocation.swift`; `host/macmosh-host` (`cmd_desk_closed`, `cmd_status`); `App/Info.plist`; `Tests/MacMoshKitTests/` (`MenuModelTests`, `AppBundleTests`, `Fixtures/status/full.txt`); `.github/workflows/ci.yml`.
