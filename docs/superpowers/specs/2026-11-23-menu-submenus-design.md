# MacMosh menu: submenus, a line per window, and going to the right tab

Status: the design to build for issues #107 and #105 (part 2). Written: 2026-11-23, from Shariq's requests of that day, a trial of submenus on GitHub's macOS 15 and macOS 26 runners, and the coordinating agent's decisions after it. (changed 2026-11-23) When first written, nothing here was built. Since built: S1 (pull request #115), the script's labels (#116), the daily Mac's side of a tab on one window (#119), the two tab actions (#123), and S2's menu, a line per window behind the gate, with the summary one fact per line (issue #124); where they differ from the text, the text says so, marked "(changed 2026-11-23)". Section 12 lists the smaller calls the agent made, for Shariq to check. Repo: `shariqh/macmosh`.

This document adds to the v1 design (`docs/superpowers/specs/2026-11-18-macmosh-v1-design.md`, "the v1 design") and to the main-window design (`docs/superpowers/specs/2026-11-23-main-window-design.md`, "the main-window design"). Both carry dated amendments that point here.

The layout started from a design that a reviewing agent joined from three independent drafts, called "the base design" below. It is not kept in the repository. Where the trial changed it, this document says so.

## 1. The short version

The menu gets one row per desk. Resting the pointer on a desk's row opens a submenu with that desk's windows and actions. Clicking the row opens the desk, or takes him to its tab if it already has one. The workhorse's rarer lines (Share screen, Restart…, the lid-closed switch, the power summary, Run the checklist…) move into a submenu under the workhorse's own row. Each window of a desk gets its own line, and clicking that line brings forward the terminal tab that shows it, or opens one. `New window` opens in a tab of its own, so the tab he was using keeps showing what it showed.

With one workhorse called Attic and six desks, the menu reads:

```
Attic · Ready                              ▸
   website · 3 windows, 2 in tabs          ▸
   api · 2 windows                         ▸
   notes · 1 window, in a tab              ▸
   blog · 1 window                         ▸
   shop · 2 windows, 1 in a tab            ▸
   garden (closed)                         ▸
   New desk…
─────
Add a Mac…
Check now
─────
Quit MacMosh
```

`▸` marks a row that opens a submenu. With six desks the top level drops from 35 rows today (six open desks, section 3) to 11 (both counts leave out Quit and include the separator above Add a Mac…). While the menu is open and shows submenus, it holds still: a background check never changes it under his pointer, and what the check found shows the next time he opens it.

## 2. Words used

The v1 design's words (its section 2) and the main-window design's (its section 2) still hold. This design uses four of them closely:

| Word | Meaning here |
|---|---|
| **Desk** | A persistent terminal session on the workhorse, kept by tmux (the terminal multiplexer that keeps programs running when no terminal is attached). One per project. |
| **Window** | A tmux window inside a desk: one program, such as his AI agent or a shell. "website · 3 windows" means three. |
| **Tab** | A terminal tab on the daily Mac that shows one window of a desk. In Apple's Terminal each one is a terminal window (v1 design, call 20). |
| **View** | A small tmux session that one tab uses, joined to its desk so it shares the desk's windows but keeps its own current window. Pull request #106 adds them. "View" is a word for the code and these documents only. It never appears on screen. |

Three more names are used below:

- **Label**: a short random word, 16 lowercase hex characters such as `9f3a1c2e5b7d4a60`, that MacMosh gives each tab it opens, so it can find that tab again. (Corrected on 2026-11-23 from 8: the script doesn't check that labels are unique, so the daily Mac makes them longer; v1 design, call 50.)
- **Tab record**: a small file on the daily Mac, one per tab, that says which tab (by its terminal device) carries which label.
- **Primary action**: what a row with a submenu does when it is clicked, as opposed to when the pointer rests on it.

No line on screen says view, session, pane or tmux.

## 3. Why

On 2026-11-23 Shariq wrote, about the menu (issue #107):

> "the menubar is kinda messy once i have things running. can we do submenu items where it makes sense? and some of that stuff can move into the desktop app where it makes sense as you get that ready."

The same day, after `New window` took over the tab he was using, he said (issue #105):

> "I opened a new window in an existing desk and it just took over the desk window that was already open and I don't know how to switch between the two windows within that desk now."

> "I think I'd prefer it to be able to be open as a new tab, and then the user can click and drag the tabs to make it side by side, similar to iTerm2 today."

And when he approved that proposal:

> "build it and also update the menubar to show each tab in a session as a line item so i can click on it and it takes me to the right tab"

Today the menu shows one flat list (`Sources/MacMoshKit/Menu/MenuModel.swift`; `readyItems` at commit 2b9075b, built as a tree and flattened since step 1). Each open desk takes four rows: its title, `New window in <name>`, `Rename <name>…` and `Remove <name>…`. With one workhorse and six open desks that is 35 rows: the headline, 24 desk rows, six workhorse rows (New desk…, Share screen, Restart…, the lid-closed switch, the summary line and the home-address line), Run the checklist…, a separator, Add a Mac… and Check now. A line per window would make it longer still.

## 4. Constraints

### 4.1 What Shariq has ruled

| Ruling | His words, where recorded | What it means here |
|---|---|---|
| Submenus where they make sense; some lines move into the window later | "can we do submenu items where it makes sense? and some of that stuff can move into the desktop app where it makes sense as you get that ready." (2026-11-23, #107) | One row per desk, rare lines under the workhorse's row; Rename, Remove and the rare workhorse lines leave the menu once the window has them (section 6.5). |
| A line per window that takes him to its tab | "update the menubar to show each tab in a session as a line item so i can click on it and it takes me to the right tab" (2026-11-23, #105) | Window lines inside each desk's submenu; a click selects the tab that shows that window (section 8). |
| A new window opens in a tab of its own | "I think I'd prefer it to be able to be open as a new tab" (2026-11-23, #105) | `New window` opens a tab on a new window; other tabs keep what they show. |
| Opening a desk with several windows and no tab opens one tab per window; closing a tab leaves its program running and the menu still lists that window; clicking a desk whose windows all have tabs brings its tab to the front | He changed none of these three proposals in #105 on 2026-11-23, so they stand | The first line of a desk's submenu, and the desk row's click (section 6.2). |
| The main window starts now, beside the menu | "Start the window now, alongside the menu" (2026-11-23, on the board) | The order of work in section 10. |
| No third-party app or library a user must install | "i don't want third party dependency can we not make a native menu bar item instead" (2026-11-19) | SwiftUI and AppKit only; the terminals are driven by AppleScript, as today. |
| Plain words in everything the person reads | v1 design, section 11 | No tmux words on screen. |

### 4.2 What the code imposes

Read from the repository at commit 2b9075b, and from pull request #106's branch where it says so. Two pull requests merged after that reading: #106 (commit c52bb50) and main-window step 1, #109 (commit eb77d6c). Where they change a fact below, it says so; the line numbers given are those of eb77d6c.

- **The menu model.** At 2b9075b it was flat: `MenuItem` has a title, an action, an indent and a separator flag, and no children or id (`MenuModel.swift`). Step 1 of the main window (issue #108, merged as pull request #109) now builds the menu as a tree of `MenuEntry` (an id, a title, an action, a separator flag and children) and flattens it into `MenuItem`s, with no visible change (`Sources/MacMoshKit/Menu/MenuLines.swift`). That tree is what this design draws as submenus.
- **The view keys rows by position.** `MenuContent` draws `ForEach(items, id: \.offset)` (`Sources/MacMoshApp/MenuContent.swift:18`).
- **The "menu opened" signal.** The app's label listens for `NSMenu.didBeginTrackingNotification` and calls `MenuRefresher.menuOpened()` each time (`Sources/MacMoshApp/MacMoshApp.swift:33`). There is no listener for the end of tracking.
- **CI counts lines.** The log line `menu refreshed: … lines=<n>` counts `menu.items` (`MenuLog.swift:31`). CI expects `menu refreshed: symbol=plus.circle workhorses=0 lines=2` (`.github/workflows/ci.yml:52`), and `MenuRefresherTests` expects `lines=6` for the waiting state (line 300).
- **Every action argument is plain characters.** `TabCommand` requires every element to match `^[A-Za-z0-9@%+=:,./_-]+$` (`TabCommand.swift:10`). A window id such as `@3` and an 8-character hex label pass.
- **Tabs open in the app's own process.** A `.tab` action opens a terminal tab through `osascript` from the app (`TerminalLauncher.swift:40`), the route that holds the Automation permission since sitting 1. A `.run` action runs the bundled helper in the background with a 30-second limit (`MenuActionRunner.swift:17`).
- **Today's `New window`** runs `desk window` in the background, with no tab (`Sources/MacMoshKit/Board/ButtonRules.swift:76`, since step 1; `MenuModel.swift:198` at 2b9075b), and the workhorse makes the new window the desk's current one, which is what took over his tab.
- **Connecting passes one argument.** The mosh line is `/bin/sh -c 'exec "$HOME/.macmosh/macmosh-host" attach "$1"' macmosh-host <desk>` (`ConnectPlanner.swift:61`). Tabs mode needs iTerm2 (`ConnectRunner.swift`, `TERM_PROGRAM != "iTerm.app"`).
- **The report already carries a script version.** `HostStatus.scriptVersion` (`HostStatus.swift:79`). Unknown record types are skipped, so an older app ignores new ones.
- **A parsed window has no id.** `HostStatus.Window` has only an index and a name.
- **Tests can use a temporary folder.** `Paths.standard()` honours `MACMOSH_SUPPORT_DIR`.
- **The script's version rule.** "any change to `host/macmosh-host` raises `MACMOSH_HOST_VERSION` and re-runs `scripts/embed-host-script.sh`" (v1 plan, "Every task", rule 8).
- **Pull request #106 (merged on 2026-11-23 as commit c52bb50)** made the script 0.7.0 with views: `attach [--cc] [--window @<id> | --new-window] [--dry-run] <desk>`, a view named `<desk>+<pid>` and tagged with the tmux option `@macmosh-view`, and two new report records after each desk's windows: `windowinfo` (desk, index, window id, whether the desk's own session shows it, how many tabs show it) and `view` (desk, view name, the window it shows, its tabs). An older script refuses an unknown option (`--*) mm_usage_error attach "unknown option $1"`).

### 4.3 What Apple's frameworks and the terminals document

Apple's pages were read on 2026-11-23 through the data endpoint behind each page. The terminals' scripting dictionaries were read with `sdef`, the macOS command that prints an app's scripting dictionary: the list of commands and properties the app accepts from AppleScript.

| Fact | The exact words | Source |
|---|---|---|
| A submenu is a `Menu` inside a `Menu` | "Create submenus by nesting Menu instances inside others. Use a Divider view to create a separator between menu elements." | [3] |
| The same, from the adaptive-controls article | "inserting a `Button` in the menu's closure renders an actionable menu item, while inserting a `Menu` creates a submenu item." | [2] |
| A `Menu` can have a primary action | "The primary action will be performed when the user taps or clicks on the body of the control, and the menu presentation will happen on a secondary gesture, such as on long press or on click of the menu indicator." | [1] |
| Apple does not promise the same look everywhere | "the system may display the menu differently depending on the device." | [2] |
| The menu style of a menu-bar item | "A menu bar extra style that renders its contents as a menu that pulls down from the icon in the menu bar." | [4] |
| The default style, as documented | "The default menu bar extra style." Nothing more: the page does not say it is the same as the menu style. | [4] |
| A menu-bar item shows a menu | "Display a menu — not a popover — when people click your menu bar extra." | [6] |
| Use submenus sparingly | "Use submenus sparingly. Each submenu adds complexity to the interface and hides the items it contains." | [5] |
| One level, about five items | "it's generally best to restrict them to a single level. Also, if a submenu contains more than about five items, consider creating a new menu." | [5] |
| Frequent items first; an ellipsis when more is needed | "Prefer listing important or frequently used menu items first. … Append an ellipsis to a menu item's label when the action requires more information before it can complete." | [5] |
| A submenu stays openable | "Make sure a submenu remains available even when its nested menu items are unavailable." | [5] |
| The tracking signal's object, as documented | "The notification object is the main menu bar (`[NSApp mainMenu]`) or the root menu of a popup button. This notification does not contain a `userInfo` dictionary." | [7] |
| The end of tracking | "Posted when menu tracking ends, even if no action is sent." | [8] |
| Row ids must stay stable | "It's important that the `id` of a data element doesn't change, unless the data element has been replaced with a new data element that has a new identity." | [9] |
| iTerm2: bring a window forward | "select Gives the window keyboard focus and brings it to the front." | [10] |
| iTerm2: select a tab | "select Selects the tab, making it the current tab for the window." | [10] |
| iTerm2: select a session | `<command name="select" code="Itrmslct" description="Make receiver visible and selected.">` | [12] |
| iTerm2: a session's tty | "tty The name of the session's tty (e.g., /dev/ttys01). Returns a string." | [10] |
| iTerm2's session id is shown only by example | "The sessionid parameter takes the value of the session's ITERM_SESSION_ID environment variable (for example, w0t0p0:ABCD-EFGH-... )." | [11] |
| Terminal: a tab's tty and whether it is selected | "The tab's TTY device." and "Whether the tab is selected." | [13] |
| Terminal: a window's order and whether it is minimized | "The index of the window, ordered front to back." and "Whether the window is currently minimized." | [13] |
| Terminal: `do script` runs in an existing tab or window | "Runs a UNIX shell script or command." with the parameter `in`, "The tab in which to execute the command" (type tab, window or any), and the result "The tab the command was executed in." | [14] |
| A process can learn its terminal device | "The ttyname() function gets the related device name of a file descriptor for which isatty() is true." | [15] |
| A process can be checked without a signal | "A value of 0, however, will cause error checking to be performed (with no signal being sent). This can be used to check the validity of pid." | [15] |
| tmux user options | "tmux also supports user options which are prefixed with a '@'." | [15] |

Two things are not documented anywhere read for this design: that iTerm2's AppleScript session id equals the part of `ITERM_SESSION_ID` after the colon, and that a terminal device name (`/dev/ttys005`) is never reused by a later tab. So MacMosh matches tabs by their terminal device only while the process that recorded it is still alive (section 8).

## 5. What the trial showed

### 5.1 How it was run

A throwaway menu-bar app (`SubmenuTrial`, on the branch `trial-submenus`, not merged and kept as evidence) ran on GitHub's macOS 15 runner (macOS 15.8.2, 24H232) and macOS 26 runner (macOS 26.7.2, 25G332), in five runs [16]. The five runs were made at commits 1bf410d, 43bdae6, 3e760b4, 8dd4fc7 and 949f02d, in that order; 949f02d is the branch's last commit. The trial app never ran on Shariq's Macs; only its build did.

**No person touched it.** The pointer moves, clicks and key presses were posted by a tool (`trialtool`) as CGEvents (the low-level mouse and key events macOS delivers to apps) at the system's event tap. In the first phases, System Events (macOS's scripting route into other apps' controls) sent key codes and opened the menu with an accessibility press (AXPress) on the menu-bar item. From run 1's pointer section on, the menu was opened with a posted click. None of it was a person on a trackpad or a physical keyboard. The app logged every menu notification, every button and primary action, and every model change. A window list sampled every 50 ms showed when a submenu opened and closed. The runner's screen is 1024 × 768 at scale 1, and the screenshots do not draw the pointer.

A second agent re-read the logs, the screenshots and the trial's code, and narrowed several of the first agent's conclusions. The tables below use the narrower wording wherever the two disagreed.

### 5.2 Does a nested `Menu` show as a submenu?

| | |
|---|---|
| macOS 15 | Yes. The row has a right chevron. It opens when the posted pointer rests on it, and about 0.25 s after the keyboard highlight reaches the row. The right arrow then moves the highlight into it; the left arrow closes it. The default style and `.menuBarExtraStyle(.menu)` gave the same 27-item tree. |
| macOS 26 | The same. Rows are 24 px tall, against 22 px on macOS 15. |
| How it was shown | Posted pointer moves, System Events key codes, the app's `NSMenuWillOpenNotification` and `NSMenuDidCloseNotification` lines, the window list, and screenshots (run 1). |
| Not shown | The right arrow opening a submenu that was closed: in every keyboard sequence the submenu was already open. Whether the default style is the same configuration as `.menu`: both were run and behaved the same, but Apple documents the default only as "The default menu bar extra style." [4], so that is not documented. The daily-Mac tries use MacMosh's own style. Which side a submenu opens on: it opened to the left in run 1 and to the right in runs 4 and 5, and the cause was not shown. A real trackpad or keyboard. |

### 5.3 Can a row with a submenu also act on a click?

| | |
|---|---|
| macOS 15 | A posted pointer resting on the row opened its submenu. A posted click on the row, made after the pointer had rested there about 1.5 s with the submenu open, closed the submenu, ran the primary action, and closed the whole menu (`app primary action desk=workhorse`, then `menuWindows=0`). Return on the highlighted row ran the primary action and closed the menu; in that sequence the submenu had been opened and closed again with the left arrow first. An accessibility press (AXPress) on the row did not run the primary action: it only opened the submenu, and the menu stayed open. |
| macOS 26 | The same on every point. |
| How it was shown | Posted pointer events and System Events key codes, one click per macOS version per style; the app's log and screenshots (run 1). |
| Not shown | A click that arrives before the submenu has opened. A tap or a press on a real trackpad, and a force click. Return while the submenu is still open. |

### 5.4 How do text lines, dividers and indented lines behave?

| | |
|---|---|
| macOS 15 | A `Text` line is grey, like a disabled row. The keyboard skips it, the pointer highlights nothing, and a posted click on it does nothing and leaves the menu open. (An AXPress on it closes the menu and runs nothing.) A `Divider` is 11 px tall and never highlighted. A disabled button is grey, skipped, and its action never ran. A `Section` header is a small grey caption that is never highlighted. A button titled with three leading spaces is drawn indented and works like any button. A submenu behaves like the top level. |
| macOS 26 | The same. |
| How it was shown | The accessibility tree, posted pointer rests and clicks, keyboard walks (runs 1 and 3). |
| Not shown | An AXPress on a disabled button: that probe hit a menu that had already closed, so it says nothing. |

### 5.5 How often does the "menu opened" signal fire?

| | |
|---|---|
| macOS 15 | Exactly one `didBeginTracking` for each opening of the menu, and exactly one `didEndTracking` for each closing (Escape, choosing a line, or a click outside). None when a submenu opens or closes; a submenu posts only its own will-open and did-close. The object is the same menu every time: SwiftUI's menu for the menu-bar item, with an empty title, not `NSApp.mainMenu`. At the first opening it has no items yet; they arrive with the will-open notification. |
| macOS 26 | The same. |
| How it was shown | The app's notification log. Begin and end counts are equal in all ten logs (five runs, two versions). |
| Not shown | Apple's page names the main menu bar or a pop-up button's root menu as the object [7]; the runner showed the menu-bar item's own menu instead. One stray will-open and did-close of the top menu, with no begin or end, followed an AXPress sent to a menu that had already closed. |

### 5.6 What happens when the menu changes while it is open?

| | |
|---|---|
| macOS 15 | The top level redraws live: titles, added and removed rows, and the menu's height all change. Posted clicks on a changing top-level row 50, 400 and 1200 ms after a change ran the action of the row that was clicked (3 clicks per keying). Posted clicks inside an open submenu, at least 1.3 s after a change, also ran the right row. **An open submenu closes at every change, a changed title included.** It comes back about 0.25 s later only if the pointer rests on its parent row. With the pointer inside the submenu it stays closed, and a click where it was closes the whole menu and runs nothing (8 of 8 in run 2). A change also moved or cleared the keyboard highlight in three cases, each seen once on each version, and Return pressed right after one of them ran the row the highlight had jumped to (run 5; in run 4, with Return about 0.6 s later, it ran nothing). In another case the highlight held through four changes, so the cause is not known. |
| macOS 26 | The same, with two differences in the keyboard cases. Return after the highlight jumped ran the row it had jumped to in both runs 4 and 5. In 1 of 4 runs of the last keyboard case (run 5, macOS 26 only), a later Return ran a row nobody aimed at; in the other three, macOS 15's included, Return there ran nothing. |
| How it was shown | A timer that added, removed or renamed a row every 2 s (6 s in runs 4 and 5), posted clicks timed against the app's "model change" line, the window list, a highlight sampler every 100 ms (run 5), and screenshots (runs 1 to 3). |
| Not shown | A press within 50 ms of a change. Whether keying rows by id rather than by position makes a difference: all 26 recorded presses ran the row that was shown, but each keying met only one kind of change and too few clicks to tell them apart. A submenu opened by keyboard staying closed after a change: one clean sample per version (run 4). A real trackpad, at MacMosh's real refresh rate. |

### 5.7 Does pressing a line in a submenu close the whole menu?

| | |
|---|---|
| macOS 15 | Yes, for an AXPress, Return and a posted click alike. One `didEndTracking` follows, and no begin. The order is: the line is selected, the submenu and the top menu close, `didEndTracking`, then the line's action runs. **The end of tracking comes before the action.** |
| macOS 26 | The same order. |
| How it was shown | The app's notification log (runs 1 and 5). |
| Not shown | Nothing further for this question. |

### 5.8 How tall is the menu?

| | |
|---|---|
| macOS 15 | On a 1024 × 768 screen at scale 1, 11 top-level rows make a menu 252 px tall. A 12-row submenu opened from it is 274 px tall and fits with no scrolling. |
| macOS 26 | 274 px for the 11 rows and 298 px for the 12-row submenu; it fits with no scrolling. |
| How it was shown | The window list, the accessibility tree and screenshots (run 1). |
| Not shown | A MacBook screen with a notch, and the real six-desk menu on the daily Mac. |

### 5.9 What does Terminal's dictionary say about `do script`?

| | |
|---|---|
| macOS 15 | Terminal 2.14. `<command name="do script" code="coredosc" description="Runs a UNIX shell script or command.">`, a parameter `<parameter name="in" description="The tab in which to execute the command" … optional="yes">` of type tab, window or any, and `<result type="tab" description="The tab the command was executed in." />`. Nothing in these lines asks for a new tab. |
| macOS 26 | Terminal 2.15. The same lines, at the same line numbers (320 to 335). |
| How it was shown | `sdef` run on each runner; the trial printed lines 318 to 336 of the dictionary (run 1). |
| Not shown | The rest of the dictionary. Running any form of `do script … new tab`. |

## 6. The design

### 6.1 The menu in five cases

All names are examples. Attic is a laptop workhorse with six desks:

| Desk | Windows | Tabs |
|---|---|---|
| website | claude, zsh, vim | claude and zsh each in a tab MacMosh opened; vim in none |
| api | server, tests | none |
| notes | one window | in a tab MacMosh opened |
| blog | one window | none |
| shop | web, db | web in a tab MacMosh can't find (for example one opened by hand) |
| garden | permanent, closed | none |

`▸` marks a row that opens a submenu. `(text)` marks a grey line that does nothing when clicked. Indent is three spaces, as today; the trial showed leading spaces drawn as an indent (section 5.4). Submenus go one level deep only.

#### (a) Attic Ready, workhorse script 0.8.0 or newer, mosh or plain ssh

Top level:

```
<the notice: what the last action said, when there is one>
Attic · Ready                              ▸
   website · 3 windows, 2 in tabs          ▸
   api · 2 windows                         ▸
   notes · 1 window, in a tab              ▸
   blog · 1 window                         ▸
   shop · 2 windows, 1 in a tab            ▸
   garden (closed)                         ▸
   New desk…
─────
Add a Mac…
Check now
─────
Quit MacMosh
```

The submenus:

```
Attic · Ready ▸
   Share screen
   Turn off lid-closed mode…                (laptops only; "Turn on lid-closed mode…" when it is off)
   Restart…
   ─────
   Sign-ins working                         (text; today's summary, one fact per line; changed 2026-11-23)
   Awake on power                           (text)
   Lid-closed mode on                       (text; laptops only)
   On power, 100%                           (text)
   <today's home-address line, word for word>   (text)
   ─────
   Run the checklist…

website ▸                                 api ▸
   Open the 1 window not in a tab            Open api in 2 tabs
   ─────                                     ─────
   claude (in a tab)                         server
   zsh (in a tab)                            tests
   vim                                       ─────
   ─────                                     New window
   New window                                ─────
   ─────                                     Rename api…
   Rename website…                           Remove api…
   Remove website…
   kept running, permanent   (text; only the flags that are set)

notes ▸              blog ▸              shop ▸                               garden ▸
   Go to notes          Open blog           Open the 1 window not in a tab       Open garden
   ─────                ─────               ─────                                ─────
   New window           New window          web (open in another tab)            Rename garden…
   ─────                ─────               db                                   Remove garden…
   Rename notes…        Rename blog…        ─────                                permanent   (text)
   Remove notes…        Remove blog…        New window
                                            ─────
                                            Rename shop…
                                            Remove shop…
```

- (changed 2026-11-23) The summary is the same words `StatusFormat.summaryLine` joins with " · ", split where it joins them, one grey line each (`StatusFormat.summaryFacts`), in both shapes (a) and (b). CI's pictures showed the single long line cut in the middle on the runners' 1024 × 768 screen. The window's board keeps the joined line.
- A desk with one window has no window list; its first line does that job.
- Two tabs on one window read `zsh (in 2 tabs)`.
- Two windows with the same name read `zsh` and `zsh (window 3)`, where 3 is that window's number. (changed 2026-11-23) The number comes right after the name, before any tab words: `zsh (window 3) (in a tab)`. A window with no name reads `window <number>`.
- (changed 2026-11-24, issue #144) With workhorse script 0.11.0 or newer, and the report giving the desk's window ids, every open desk's submenu has **`Name a window…`** right after `New window`, in the same group: `New window`, `Name a window…`, then the separator before `Rename <desk>…`. A closed desk has none. A window's line shows the name it was given (`front end (in a tab)`), whole.

With sign-ins off, today's hint and `Fix…` stay at the top level, directly under `Attic · Ready` and above the desks. A problem is never hidden in a submenu.

#### (b) Attic Ready with an older script (before 0.8.0), or in Tabs mode

The top level has the same shape. Each desk's row keeps today's title word for word, and its submenu has no window lines:

```
Attic · Ready                                            ▸   (as in (a))
   website (3 windows: claude, zsh, vim, open in 1 tab)  ▸
      Open website            (today's desk click: a tab running connect)
      New window              (today's background "desk window")
      ─────
      Rename website…
      Remove website…
   garden (closed)                                       ▸
      Open garden
      ─────
      Rename garden…
      Remove garden…
   New desk…
```

(changed 2026-11-23) The workhorse's submenu in shape (b) also draws the summary one fact per line; nothing else in it changes.

In Tabs mode iTerm2 already shows each tmux window as its own tab, so today's `New window` already gives the new window a tab, and a window list is not needed.

(changed 2026-11-24, issue #144) Shape (b) gets `Name a window…` too, on the same rule as (a): script 0.11.0 or newer and window ids in the report, whatever the connection. It sits right after `New window`, before the separator: `Open website`, `New window`, `Name a window…`, ─────, `Rename website…`, `Remove website…`.

#### (c) States that are not Ready: unchanged and flat

```
Attic · Locked after a restart
   <hint>
   Unlock disk…  (you type the Mac's password)
   Run the checklist…

Attic · Waiting for login
   <hint>
   Log in…  (opens Screen Sharing)
   Run the checklist…

Attic · Can't reach it
   <hint>
   Run the checklist…
```

Can't verify it, Needs setting up (with `Pair…` or `Finish setting up…`), Waiting for the desk server and Still checking… keep exactly today's lines. None of them has a submenu.

#### (d) Two workhorses

```
Attic · Ready                           ▸
   website · 3 windows, 2 in tabs       ▸
   … one row per desk …
   New desk…
─────
Den · Locked after a restart
   <hint>
   Unlock disk…  (you type the Mac's password)
   Run the checklist…
─────
Add a Mac…
Check now
─────
Quit MacMosh
```

#### (e) No workhorse: unchanged

```
No workhorses yet
Add a Mac…
─────
Quit MacMosh
```

CI's `lines=2` still holds.

### 6.2 What each line does

Terms used in the table:

| Term | Meaning |
|---|---|
| F | the desk's windows that have a tab MacMosh can find |
| U | windows whose only tabs MacMosh can't find |
| N | windows with no tab |
| `connect` | the bundled `macmosh connect`, run in a new terminal tab |

| Line | Click |
|---|---|
| A desk's row | Resting the pointer on it opens its submenu. A click runs the same action as the submenu's first line, and the menu closes. Return on the row is expected to do the same; the trial showed it only with the submenu closed (section 5.3). The first line stays in the submenu too. |
| The workhorse's row (`Attic · Ready`) | Resting the pointer on it opens its submenu. It has no action of its own. |
| `Open <desk>` (one window, no tab) | `.tab(["connect", id, desk, "--window", "@n"])` |
| `Open <desk> in K tabs` (every window has no tab) | `.tabs`: one `connect … --window @n` per window, in window order |
| `Open the K window(s) not in a tab` (some windows have no tab, others have one) | `.tabs`: one `connect … --window @n` per window with no tab |
| `Open the 1 window not in a tab` (changed 2026-11-23: the exact words for one) | `.tabs` with that one window's `connect … --window @n` |
| `Go to <desk>` (every window has a tab, at least one findable) | `.focus(label: <the tab on the lowest-numbered F window>, orOpen: ["connect", id, desk, "--window", "@n"])` |
| `Open <desk> in a new tab` (every window has a tab, none findable) | `.tab(["connect", id, desk, "--view"])` |
| `Open garden` (a closed permanent desk) | `.tab(["connect", id, desk, "--view"])`; the script makes the desk, then a view on it |
| `<window> (in a tab)` or `(in N tabs)` | `.focus(label: <the most recently opened findable tab>, orOpen: connect … --window @n)` |
| `<window>` (no tab) | `.tab(connect … --window @n)` |
| `<window> (open in another tab)` | `.tab(connect … --window @n)`: a second tab on that window, here. tmux shows the same window in both. |
| `New window` (0.8.0 or newer, mosh or ssh) | `.tab(["connect", id, desk, "--new-window"])`. Tabs that are already open keep what they show. |
| `New window` (older script or Tabs mode) | Today's `.run(["desk", "window", id, desk])` |
| `Name a window…` (changed 2026-11-24, issue #144: script 0.11.0 or newer, window ids in the report, an open desk; both shapes) | `.tab(["desk", "name-window", id, desk])`: a tab whose form lists the desk's windows numbered, asks which (not when it has one; an empty answer changes nothing) and asks the name (an empty answer lets the window follow its program's name again), like `Rename…`. The click is a tab line like the others, logged `menu action: tab desk (line)`. The window's board has a button per window instead (main-window design, section 7.1 A). |
| `Open <desk>` (older script or Tabs mode) | Today's `.tab(["connect", id, desk])` |
| (changed 2026-11-23) The window's board | Keeps its buttons as they were: `Open <desk>` with today's `connect`, and `New window` with today's `desk window`. Only the menu has the first-line forms, the window lines, `New window` in a tab of its own and the flags line; the test that compares the two faces names these as the menu's own. |
| Rename… and Remove… (Remove still with `--ask`), New desk…, Restart…, the lid-closed line, Run the checklist…, Fix…, Unlock disk…, Log in…, Pair…, Finish setting up…, Share screen, Add a Mac…, Check now | Unchanged |
| Text lines | Nothing |

`.tabs` and `.focus` are two new actions. Like `.tab`, they run in the app's own process (`MenuActionRunner`), the route that already holds the Automation permission, not through the 30-second background helper. What `.focus` does:

1. It reads the tab record named by the label.
2. If the record is missing, or its process has ended or has a different start time, it deletes the record and opens `orOpen` as a tab. The notice reads `That tab has closed, so MacMosh opened a new one.`
3. Otherwise it runs the select script for the record's terminal (section 8.4), with the tab's terminal device as a separate argument.
   - `ok`: done. The log says `tab selected`.
   - `gone`: it deletes the record and does step 2's fallback.
   - Automation denied: today's notice, word for word.
   - Any other failure: the notice `Couldn't bring that tab forward. <reason>`.

`.tabs` opens its tabs in order and stops at the first denial. (changed 2026-11-23) As merged in pull request #123, it stops at the first tab that doesn't open for any reason, a denial or another failure, and the notice says how many opened before it (`2 of 3 tabs opened. <why>`). A tab the opener had to open another way (a command file, when macOS hasn't let MacMosh control the terminal) counts as opened, and the first such sentence is kept as the notice. It waits 400 ms between two tabs.

### 6.3 New and changed words

- **Desk row** (0.8.0 or newer, mosh or ssh): `<desk> · 1 window` or `<desk> · N windows`, followed by nothing, `, in a tab` (one window), `, all in tabs`, `, 1 in a tab` or `, K in tabs`. A window counts as in a tab when any tab shows it, findable or not. `<desk> (closed)` stays. With an older script or in Tabs mode, the row keeps today's title.
- **First line of a desk's submenu**: `Open <desk>`, `Open <desk> in K tabs`, `Open the 1 window not in a tab`, `Open the K windows not in a tab`, `Go to <desk>` or `Open <desk> in a new tab`.
- **Window line**: `<name>`, `<name> (in a tab)`, `<name> (in N tabs)` or `<name> (open in another tab)`. A repeated name gets ` (window <number>)`.
- **Other desk lines**: `New window`, `Rename <desk>…`, `Remove <desk>…` (today they read `New window in <desk>` and the same two). (changed 2026-11-24, issue #144) And `Name a window…`, right after `New window`.
- **Flags line**: `kept running`, `permanent`, or `kept running, permanent` (today these sit inside the desk's title).
- **Summary** (changed 2026-11-23): one grey line per fact in the workhorse's submenu, for example `Sign-ins working`, `Awake on power`, `Lid-closed mode on`, `On power, 100%`; the words are today's.
- **Notices**: `That tab has closed, so MacMosh opened a new one.` and `Couldn't bring that tab forward. <reason>`.
- **Later**: `Open MacMosh` (main-window design, step 3).

### 6.4 The menu holds still while it is open

The trial showed that every change to the menu's content, a changed title included, closes an open submenu. It comes back only if the pointer is resting on its parent row, and a click where it was closes the whole menu and runs nothing. A change sometimes moved the keyboard highlight, and Return right after it ran the row the highlight had jumped to (section 5.6). So:

1. The refresher never publishes a menu equal to the one on screen.
2. While the menu is open and the menu on screen has at least one submenu, a different menu waits. It is applied when the menu closes, at `didEndTracking`.
3. A menu on screen with no submenu (every state that is not Ready, and "No workhorses yet") updates at once, as today.
4. The check that runs when the menu opens still runs. Its result is what he sees the next time he opens the menu, or at once if the menu on screen has no submenu.

A changed title waits like any other change, because the trial showed that a title change closes an open submenu too. (The base design applied title-only changes at once; that is dropped.)

This rule is pure and lives in MacMoshKit, with tests (section 9). The app adds a listener for `NSMenu.didEndTrackingNotification` beside today's listener for the beginning. The trial showed exactly one of each per opening and none for a submenu (section 5.5), so today's "menu opened" signal stays as it is, and the base design's gate on it (`MenuOpenGate`) is not built.

Two timing details are the agent's calls (section 12). First, the waiting menu is applied on the main actor's next turn after `didEndTracking`, because the trial showed the end of tracking arriving before the chosen line's action runs (section 5.7). Second, a `didBeginTracking` that arrives while the refresher still thinks the menu is open first applies any waiting menu, so a lost end notice could cost one stale opening, not a menu that never changes again. That the next turn comes after the chosen line's action has been sent is expected, not shown, so the app writes a log line when it applies a waiting menu, and the log shows which came first.

### 6.5 What moves into the main window later

Once the main window's forms exist (its step 4 for desks and step 6 for Settings, on top of the window of step 3):

- `Rename…`, `Remove…` and the flags line leave each desk's submenu. The window's detail strip and forms take them.
- `Restart…`, `Run the checklist…`, the summary lines (changed 2026-11-23: one line per fact) and the home-address line leave the workhorse's submenu. The window's header and foot have them.
- The workhorse's submenu keeps `Share screen` and the lid-closed line.
- A desk's submenu then has the Open or Go line, the window lines and `New window`. That is under the "about five items" of Apple's guideline [5] for most desks.
- The hint and fix lines of states that are not Ready, `Run the checklist…` among them, stay.
- `Open MacMosh` arrives earlier, with the window itself (main-window design, step 3), above `Quit MacMosh`.

## 7. The workhorse script's addition (0.8.0)

Pull request #106 merged as reviewed, as script 0.7.0 with views. The labels are their own small pull request on top of it, as script 0.8.0:

1. **`attach --label <word>`.** The word must match `^[0-9a-f]{4,32}$`; anything else is a usage error.
   - With `--cc` (Tabs mode): a usage error.
   - With `--window` or `--new-window`: the new view gets the tmux user option `@macmosh-label <word>`, set by the view's id beside `@macmosh-view`, as pull request #106 sets its tag.
   - With neither: a view on the desk's current window, first making the desk if it is a permanent desk that is closed, as plain `attach` does. Then the label is set on it. This is what lets every tab the new app opens be found again.
2. **The `view` record gains a sixth field, the label**, empty when there is none: `view<TAB>desk<TAB>view name<TAB>window id<TAB>tabs<TAB>label`. The window id is the view's current window, so the label follows him when he switches windows inside a tab.
3. **The version goes to 0.8.0**, and `scripts/embed-host-script.sh` is run again (v1 plan, "Every task", rule 8).
4. **Script tests**, on the throwaway tmux socket:
   - a label is stored and comes back in the `view` record;
   - a bad label is refused;
   - `--cc --label` is refused;
   - a label with no window option makes a view on the current window;
   - a label on a closed permanent desk makes the desk and then the view;
   - after a rename, the view is listed under the new desk name.

The app uses the shape of section 6.1 (a) only when the workhorse's script is 0.8.0 or newer (section 8.3).

## 8. Finding the tab on the daily Mac

### 8.1 The tab record

- The folder is `<supportDir>/tabs/`, mode 0700, with one file per tab, named by its label, mode 0600. `supportDir` already honours `MACMOSH_SUPPORT_DIR`, so tests use a temporary folder.
- Each file holds a small JSON object:
  - `label`;
  - `workhorse` (its id);
  - `desk` (for logs only; it is never used to join, so a rename can't break it);
  - `askedWindow` (`@n`, or empty);
  - (changed 2026-11-23) `target`: the option the tab was opened with, `window`, `new-window` or `view`. A record written before this key existed has none and still reads. It tells a fresh `--view` tab from a `--new-window` one, whose `askedWindow` are both empty (section 8.2);
  - `pid` and `started`: the `macmosh connect` process and its start time;
  - `tty`: the tab's terminal device, from `ttyname(STDIN_FILENO)` [15];
  - `terminal`: `iterm2` when `TERM_PROGRAM` is `iTerm.app`, `terminal` when it is `Apple_Terminal`, otherwise `unknown`. The `Apple_Terminal` value is inferred, not documented: macOS's `/etc/zshrc` reads `/etc/zshrc_$TERM_PROGRAM`, and the file `/etc/zshrc_Apple_Terminal` exists [15]. It is checked on the daily Mac (section 11);
  - `openedAt`.
- Nothing is matched on `ITERM_SESSION_ID`, because no page read joins it to the AppleScript session id (section 4.3).

### 8.2 When a record is trusted

A record is live only while both hold:

- `kill(pid, 0)` succeeds [15]; and
- the process's start time equals `started`. The builder takes the start-time call from Apple's or the manual page's documentation, behind a small `ProcessProbe` protocol so tests can fake it.

The terminal device alone is never trusted, because nothing read says a device name is not reused by a later tab. `macmosh connect` deletes its record when it ends; a record that outlives it fails the check above.

**Joining** is a pure function in MacMoshKit, `DeskTabs.build(desk:windowInfo:views:records:now:)`:

- A window's findable tabs are the live records whose label appears in a `view` record for that window.
- A live record whose label is not in the report yet, whose `askedWindow` is that window and whose `openedAt` is less than 2 minutes old, also counts. Without this, a second click before the next check would open a duplicate tab.
- Unfindable tabs are the window's `windowinfo` tab count minus its findable tabs, never below 0.
- (changed 2026-11-23) Two cases the outline left open, decided in issue #124: a label on `view` lines of two windows (the script doesn't check labels are unique) counts for the window of the first such line only, and on the other window it is an unfindable tab; a `view` line for a window with no `windowinfo` line is ignored, as if it were not there, so its label is in no window and a fresh record carrying it still counts for its asked window. A record whose label breaks the label rule, and a window whose id isn't `@` and digits, are never used, since their words would go into an action.
- (changed 2026-11-23) The 2-minute rule above is not enough on its own: the new tab writes its record only after its own `macmosh connect` has checked the workhorse, and the menu shows the tab only once a later check has the record or the `view` line, so the menu can offer the same window for up to one poll (about 30 seconds) after the click. So the click is guarded as well (`MenuActionRunner`, review of pull request #127): before a tab action opens `connect <id> <desk> --window @n` (alone, as one of several tabs, or as a Go action's fallback) or `connect <id> <desk> --view`, it looks for a live record of the same workhorse and desk, asked for that window (or with `target` `view`), opened less than 2 minutes ago, with a terminal tab's device. If there is one, that tab is brought forward instead, and in a list of tabs it counts as opened. This check matches the desk by name, which section 8.1 otherwise never does; for 2 minutes that is safe, and after a rename it only means a new tab opens as before. `New window` is never guarded: each click is a new window.
- The refresher prunes this workhorse's records that are dead, or whose label has been missing from a good report for more than 2 minutes. Pruning is a side effect, so it lives in `MenuRefresher`, not in the model.

### 8.3 `macmosh connect` and the gate

`macmosh connect <id> <desk> [--window @n | --new-window | --view]`:

- With one of these options (only the menu sends them, and only when the gate below passes), `connect` makes a label from the system's random generator, writes the record, and runs `attach --label <word>` with the matching option (`--view` sends none).
- The mosh line becomes `/bin/sh -c 'exec "$HOME/.macmosh/macmosh-host" attach "$@"' macmosh-host --label 9f3a1c2e5b7d4a60 --window @3 website`. The plain ssh mode's host command changes the same way.
- In Tabs mode the options are refused with `Tabs mode already shows every window as its own tab.`
- Plain `connect <id> <desk>` behaves exactly as today.

**The gate.** The menu uses the shape of section 6.1 (a) only when all three hold:

- the workhorse's `scriptVersion` is 0.8.0 or newer, compared with the dotted-number comparison `HostInstaller` already uses;
- the connection mode is mosh or plain ssh;
- the report carries `windowinfo` records for the desk.

Otherwise it uses shape (b).

(changed 2026-11-23) As built (`WindowLinesGate`, issue #124), the gate is decided for each desk, and the second condition is the connection the tab will really use: the workhorse's mode as `connect` turns it, by the same function `connect` calls (`ConnectionMode.used(inITerm2:)`), for the terminal the menu's tabs open in (`TabOpener.terminal`: the setting, else iTerm2 when it is installed, else Terminal). Tabs mode with tabs opening in Terminal is mosh, so it passes. A closed permanent desk has no windows to detail and needs only the first two conditions. An open desk whose window ids are all unusable keeps shape (b). Since a closed permanent desk needs no window details, a 0.8.0 report without `windowinfo` lines gives a mix: its closed permanent desks take shape (a) (`Open <desk>` with `--view`, the flags as a grey line) while its open desks keep shape (b). `MenuRefresher` reads the live records and asks where tabs open off the main actor, after it clears old records, and passes both, with the time, into `MenuModel.build` as a value (`TabsOnThisMac`); the model reads no file and no clock.

### 8.4 The select scripts

Two launcher scripts, sent as today's are, through `osascript`, the macOS command that runs AppleScript (`osascript -e <script> <tty>`, `TerminalLauncher.swift`). Each answers one line: `ok`; `gone` when no tab has that device; or `failed <step> <error number>`.

(changed 2026-11-23, issue #129) **What went wrong, and the rule from now on.** The scripts merged in pull request #123 had been read against the dictionaries but never run. On the daily Mac (iTerm2 3.7.8) going to a tab failed every time with error -1728: inside `tell application "iTerm2"`, `contents of w` is iTerm2's own session property, "The currently visible contents of the session.", not AppleScript's. From now on a script that drives a terminal app is not merged until it has run against that app: CI's "Terminal scripts" job (`.github/workflows/terminal-scripts.yml`, `scripts/ci/try-select.sh`) runs the two scripts the build sends against a real iTerm2 and Terminal on macOS 15 and 26 and reads back which tab is in front. Today it runs only the two select scripts: the scripts that open a tab (`ITermLauncher.script`, `AppleTerminalLauncher.script`) ran by hand in sitting 1, and a change to them must be added to the job before it merges. The job is not a required check (`main` has no branch protection), so the rule holds only while whoever merges reads the job's result.

The scripts as of issue #129 work in three steps. Each step searches again by the device, does one thing to what it finds and returns, so no reference is used after a command that can change the order of windows (a loop variable is a reference by position, and both terminals list their windows front to back). Step A un-minimizes the window that holds the tab. In iTerm2, step B brings that window to the front and step C selects the tab and the session and activates iTerm2. In Terminal, step B activates Terminal and step C selects the tab and puts its window first: with Terminal behind another app, raising a window that had been minimized and then activating Terminal brought Terminal's previous front window back on top (CI, pull request #131), so Terminal is activated before its window is raised. Each step runs inside its own `try`, so a failure names its step. `TabOpener.select` reads the answer: `ok` is selected, `gone` is gone, a `failed` line is a failure whose log summary is `tab not selected (step B, error -1728)` and whose notice is "Couldn't bring that tab forward." with a short reason. A step that answers error -1743 is still the Automation refusal, worded as before.

iTerm2:

```applescript
on run argv
    repeat with i from 1 to 3
        set step to character i of "ABC"
        try
            if not atStep(step, item 1 of argv) then return "gone"
        on error number n
            return "failed " & step & " " & n
        end try
    end repeat
    return "ok"
end run

on atStep(step, wanted)
    tell application "iTerm2"
        repeat with w in windows
            repeat with t in tabs of w
                repeat with s in sessions of t
                    if (tty of s) is wanted then
                        if step is "A" then
                            if miniaturized of w then set miniaturized of w to false
                        else if step is "B" then
                            select w
                        else
                            select t
                            select s
                            activate
                        end if
                        return true
                    end if
                end repeat
            end repeat
        end repeat
    end tell
    return false
end atStep
```

Terminal:

```applescript
on run argv
    repeat with i from 1 to 3
        set step to character i of "ABC"
        try
            if not atStep(step, item 1 of argv) then return "gone"
        on error number n
            return "failed " & step & " " & n
        end try
    end repeat
    return "ok"
end run

on atStep(step, wanted)
    tell application "Terminal"
        repeat with w in windows
            repeat with t in tabs of w
                if (tty of t) is wanted then
                    if step is "A" then
                        if miniaturized of w then set miniaturized of w to false
                    else if step is "B" then
                        activate
                    else
                        set selected of t to true
                        set index of w to 1
                    end if
                    return true
                end if
            end repeat
        end repeat
    end tell
    return false
end atStep
```

Every word these scripts send is in the installed dictionaries (section 4.3): iTerm2's window, tab and session `select`, session `tty` and window `miniaturized`; Terminal's tab `tty` and `selected`, and window `index` and `miniaturized`. Neither says `contents` or names an object by `id`. On pull request #131 the CI job ran them with iTerm2 3.7.7 and Terminal 2.14 (macOS 15) and 2.15 (macOS 26) in four cases: a tab in a window behind another (in iTerm2 also not the selected tab of its window), a tab in a minimized window, the tab already in front, and a device no tab has. Before the first two the job brings Finder forward, so the terminal is not the active app, as when a person clicks the menu. Every case ended with the wanted tab in front, unminimized, its app frontmost, and `gone` for the last. Not shown there: Terminal choosing between tabs of one window (Terminal opens only windows by script), iTerm2 3.7.8, the app itself sending the script, and a window on another Space; those are tried on the daily Mac.

**Which terminal.** The record's `terminal` value decides. When it is `unknown`, the rule `TabOpener` uses today applies: the setting, else iTerm2 if it is installed, else Terminal.

**The Automation permission.** Selecting a tab sends Apple events from the same app to the same terminal as opening one does, so the existing permission is expected to cover it. That is checked on the daily Mac.

### 8.5 Terminal: no new tab from `do script`, so a window per tab

`do script` has no form that asks for a new tab, and the separate `do script in new tab` has not been tried, so MacMosh keeps a window per tab in Terminal. Terminal's dictionary, printed on both runners (Terminal 2.14 on macOS 15 and 2.15 on macOS 26), defines `do script` as "Runs a UNIX shell script or command." Its only target parameter is `in`, "The tab in which to execute the command", which takes a tab or a window that already exists, and its result is "The tab the command was executed in." There is no "new tab" form in it [14]. So in Terminal, MacMosh keeps opening a new window for each tab, as the v1 design's section 7.7 and call 20 already decide (section 7.7 now also notes the separate command), and `.tabs` opens one Terminal window per tab. Bringing a Terminal window forward by its terminal device (section 8.4) still applies. The base design's attempt to open Terminal tabs is dropped.

The evidence is narrow. The trial printed only lines 318 to 336 of each runner's dictionary. Issue #105 noted that Terminal 2.15's dictionary read on macOS 27.3 also lists a separate command, `do script in new tab` ("Runs a UNIX shell script or command in a new tab.") [14]. Whether the runners' dictionaries list it was not shown, and nobody has run it; sitting 1's attempt used a different form and stopped at a syntax error (-2741). This design does not use it. Trying it is a separate, later change.

## 9. The model and the tests, in outline

### 9.1 The model

Step 1 of the main window (#108) builds the menu as a tree and flattens it. This design draws that tree. The outline below was written before step 1 merged (pull request #109). The merged `MenuEntry` differs from it: it holds an id, a title, an action, a separator flag and children, and an entry with both an action and children is a desk's line. S1 follows the merged types and adds what the outline needs on top of them, such as a way to mark a grey text line.

```swift
// MacMoshKit/Menu/MenuLines.swift (step 1 renamed Menu to MenuLines)
public struct MenuLines: Sendable, Equatable {
  public var symbol: String
  public var entries: [MenuEntry]
  public var items: [MenuItem] { MenuEntry.flatten(entries) }   // the log's lines=, older tests and PlainWords read this
}
public struct MenuEntry: Sendable, Equatable, Identifiable {
  public enum Kind: Sendable, Equatable {
    case button(MenuAction), text, separator
    case submenu([MenuEntry], primary: MenuAction?)   // primary: a desk's first line; nil for the workhorse's row
  }
  public var id: String; public var title: String; public var kind: Kind
}
public enum MenuAction { case tab([String]), tabs([[String]]), focus(label: String, orOpen: [String]), run([String]), refresh, none }
MenuModel.build(_ gathered: [Gathered], tabs: [TabRecord], waitingForDeskServer: Set<String>, now: Date) -> MenuLines
```

(changed 2026-11-23) As built in issue #124: `MenuModel.build(_ gathered:, waitingForDeskServer:, tabs: TabsOnThisMac, now:, timeZone:)`, where `TabsOnThisMac` holds the live records and the terminal tabs open in. The gate is `WindowLinesGate`, and a desk past it carries a `DeskWindows` value (its row title, first line, window lines, `New window` and flags line) on its `DeskLine`, made from `DeskTabs.build`. The view (`MenuContent`) is unchanged: it draws what `MenuLines.rows` gives.

- **flatten** turns a submenu into one line at indent d, carrying its primary action or `.none`, with its children at indent d + 1. `lines=` counts the flattened items, so CI's `lines=2` and `MenuRefresherTests`' `lines=6` don't change: those states have no submenus.
- **Ids** are unique across the whole tree and the same across builds:

  | Entry | Id |
  |---|---|
  | the workhorse's row | `wh:<id>` |
  | hint, fix | `wh:<id>:hint`, `wh:<id>:fix` |
  | a desk's row | `desk:<id>:<name>` |
  | lines inside a desk | `desk:<id>:<name>:open`, `…:win:@3`, `…:window` (changed 2026-11-23: `New window` keeps the id it has in shape (b), not `…:new`), `…:rename`, `…:remove`, `…:flags` |
  | the summary's lines (changed 2026-11-23) | `wh:<id>:summary:1`, `wh:<id>:summary:2`, … |
  | separators | `<parent>:sep<n>` |
  | top-level lines | `top:newdesk:<id>`, `top:add`, `top:check`, `top:sep<n>` |

  A rename changes a desk's ids, which Apple's `ForEach` page allows for "a new data element" [9].
- **`MenuContent`** draws the tree with two small views, `EntryList` (a `ForEach(entries)` keyed by `id`) and `EntryRow`: a submenu is `SwiftUI.Menu(title) { EntryList(children) }`, with `primaryAction:` when it has one; text is `Text`; a separator is `Divider`; a button is `Button`. The notice and Quit stay as they are.
- **The hold-still rule** (section 6.4) is a small pure type in MacMoshKit (called `MenuHold` here). Given the menu on screen, whether the menu is open, and a newly built menu, it says "show now", "wait" or "nothing to do". `MenuRefresher` keeps the waiting menu and applies it when told the menu closed.

### 9.2 The tests

All are pure except the record store, which uses a temporary folder.

- **Stored trees** for every `everySampleMenu()` case, plus new samples: six desks with mixed tabs; an older script; Tabs mode; two workhorses that share a desk name.
- **Shape**: with six desks the Ready top level is 1 + desks + 1 lines; sign-ins off adds only the hint and `Fix…`. Blocks that are not Ready equal step 1's stored copy.
- **Primary actions**: every desk row's primary action equals its first line's action; the workhorse's row has none.
- **First line**: each combination of N, F and U gives the expected words and action, including all-unfindable and closed.
- **Window lines**: a findable tab gives `.focus` with the most recent label; no tab gives `.tab --window`; an unfindable one gives `.tab --window`; two tabs give "(in 2 tabs)"; a repeated name gets "(window n)".
- **Joining**: a fresh record not yet in the report counts for its asked window, and after 2 minutes it doesn't; a dead or restarted process doesn't count; a label that follows a window switch moves to the new window; after a rename the record still joins by label; another workhorse's records are ignored.
- **Gate**: an older script, Tabs mode, or no `windowinfo` gives shape (b) and today's `.run` New window; `connect` refuses the new options in Tabs mode.
- **Ids**: unique across the tree, the same across two builds, and no submenu inside a submenu.
- **Hold still**: a menu equal to the one on screen is never published; with the menu open and a submenu on screen, a different menu waits; it is applied at the close; with no submenu on screen it shows at once; the check run at opening waits like any other; of two waiting menus the later one wins; a close with nothing waiting does nothing; a begin while marked open applies the waiting menu first.
- **Plain words**: walks every argument in `.tab`, `.tabs`, `.focus`'s `orOpen` and `.run`, and the labels, across the flattened tree; `seen > 20` still passes.
- **No tmux words**: no title contains "view", "session", "pane" or "tmux".
- **`MenuActionRunner`**, with a fake tab opener and a fake select runner: `.focus` gives `ok`; `gone` then open; a dead record then open; Automation denied. `.tabs` opens in order and stops at the first denial.
- **`ConnectPlanner`**: the mosh argv carries `"$@"` with `--label` and `--window` or `--new-window`; the ssh host command does the same; plain `connect` is unchanged.
- **`TabRecordStore`**: file mode 0600, folder mode 0700, write, read, prune, and removal when `connect` ends.
- **`HostStatus`**: `view` with 5 or 6 fields, and `windowinfo`; unknown record types are still skipped.

CI's menu check clicks the menu-bar icon through System Events. The trial showed that an accessibility press on a desk's row does not run its primary action (section 5.3), so the row's click is covered by the model tests and the daily-Mac tries, not by CI.

(changed 2026-11-23) Since pull request #118, a second CI job (`.github/workflows/menu-pictures.yml`) starts a debug build with sample data and drives it with posted pointer events, which do run a row's primary action on the runners. For issue #124 it gained the sample `windows` (a script-0.8.0 report with window details and labels, and stand-in tab records in the sample's own temporary folder): it pictures the top level, a desk's submenu with a window in a tab, one open in another tab and one with no tab, and the workhorse's submenu, and it clicks a window line with no tab and one in a tab and checks the app's log names each row. These are posted clicks on GitHub's runners, not a trackpad, and no terminal tab is opened or brought forward there. The stored copies gained `Fixtures/menu/windows-menu.txt` (menus with a line per window) and `Fixtures/menu/s1-menu.txt` (the menu before issue #124, which every menu that fails the gate must equal, but for the summary's lines).

## 10. Order of work

One issue and one pull request per step, tests first, with a build-log entry, as the plan requires.

1. **Main window, step 1** (issue #108, merged as pull request #109): the tree behind the menu, with no visible change.
2. **This documents pull request**: this design, the dated amendments to the main-window design, and the v1 plan and design changes.
3. **The labels in the workhorse script, 0.8.0** (section 7), on top of pull request #106 (views, 0.7.0, merged). Issue #111.
4. **S1: submenus for every script version** (issue #107). Shape (b) of section 6.1 for every Ready workhorse, with the workhorse's submenu, `New desk…` at the top level, the desk row's primary action, and the hold-still rule. The stored copies of Ready menus and the tests that pin positions change on purpose; blocks that are not Ready must still equal step 1's copies. Waits on step 1.
5. **S2: a line per window, `New window` in a tab of its own, and going to the right tab** (issue #105, part 2): `HostStatus` reads `windowinfo` and `view`, the `connect` options, the tab records, `ProcessProbe`, the `.tabs` and `.focus` actions, the select scripts, and shape (a), behind the 0.8.0 gate. Waits on steps 3 and 4.
6. **The lines of section 6.5 leave the menu**, once the main window's forms exist (its steps 4 and 6). Its issue is filed when it starts.

The main window's steps 2 to 6 go on beside steps 3 to 5 (main-window design, section 8, as amended).

## 11. What is not known yet

| Unknown | Why it matters | How it is settled |
|---|---|---|
| A tap or press on a real trackpad on a desk's row, and a click that arrives before the submenu has opened | The row's click is how he opens a desk | Tried on the daily Mac, try 1 below |
| Return on a desk's row while its submenu is open | The submenu opens about 0.25 s after the highlight reaches the row (section 5.2), so a person's Return usually lands while it is open; the trial showed Return only with it closed (section 5.3) | Try 1 below |
| Whether the hold-still rule keeps an open submenu open when a background check lands | It is the reason for the rule | Try 2 below |
| Whether applying a waiting menu between the end of tracking and the chosen line's action could change which action runs | The trial saw the end come first (section 5.7) | Expected to be avoided by applying on the next turn (section 6.4); not shown. A log line records the order of the menu change and the action, and try 2 watches it |
| Whether iTerm2's select script brings the right tab forward with several windows, a minimized window, and a window on another Space, with no new permission prompt | "Takes me to the right tab" | Try 3 |
| Whether `TERM_PROGRAM` is `iTerm.app` inside a tab MacMosh opened, and the tty the process reads equals the one iTerm2 reports | The record would point at the wrong tab | Try 4 |
| Whether a real tab over mosh made with `--window` and with `--new-window` shows its own window, and closing it ends its view within seconds | Pull request #106 left this to a real Mac | Try 5 |
| iTerm2's Tabs mode on a desk that is in a session group | Pull request #106 left this to a real Mac | Try 6 |
| The menu's height with six desks on the daily Mac's screen | Scrolling would hide desks | Try 7 |
| Terminal's select script with several windows, a minimized one and another Space | Decision 4 keeps it | Try 8 (agent's call, section 12) |
| Locking or suspending a tmux client in a view tab closes the tab | Pull request #106 left this as it is on purpose and filed it as issue #110. Once the labels make every tab the new app opens a view, it applies to every such tab, but only with a tmux lock setting or a deliberate lock or suspend | Settled on issue #110 before S2 ships |
| Whether Terminal's `do script in new tab` works | It would give Terminal real tabs | Not tried; a separate, later change (section 8.5) |

### 11.1 What is tried on the daily Mac before the rollout

The agent builds a test copy of the app and reads the app's log over ssh itself. Shariq is asked only for his hands and eyes.

1. **A tap and a press on a desk's row.** Shariq rests on one desk's row and taps it (tap-to-click), then rests on another and press-clicks it. Then he does both again, clicking as soon as the pointer reaches the row, before its submenu opens. Last, he opens the menu, moves the highlight to a desk's row with the arrow keys, waits for its submenu to open, and presses Return. Expect: every click, and the Return, opens (or goes to) that desk, and the menu closes.
2. **A background check with a submenu open.** Shariq opens the menu, rests on a desk so its submenu opens, moves into the submenu and waits there for a minute while the agent changes something the check will see (a scratch desk it makes and removes). Expect: the submenu stays open and unchanged; the next time he opens the menu, it shows the change.
3. **iTerm2 brings the right tab forward.** With tabs on three windows of a scratch desk spread over two iTerm2 windows, one window minimized and one on another Space, Shariq clicks each window line. Expect: each click shows that tab, unminimizes or switches Space as needed, and no new permission prompt appears. (changed 2026-11-23, issue #129) Three cases are tried on their own as well, the ones CI's "Terminal scripts" job runs first (section 8.4): the wanted tab not the selected one in its window, its window behind another, and its window minimized.
4. **The tab's own record.** In a tab MacMosh opened, the agent reads the tab record. Expect: `terminal` is `iterm2`, and its `tty` equals the `tty` iTerm2 reports for that tab's session.
5. **A tab on one window, over mosh.** The agent opens a tab with `--window` and another with `--new-window` on a scratch desk. Expect: each tab shows its own window, the first tab doesn't move, and closing either tab ends its view within seconds (the next report has no `view` line for it).
6. **Tabs mode.** On a scratch desk in a session group, Shariq opens the desk in iTerm2's Tabs mode. Expect: the windows show as iTerm2 tabs, as they do today.
7. **The height.** With six desks, Shariq opens the menu and the longest desk submenu. Expect: no scroll arrows.
8. **Terminal, only if Terminal is the chosen terminal for this try.** The same as try 3 in Apple's Terminal. Expect: the right Terminal window comes to the front, unminimized. (changed 2026-11-23) Here too, two or more Terminal windows with the wanted one not in front, and the wanted window minimized, are tried on their own.

If something's off:

- A click on a desk's row opens only its submenu: S1 ships with the desk's first line as the only way in (the row runs nothing), and the agent brings the choice to Shariq.
- The submenu still closes when a check lands: the agent reads the app's log for a menu change while the menu was open, which would be a fault in the hold-still rule.
- A window line brings the wrong tab forward, or a permission prompt appears: S2 is held, and the select script is changed before rollout.
- A view tab does not end when closed: S2 is held, and the finding goes on issue #105 or a new issue.

## 12. Smaller calls the agent made, for Shariq to check

1. **The waiting menu is applied on the main actor's next turn after the end of tracking**, not inside it, because the trial showed the end arriving before the chosen line's action runs (section 6.4).
2. **A begin while the menu is marked open applies the waiting menu first**, so a lost end notice costs one stale opening instead of a menu that stops changing (section 6.4).
3. **`Open MacMosh` arrives with the main window's step 3**, as the approved main-window design says, not with the last menu step as the base design had it (section 6.5).
4. **Terminal's select script is tried on the daily Mac too** (try 8), because the decision to keep it adds a script nothing has run yet (section 11.1).
5. **`do script in new tab` is recorded as "not used and not tried", not as "absent"**, because the trial printed only part of the dictionary and issue #105 found the command in another copy of it (section 8.5).
6. **A closed permanent desk's row opens it on a click**, `Open garden`, like every other desk row's first line (section 6.2).
7. **CI does not test the desk row's click**, because the trial showed that an accessibility press doesn't run a primary action; the model tests check that it equals the first line (section 9.2).
8. **The view-lock question (issue #110, left as it is by pull request #106) is listed as a risk for S2**, because the labels make every tab the new app opens a view (section 11).
9. **The hold-still type is called `MenuHold` here**; the builder may name it otherwise (section 9.1).
10. **If a click on a desk's row fails on a real trackpad, S1 ships with the row running nothing** and the first line as the way in, and the choice goes to Shariq (section 11.1).
11. **A log line when a waiting menu is applied**, because nothing has shown that the next turn comes after the chosen line's action; the log lets try 2 check it (section 6.4).
12. **Return on a desk's row with its submenu open is part of try 1**, because the trial pressed Return only after closing the submenu (sections 5.3 and 11).

## 13. Sources

Apple pages were read on 2026-11-23 through the data endpoint behind each page: `https://developer.apple.com/tutorials/data/documentation/<path>.json` for the framework pages, and `https://developer.apple.com/tutorials/data/design/human-interface-guidelines/<page>.json` for the Human Interface Guidelines.

1. SwiftUI `Menu`: https://developer.apple.com/documentation/swiftui/menu
2. Populating SwiftUI menus with adaptive controls: https://developer.apple.com/documentation/swiftui/populating-swiftui-menus-with-adaptive-controls
3. Menus and commands: https://developer.apple.com/documentation/swiftui/menus-and-commands
4. `MenuBarExtraStyle.menu`: https://developer.apple.com/documentation/swiftui/menubarextrastyle/menu ; `MenuBarExtraStyle.automatic`: https://developer.apple.com/documentation/swiftui/menubarextrastyle/automatic
5. Human Interface Guidelines, Menus: https://developer.apple.com/design/human-interface-guidelines/menus
6. Human Interface Guidelines, The menu bar: https://developer.apple.com/design/human-interface-guidelines/the-menu-bar
7. `NSMenu.didBeginTrackingNotification`: https://developer.apple.com/documentation/appkit/nsmenu/didbegintrackingnotification
8. `NSMenu.didEndTrackingNotification`: https://developer.apple.com/documentation/appkit/nsmenu/didendtrackingnotification
9. `ForEach.init(_:id:content:)`: https://developer.apple.com/documentation/swiftui/foreach/init(_:id:content:)
10. iTerm2, Scripting with AppleScript (Windows, Tabs and Sessions sections): https://iterm2.com/documentation-scripting.html
11. iTerm2, URL scheme: https://iterm2.com/documentation-url-scheme.html
12. iTerm2's scripting dictionary, `sdef /Applications/iTerm.app` (iTerm2 3.7.7), read 2026-11-23.
13. Terminal's scripting dictionary, `sdef /System/Applications/Utilities/Terminal.app` (Terminal 2.15 on macOS 27.3), read 2026-11-23: tab `tty` and `selected`, window `index` and `miniaturized`.
14. Terminal's `do script`: printed on GitHub's runners in trial run 1 (Terminal 2.14 on macOS 15.8.2, Terminal 2.15 on macOS 26.7.2), dictionary lines 318 to 336; `do script in new tab`: the same `sdef` as [13], noted in issue #105; sitting 1's attempt: `docs/sittings/sitting-1-results.md`.
15. Manual pages on macOS 27.3: `kill(2)`, `ttyname(3)`, `tmux(1)` (3.8, user options); `/etc/zshrc` and `/etc/zshrc_Apple_Terminal`.
16. The trial: branch `trial-submenus` (`trials/submenu/`), last commit 949f02d. Runs 1 to 5, at commits 1bf410d, 43bdae6, 3e760b4, 8dd4fc7 and 949f02d: https://github.com/shariqh/macmosh/actions/runs/45273165480 , https://github.com/shariqh/macmosh/actions/runs/45275259655 , https://github.com/shariqh/macmosh/actions/runs/45276114716 , https://github.com/shariqh/macmosh/actions/runs/45276981510 and https://github.com/shariqh/macmosh/actions/runs/45277783257 .
17. Issues: #107 (submenus), #105 (a new window in a tab of its own, a line per window), #108 (main window, step 1), #94 (the main window), #110 (locking or suspending a view tab closes it), #111 (the labels, script 0.8.0). Pull requests: #106 (views, script 0.7.0, merged as c52bb50), #109 (main window, step 1, merged as eb77d6c).
18. The v1 design (sections 5.1, 7.3, 7.7, calls 20 and 35), the v1 plan ("Every task", the task table, Tasks 28 to 31), and the main-window design (sections 7.6, 7.7 and 8).
19. Code read for this design, at commit 2b9075b, with the places that pull requests #106 and #109 changed read again at eb77d6c: `Sources/MacMoshApp/MacMoshApp.swift`, `MenuContent.swift`; `Sources/MacMoshKit/Menu/` (`MenuModel`, `MenuActionRunner`, `MenuLog`, `MenuRefresher`); `Sources/MacMoshKit/Terminal/` (`TabCommand`, `TerminalLauncher`, `ITermLauncher`, `AppleTerminalLauncher`); `Sources/MacMoshKit/Connect/` (`ConnectPlanner`, `ConnectRunner`); `Sources/MacMoshKit/Host/HostStatus.swift`; `Paths.swift`; `.github/workflows/ci.yml`; `Tests/MacMoshKitTests/` (`MenuModelTests`, `MenuRefresherTests`); `Sources/MacMoshKit/Menu/MenuLines.swift` and `Sources/MacMoshKit/Board/ButtonRules.swift` at eb77d6c; and `host/macmosh-host` on pull request #106's branch.
