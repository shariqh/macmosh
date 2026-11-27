# "Workhorse" becomes "remote Mac": every sentence, before and after

Status: draft for the owner's yes. Written: 2026-11-27. Nothing in the app changes until he approves this document; then one pull request makes exactly these changes, checked through CI's pictures.

On 27 November 2026 the owner decided to stop calling the spare Mac "the workhorse", and asked for the change "Everywhere, the app too". The README already says "the remote Mac". This document lists every sentence a person reads that holds the word, says what it becomes, and names the few places where he has a choice.

## 0. For the owner

### What changes

- Every sentence that says "workhorse" says "remote Mac" instead: the menu, the window, Settings, the checklist, the command's messages and its help, macOS's Local Network prompt, and the lid-closed guide.
- "This Mac" still means the Mac you sit at. No new sentence uses it for the remote Mac, and two old sentences that did are fixed (choice 6).
- The README loses its line "MacMosh's own menus call it the workhorse.", because it stops being true, and its two Settings pictures are taken again, because they show the old words.
- File names, saved-data keys, log lines and code names keep the word for now (section 3), and so does the made-up sample Mac called "Workhorse" in CI's pictures until you choose (choice 5).

### The rule, in short

1. The spare Mac is "a remote Mac", "the remote Mac" or "remote Macs". Where the sentence already names the Mac or sits on its page, plain "Mac" is enough.
2. "This Mac" is only ever the Mac you sit at. If "this" is needed for the remote Mac, it is "this remote Mac".
3. Only words people read change, and each sentence changes as few words as it can.

### The twelve sentences you meet most

| Where | Before | After |
|---|---|---|
| Menu, nothing saved (the command and Settings start the same way) | No workhorses yet | No remote Macs yet |
| Window, nothing saved: the Add a Mac page | At the other Mac, turn on these two in System Settings > General > Sharing: | At the remote Mac, turn on these two in System Settings > General > Sharing: (choice 7) |
| Settings, a Mac's section | Remove MacMosh from this workhorse… | Remove MacMosh from this remote Mac… (choice 1) |
| Settings, Typing prediction | Mosh can show what you type before the workhorse answers. | Mosh can show what you type before the remote Mac answers. |
| Checklist heading | On the workhorse: | On the remote Mac: (choice 3) |
| Checklist step | 1. At the workhorse, turn on System Settings > General > Sharing > Remote Login. | 1. At the remote Mac, turn on System Settings > General > Sharing > Remote Login. |
| macOS's Local Network prompt, once | MacMosh checks on your workhorse over your home network. | MacMosh checks on your remote Mac over your home network. |
| Pairing question | Workhorse address: | Remote Mac address: |
| Pairing question | User name on the workhorse [alex]: | User name on the remote Mac [alex]: |
| Pairing | Next, ssh asks for the workhorse's password. You are typing into ssh; MacMosh can't see it. | Next, ssh asks for the remote Mac's password. You are typing into ssh; MacMosh can't see it. |
| Error | The workhorse didn't answer within 15 seconds. | The remote Mac didn't answer within 15 seconds. |
| A desk's tab, after a drop | … Your work keeps running on the workhorse. | … Your work keeps running on the remote Mac. |

The window's sidebar holds no "workhorse" today (it lists each Mac by its own name), so it doesn't change.

### Your choices

Each has a recommendation; approving the document approves the recommendation unless you pick the other.

1. **The Settings button.** "Remove MacMosh from this Mac…" would point at the wrong Mac, because Settings also has a "This Mac" section. Recommended: **"Remove MacMosh from this remote Mac…"**. Other: name the Mac, as in "Remove MacMosh from Attic…" (clearer, but the fixed text becomes text built from the name).
2. **"The workhorse script"** (macmosh-host, the script MacMosh installs on the remote Mac) appears in five sentences. Recommended: **"the MacMosh script"**, as in "needs the MacMosh script 0.11.0 or newer, and Attic has 0.10.2." The removal list already calls it that ("The MacMosh script: ~/.macmosh/macmosh-host"). The risk: once MacMosh itself has version numbers, "the MacMosh script 0.11.0" could be read as the app's version. Other: **"macmosh-host"**, the name the checklist prints ("Installing macmosh-host 0.13.0 …"): exact, but a file name rather than words.
3. **The checklist's second heading** sits under "On this Mac:". Recommended: **"On the remote Mac:"**. Other: the Mac's name, "On Attic:".
4. **The command's one-line description** ("Drive a spare Mac that works as your workhorse.") reads badly with the rule: "a spare Mac that works as your remote Mac". Recommended: **"Drive a spare Mac that runs your work."**, from the README's own definition. Other: "Drive a remote Mac from this one."
5. **The sample Mac named "Workhorse"** in CI's pictures. The README's first picture shows it three times (in the sidebar, as the page's headline, and as "Workhorse-in-th…"), so readers of the public page still see the word. Recommended: **keep it in this change, and rename it in its own pull request right after**, so this change's stored menu copies differ from today by the new words only. Other: rename it in this change. That costs little extra in pictures, because this change already takes new README pictures, but it re-records the 3 stored menu copies and touches about 48 test lines and 32 CI lines (section 4).
6. **Two sentences already call the remote Mac "This Mac"**: "This Mac can't be unlocked over the network: …" (`macmosh unlock`) and "This setting is for laptops. This Mac has no battery, so it has no lid to close." (`macmosh power … lid`). Once "remote Mac" is the word, both read as the Mac you sit at. Recommended: **change both now**, to "The remote Mac can't be unlocked…" and "…The remote Mac has no battery…". Other: leave them.
7. **The Add a Mac page says "the other Mac"** ("At the other Mac, turn on these two…" and "…asks for the other Mac's password."). It has no "workhorse", but after this change it would be the only place in the app with another name for the remote Mac, and it is the first page a new user meets. Recommended: **"At the remote Mac, …" and "…asks for the remote Mac's password."** Other: leave "the other Mac", which reads well on its own page.

### What you approve by approving this document

1. The rule of section 1.
2. Every row of section 2 as written, with your answers to the seven choices.
3. Two small decisions with no real alternative, since nothing anyone types changes: the `<workhorse>` placeholder in the command's help (`macmosh restart <workhorse>` and 16 more) becomes `<mac>`, also in the two power errors that quote it and in the "Missing expected argument" error; and the made-up example address `alex@workhorse` in add's help and two errors becomes `alex@attic`, the one the other messages already use.
4. Section 3's other names kept as they are.
5. Section 5: the README's bridging line removed, its quoted menu line changed, its two Settings pictures replaced from CI's pictures after the change, and the lid-closed guide reworded.
6. Not approved here: renaming the sample Mac (choice 5, unless you pick it), and the blog and post drafts (section 7), which come back to you rewritten.

### What does not change

- Code names (`WorkhorseStore`, `workhorseID`), file names (`workhorses.json`), saved-data keys, the `--json` values programs read, log lines that tests and CI read, and every command, flag and `macmosh set` key. None of those you type holds the word.
- History: the design documents, the plans, `docs/build-log.md`, the first-run records and the sitting records.
- How anything works. This is words only.

## 1. The rule, in full

**"Remote Mac".** The spare Mac that stays on is "a remote Mac" (a new or any one: "Restart a remote Mac."), "the remote Mac" (the one being talked about: "The remote Mac refused the connection.") and "remote Macs" (the saved list: "No remote Macs yet"). The possessive is "the remote Mac's": "the remote Mac's password", "the remote Mac's address".

**Plain "Mac".** Plain "Mac" is enough only where the reader already knows which Mac is meant:

- the sentence names it ("Attic has an older one", "Nobody is logged in at Attic's screen");
- it stands on that Mac's own page or section, or follows "Add a Mac…";
- it refers back to "a remote Mac" in the same sentence or the one before ("Change a power setting on a remote Mac. … you type the Mac's password into ssh.").

Sentences that already say "the Mac" this way keep it. This change never turns "remote Mac" into plain "Mac" to save words, because the command's messages and errors are often read without their page around them.

**"This Mac".** "This Mac" names only the Mac MacMosh runs on, the one you sit at. Where a sentence said "this workhorse" (pointing at the remote Mac being talked about), it becomes "this remote Mac", never "this Mac". Sentences that have both Macs keep "this Mac" for the daily Mac and "the remote Mac" for the other: "what is ready on this Mac and on the remote Mac". The two sentences that already used "This Mac" for the remote Mac are choice 6.

**Manner.** Each sentence keeps its meaning, its length and its manner: short, plain, British spelling, no new claims. The fewest words change. Where the plain swap reads badly, section 0 offers a better sentence as a choice.

**Not words a person reads.** Code names, file names, JSON keys and values, log lines that tests and CI read, command and flag names, and CI's own check names are not part of this change (sections 3 and 8). Comments in the code are not changed either, except the comments that quote a sentence this change rewrites, which are updated with it so they stay true (section 8, point 1, lists all 11).

## 2. Every sentence, before and after

One row per distinct sentence. "Pinned" says which tests hold the exact words today; those tests change with the sentence (section 6). Line numbers are today's `main`.

### Menu

| # | File and line | Before | After | Pinned |
|---|---|---|---|---|
| M1 | Sources/MacMoshKit/Menu/MenuModel.swift:123 | No workhorses yet | No remote Macs yet | MenuModelTests 1, ButtonRulesTests 1, MenuLogTests 1; 3 stored menu copies |

### Window (result lines, which the command shows too, and the Add a Mac page)

| # | File and line | Before | After | Pinned |
|---|---|---|---|---|
| W1 | Sources/MacMoshKit/Board/WindowActionRunner.swift:283 | Start again and keep it needs the workhorse script 0.5.0 or newer, and Attic has an older one. | Start again and keep it needs the MacMosh script 0.5.0 or newer, and Attic has an older one. (choice 2) | EndedDeskRunnerTests 1 |
| W2 | Sources/MacMoshKit/Format/DeskFormat.swift:174 | Naming a window needs the workhorse script 0.11.0 or newer, and Attic has 0.10.2. | Naming a window needs the MacMosh script 0.11.0 or newer, and Attic has 0.10.2. (choice 2) | NameWindowFlowTests 2 |
| W3 | Sources/MacMoshKit/Format/DeskFormat.swift:182 | Naming a new desk's first window needs the workhorse script 0.12.0 or newer, and Attic has an older one. | Naming a new desk's first window needs the MacMosh script 0.12.0 or newer, and Attic has an older one. (choice 2) | FirstWindowTests 2 |
| W4 | Sources/MacMoshKit/Board/WindowPage.swift:573 (Add a Mac page; no "workhorse" today) | At the other Mac, turn on these two in System Settings > General > Sharing: | At the remote Mac, turn on these two in System Settings > General > Sharing: (choice 7) | WindowPageTests 2 |
| W5 | WindowPage.swift:578 (Add a Mac page; no "workhorse" today) | The button below opens a terminal tab, where the first connection asks for the other Mac's password. MacMosh never sees it. | The button below opens a terminal tab, where the first connection asks for the remote Mac's password. MacMosh never sees it. (choice 7) | WindowPageTests 2 |

W1 to W3, H12 and H13 follow choice 2. The command adds "Update it with: macmosh prepare attic --fix" to W2 and W3; that part has no word to change. CI draws the Add a Mac page but checks only that the page is there, not its words.

### Sheets

No sheet holds the word. Every sheet's text comes from MacMoshKit, and none of it says "workhorse"; the new-desk sheet uses the Mac's name.

### Settings

| # | File and line | Before | After | Pinned |
|---|---|---|---|---|
| S1 | Sources/MacMoshKit/Board/SettingsPage.swift:75 | Remove MacMosh from this workhorse… | Remove MacMosh from this remote Mac… (choice 1) | SettingsPageTests 1 |
| S2 | SettingsPage.swift:76 | No workhorses yet. Add a Mac… in the sidebar adds one. | No remote Macs yet. Add a Mac… in the sidebar adds one. | SettingsPageTests 1 |
| S3 | SettingsPage.swift:134 (every Typing prediction choice) | Mosh can show what you type before the workhorse answers. | Mosh can show what you type before the remote Mac answers. | SettingsPageTests 1 |
| S4 | SettingsPage.swift:131 (Never only) | With Never, you see what you type only after the workhorse answers. | With Never, you see what you type only after the remote Mac answers. | SettingsPageTests 1 |

S3 and S4 keep "remote Mac" although they sit in the Mac's own section: "before the Mac answers" could be read as this Mac. Nine code comments and two CI comments quote S1, S2 or M1 and change with them (section 8, point 1).

### Checklist (`macmosh prepare`, and the tab that Run the checklist… opens)

| # | File and line | Before | After | Pinned |
|---|---|---|---|---|
| C1 | Sources/MacMoshKit/Format/ChecklistFormat.swift:13 | On the workhorse: | On the remote Mac: (choice 3) | none |
| C2 | ChecklistFormat.swift:33 | Fix, at the workhorse: | Fix, at the remote Mac: | ChecklistTests 1 |
| C3 | Sources/MacMoshKit/Setup/WorkhorseChecks.swift:77 (only in `--json`) | The workhorse answers ssh. | The remote Mac answers ssh. | none |
| C4 | WorkhorseChecks.swift:81 | 1. At the workhorse, turn on System Settings > General > Sharing > Remote Login. | 1. At the remote Mac, turn on System Settings > General > Sharing > Remote Login. | contains-only, survives |
| C5 | WorkhorseChecks.swift:92 | Screen Sharing is off, so Log in… and restart recovery can't show the workhorse's screen. | Screen Sharing is off, so Log in… and restart recovery can't show the remote Mac's screen. | none |
| C6 | WorkhorseChecks.swift:93 | 1. At the workhorse, turn on System Settings > General > Sharing > Screen Sharing. | 1. At the remote Mac, turn on System Settings > General > Sharing > Screen Sharing. | none |
| C7 | WorkhorseChecks.swift:106 | The workhorse turned MacMosh's key down. Pairing installs it; you type the workhorse's password into ssh once. | The remote Mac turned MacMosh's key down. Pairing installs it; you type the remote Mac's password into ssh once. | none |
| C8 | WorkhorseChecks.swift:171 | This MacMosh is older than the script on the workhorse. Update MacMosh. | This MacMosh is older than the script on the remote Mac. Update MacMosh. | ChecklistTests 1 |
| C9 | WorkhorseChecks.swift:268 | The firewall is on, so mosh may be blocked. If a desk won't open with mosh, use Plain ssh for this workhorse, or allow mosh-server in the firewall's options at the workhorse. MacMosh never changes the firewall. | The firewall is on, so mosh may be blocked. If a desk won't open with mosh, use Plain ssh for this remote Mac, or allow mosh-server in the firewall's options at the remote Mac. MacMosh never changes the firewall. | none |
| C10 | WorkhorseChecks.swift:279 | 1. At the workhorse, open System Settings > Privacy & Security > Full Disk Access. | 1. At the remote Mac, open System Settings > Privacy & Security > Full Disk Access. | contains-only, survives |
| C11 | Sources/MacMoshKit/Setup/DailyMacChecks.swift:63 | The key named in this workhorse's settings, ~/.ssh/id_garden, isn't there. | The key named in this remote Mac's settings, ~/.ssh/id_garden, isn't there. | none |
| C12 | DailyMacChecks.swift:80 | macOS asks once, the first time MacMosh reaches the workhorse on your home network. Choose Allow. | macOS asks once, the first time MacMosh reaches the remote Mac on your home network. Choose Allow. | none |
| C13 | DailyMacChecks.swift:90 | Tailscale is installed but not connected. Optional: it lets you reach the workhorse away from home. | Tailscale is installed but not connected. Optional: it lets you reach the remote Mac away from home. | none |
| C14 | DailyMacChecks.swift:93 | Tailscale isn't installed. Optional: it lets you reach the workhorse away from home. | Tailscale isn't installed. Optional: it lets you reach the remote Mac away from home. | none |

C4, C6 and C10 repeat "At the remote Mac" right under "Fix, at the remote Mac:", as today's words repeat "at the workhorse". Dropping the repeat would change more than the word, so it stays. C11 sits under "On this Mac:" but is about the remote Mac's saved settings; "this remote Mac's" keeps that clear. C8's neighbours name the Mac ("The script isn't on Attic yet."); naming it here too would need the name passed in, so the plain swap is proposed. Under the new heading "On the remote Mac:", the check that says "its own key on this Mac" (WorkhorseChecks.swift:113) reads more clearly than before and does not change.

### Command output (printed messages, questions, and the last line in a desk's tab)

| # | File and line | Before | After | Pinned |
|---|---|---|---|---|
| O1 | Sources/MacMoshKit/Format/StatusFormat.swift:6 | No workhorses yet. Run: macmosh pair <user@address> | No remote Macs yet. Run: macmosh pair <user@address> | StatusFormatTests 2 |
| O2 | Sources/MacMoshKit/Setup/Pairing.swift:99 and Sources/macmosh/AddCommand.swift:46 (two copies, change both) | At the workhorse, run this and compare: ssh-keygen -lf … | At the remote Mac, run this and compare: ssh-keygen -lf … | PairingTests 1 (the kit's copy) |
| O3 | Pairing.swift:105 | Next, ssh asks for the workhorse's password. You are typing into ssh; MacMosh can't see it. | Next, ssh asks for the remote Mac's password. You are typing into ssh; MacMosh can't see it. | PairingTests 2 |
| O4 | Pairing.swift:156 | Workhorse address: | Remote Mac address: | PairingTests 1 |
| O5 | Pairing.swift:168 | User name on the workhorse [alex]: | User name on the remote Mac [alex]: | PairingTests 1 |
| O6 | Pairing.swift:266 | The workhorse turned the key down. | The remote Mac turned the key down. | none |
| O7 | Pairing.swift:267 | The workhorse answered with a different host key. | The remote Mac answered with a different host key. | none |
| O8 | Pairing.swift:273 | The command on the workhorse exited with code 1. | The command on the remote Mac exited with code 1. | none |
| O9 | Sources/MacMoshKit/Setup/Removal.swift:111 | MacMosh is off the workhorse, but couldn't change its list: … | MacMosh is off the remote Mac, but couldn't change its list: … | none |
| O10 | Sources/MacMoshKit/Format/DeskFormat.swift:192 | The workhorse's report doesn't say which windows website has, so MacMosh can't ask which one. | The remote Mac's report doesn't say which windows website has, so MacMosh can't ask which one. | none |
| O11 | Sources/MacMoshKit/Connect/ConnectRunner.swift:64 | mosh-client ended with exit code 255. It couldn't connect, or the connection dropped. Your work keeps running on the workhorse. | mosh-client ended with exit code 255. It couldn't connect, or the connection dropped. Your work keeps running on the remote Mac. | none |
| O12 | ConnectRunner.swift:67 | ssh ended with exit code 4. The workhorse has no desk named website now. If it was renamed or removed, open it again from the menu. | ssh ended with exit code 4. The remote Mac has no desk named website now. If it was renamed or removed, open it again from the menu. | ConnectTests 1 |
| O13 | ConnectRunner.swift:161 (stand-in name when the Mac can't be found after a drop) | The workhorse · Locked after a restart | The remote Mac · Locked after a restart | none |

O13 is a stand-in used as a Mac's name, read in the tab's headline and placed inside hints. "The remote Mac" reads well as a headline; inside a hint it keeps today's capital "The", which is no worse than now (section 8).

### Command help (`--help`)

Each subcommand's description is seen twice: in the list under `macmosh --help` and at the top of that subcommand's own help.

| # | File and line | Before | After |
|---|---|---|---|
| H1 | Sources/macmosh/Macmosh.swift:8 | Drive a spare Mac that works as your workhorse. | Drive a spare Mac that runs your work. (choice 4) |
| H2 | Sources/macmosh/AddCommand.swift:8 | Save a workhorse and pin its ssh host key. Run macmosh pair next. | Save a remote Mac and pin its ssh host key. Run macmosh pair next. |
| H3 | AddCommand.swift:11 | The workhorse, as user@address (for example alex@workhorse). | The remote Mac, as user@address (for example alex@attic). |
| H4 | AddCommand.swift:17 | Print the saved workhorse as JSON. | Print the saved remote Mac as JSON. |
| H5 | Sources/macmosh/ConnectCommand.swift:30 | Open a desk on a workhorse in this terminal tab: over mosh, as iTerm2 tabs or over plain ssh. | Open a desk on a remote Mac in this terminal tab: over mosh, as iTerm2 tabs or over plain ssh. |
| H6 | ConnectCommand.swift:39 | How to connect: mosh, tabs or ssh. Leave it out to use the workhorse's setting. | How to connect: mosh, tabs or ssh. Leave it out to use the remote Mac's setting. |
| H7 | Sources/macmosh/DeskCommand.swift:32 | Make, rename, remove, add a window to or name a window of a desk on a workhorse. | Make, rename, remove, add a window to or name a window of a desk on a remote Mac. |
| H8 | DeskCommand.swift:47 | A new desk opens again by itself after the workhorse restarts, unless you say --no-reopen. | A new desk opens again by itself after the remote Mac restarts, unless you say --no-reopen. |
| H9 | DeskCommand.swift:60 | The folder on the workhorse, a full path or one starting with ~. Leave it out to pick from the projects folder. | The folder on the remote Mac, a full path or one starting with ~. Leave it out to pick from the projects folder. |
| H10 | DeskCommand.swift:63 | Open the desk again after the workhorse restarts. This is what happens anyway, unless you say --no-reopen. | Open the desk again after the remote Mac restarts. This is what happens anyway, unless you say --no-reopen. |
| H11 | DeskCommand.swift:66 | Don't open the desk again after the workhorse restarts. | Don't open the desk again after the remote Mac restarts. |
| H12 | DeskCommand.swift:183-184 | Names are not kept across a restart of the workhorse. Needs the workhorse script 0.11.0 or newer. | Names are not kept across a restart of the remote Mac. Needs the MacMosh script 0.11.0 or newer. (choice 2) |
| H13 | Sources/MacMoshKit/Host/DeskFlow.swift:51 (`desk new --window-name`; FirstWindowTests 1) | … With a workhorse script older than 0.12.0, only - or leaving it out works, and the window is named after the program running in it. | … With a MacMosh script older than 0.12.0, only - or leaving it out works, and the window is named after the program running in it. (choice 2) |
| H14 | Sources/macmosh/DesksCommand.swift:8 | List a workhorse's desks: name, windows and attached tabs. | List a remote Mac's desks: name, windows and attached tabs. |
| H15 | Sources/macmosh/FoldersCommand.swift:8 | List the folders inside a workhorse's projects folder. | List the folders inside a remote Mac's projects folder. |
| H16 | Sources/macmosh/ListCommand.swift:8 | List the workhorses MacMosh knows, without checking them. | List the remote Macs MacMosh knows, without checking them. |
| H17 | Sources/macmosh/PairCommand.swift:8 | Install MacMosh's own ssh key on a workhorse. You type its password into ssh once. | Install MacMosh's own ssh key on a remote Mac. You type its password into ssh once. |
| H18 | PairCommand.swift:11 | A saved workhorse, or user@address. Leave it out to pick from your Tailscale devices. | A saved remote Mac, or user@address. Leave it out to pick from your Tailscale devices. |
| H19 | PairCommand.swift:14 | The fingerprint you have already compared at the workhorse; skips the question. | The fingerprint you have already compared at the remote Mac; skips the question. |
| H20 | Sources/macmosh/PowerCommand.swift:10 | Change a power setting on a workhorse. It shows the exact command first; you type the Mac's password into ssh. | Change a power setting on a remote Mac. It shows the exact command first; you type the Mac's password into ssh. |
| H21 | Sources/macmosh/PrepareCommand.swift:8 | Run the setup checklist for a workhorse: what is ready on this Mac and on the workhorse, and how to fix the rest. | Run the setup checklist for a remote Mac: what is ready on this Mac and on the remote Mac, and how to fix the rest. |
| H22 | PrepareCommand.swift:28 | Install Homebrew on the workhorse. It shows Homebrew's own command and asks first; you type the Mac's password into ssh. | Install Homebrew on the remote Mac. It shows Homebrew's own command and asks first; you type the Mac's password into ssh. |
| H23 | Sources/macmosh/RemoveCommand.swift:8 | Take MacMosh off a workhorse and off this Mac's list. It lists what goes and asks first. | Take MacMosh off a remote Mac and off this Mac's list. It lists what goes and asks first. |
| H24 | RemoveCommand.swift:14 | Only remove it from this Mac's list. Nothing on the workhorse changes and no ssh call is made. | Only remove it from this Mac's list. Nothing on the remote Mac changes and no ssh call is made. |
| H25 | Sources/macmosh/RestartCommand.swift:8 | Restart a workhorse. It lists the desks that will close and asks first. | Restart a remote Mac. It lists the desks that will close and asks first. |
| H26 | Sources/macmosh/ScreenCommand.swift:8 | Open Screen Sharing at the address where the workhorse answers. | Open Screen Sharing at the address where the remote Mac answers. |
| H27 | Sources/macmosh/SetCommand.swift:8 | Change a workhorse's setting: name, mode, prediction, projects-folder or identity. | Change a remote Mac's setting: name, mode, prediction, projects-folder or identity. |
| H28 | Sources/macmosh/SettingsCommand.swift:8 | Change a setting that belongs to MacMosh itself, not to a workhorse. | Change a setting that belongs to MacMosh itself, not to a remote Mac. |
| H29 | Sources/macmosh/StatusCommand.swift:8 | Check a workhorse, or all of them, and say how each is. | Check a remote Mac, or all of them, and say how each is. |
| H30 | StatusCommand.swift:11 | The workhorse's id or name. Leave it out to check every workhorse. | The remote Mac's id or name. Leave it out to check every remote Mac. |
| H31 | 15 copies: ConnectCommand.swift:33, DesksCommand.swift:11, FoldersCommand.swift:11, PowerCommand.swift:13, PrepareCommand.swift:11, RemoveCommand.swift:11, RestartCommand.swift:11, ScreenCommand.swift:11, SetCommand.swift:11, UnlockCommand.swift:27, DeskCommand.swift:54, 114, 153, 188, 226 | The workhorse's id or name. | The remote Mac's id or name. |
| H32 | Sources/macmosh/UnlockCommand.swift:24 | Unlock a workhorse's disk after a restart. You type the Mac's password into ssh. | Unlock a remote Mac's disk after a restart. You type the Mac's password into ssh. |
| H33 | USAGE and ARGUMENTS of 17 subcommands (from `var workhorse`), and ArgumentParser's own error when the Mac is left out | macmosh restart <workhorse>; status and pair show [<workhorse>]; "Error: Missing expected argument '<workhorse>'" | macmosh restart <mac>; status and pair show [<mac>]; "Error: Missing expected argument '<mac>'" |

H20, H22 and H32 keep "the Mac's password": "the Mac" follows "a remote Mac" in the sentence before. H33 is made by giving each of the 17 arguments a value name for the help (ArgumentParser's `ArgumentHelp(valueName:)`), so the Swift property keeps its name. The same value name is what ArgumentParser prints when someone types, say, `macmosh restart` without a Mac: the error, its "Help:" line (H31's sentence) and its "Usage:" line all follow. Nothing pins the help: no test or CI job runs `--help`.

### Errors

| # | File and line | Before | After | Pinned |
|---|---|---|---|---|
| E1 | Sources/MacMoshKit/Host/HostCommands.swift:146 | The workhorse didn't answer within 15 seconds. | The remote Mac didn't answer within 15 seconds. | used by name only |
| E2 | Sources/MacMoshKit/Host/HostInstaller.swift:91 | … the workhorse didn't answer within 30 seconds. | … the remote Mac didn't answer within 30 seconds. | none |
| E3 | HostCommands.swift:163 | The workhorse turned MacMosh's key down. Check it with: macmosh status | The remote Mac turned MacMosh's key down. Check it with: macmosh status | DeskFormatWindowTests 3 |
| E4 | HostCommands.swift:165 | The workhorse's host key is different from the one MacMosh saved. Stop, and check at the Mac. | The remote Mac's host key is different from the one MacMosh saved. Stop, and check at the Mac. | none |
| E5 | HostCommands.swift:167 | MacMosh has no saved host key for this workhorse. Pair it again with: macmosh pair | MacMosh has no saved host key for this remote Mac. Pair it again with: macmosh pair | DeskFormatWindowTests 1 |
| E6 | HostCommands.swift:171 | The workhorse refused the connection. Is Remote Login on? | The remote Mac refused the connection. Is Remote Login on? | none |
| E7 | HostCommands.swift:173 | MacMosh couldn't find the workhorse's address. | MacMosh couldn't find the remote Mac's address. | none |
| E8 | HostCommands.swift:175 | ssh couldn't connect to the workhorse. | ssh couldn't connect to the remote Mac. | none |
| E9 | HostCommands.swift:187 | The script on the workhorse stopped with exit code 9. | The script on the remote Mac stopped with exit code 9. | none |
| E10 | Sources/MacMoshKit/Format/StatusFormat.swift:289 | More than one workhorse is called "Attic". Use its id: macmosh list | More than one remote Mac is called "Attic". Use its id: macmosh list | none |
| E11 | StatusFormat.swift:290 and Sources/MacMoshKit/Setup/Pairing.swift:212 (two copies, change both) | No workhorse called "Attic". Run: macmosh list | No remote Mac called "Attic". Run: macmosh list | none |
| E12 | Pairing.swift:187 | "attic" isn't a user name and an address. Check it and give both, like this: alex@workhorse | "attic" isn't a user name and an address. Check it and give both, like this: alex@attic | none |
| E13 | Pairing.swift:190 | … Stop. Don't type a password. Check at the workhorse with: ssh-keygen -lf … | … Stop. Don't type a password. Check at the remote Mac with: ssh-keygen -lf … | none |
| E14 | Pairing.swift:195 | ssh-copy-id stopped with code 1, so MacMosh's key may not be installed. Check the user name and that Remote Login is on at the workhorse, then run: macmosh pair alex@attic | … Check the user name and that Remote Login is on at the remote Mac, then run: macmosh pair alex@attic | none |
| E15 | Pairing.swift:198 | The key was copied, but signing in with it didn't work. Check that Remote Login is on at the workhorse, then run: macmosh pair alex@attic | … Check that Remote Login is on at the remote Mac, then run: macmosh pair alex@attic | none |
| E16 | Pairing.swift:208 | Tried ssh-keyscan at attic, and no ed25519 key came back. Check the address, and that Remote Login is on at the workhorse (System Settings > General > Sharing). | … Check the address, and that Remote Login is on at the remote Mac (System Settings > General > Sharing). | none |
| E17 | Pairing.swift:210 | Tried ssh-keyscan, and the answer wasn't an ed25519 key MacMosh can read. Check that the address is the workhorse. | Tried ssh-keyscan, and the answer wasn't an ed25519 key MacMosh can read. Check that the address is the remote Mac's. | none |
| E18 | Sources/MacMoshKit/Setup/PowerPlanner.swift:45 | Say whether to turn lid-closed mode on or off: macmosh power <workhorse> lid on, or macmosh power <workhorse> lid off. | Say whether to turn lid-closed mode on or off: macmosh power <mac> lid on, or macmosh power <mac> lid off. | PowerTests 1 |
| E19 | PowerPlanner.swift:47 | dark-wake takes no on or off. Only lid does: macmosh power <workhorse> lid on. | dark-wake takes no on or off. Only lid does: macmosh power <mac> lid on. | PowerTests 1 |
| E20 | Sources/macmosh/PairCommand.swift:39 | No workhorse was chosen. Run: macmosh pair alex@workhorse, with the workhorse's user name and address. | No remote Mac was chosen. Run: macmosh pair alex@attic, with the remote Mac's user name and address. | none |
| E21 | Sources/MacMoshKit/Connect/Recovery.swift:27 (no "workhorse" today; choice 6) | This Mac can't be unlocked over the network: that needs Apple silicon and macOS 26 or later. Unlock it at the Mac. | The remote Mac can't be unlocked over the network: that needs Apple silicon and macOS 26 or later. Unlock it at the Mac. | RecoveryTests 1 |
| E22 | PowerPlanner.swift:99 (no "workhorse" today; choice 6) | This setting is for laptops. This Mac has no battery, so it has no lid to close. | This setting is for laptops. The remote Mac has no battery, so it has no lid to close. | PowerTests 1 |

The window shows only the first sentence of E3 and E5. E1 is one shared constant; code compares against it by name, so a new text breaks no comparison. E12, E18 to E20 and H3 carry the placeholder and example-address decisions of section 0 ("What you approve", item 3).

### macOS's Local Network prompt

| # | File and line | Before | After |
|---|---|---|---|
| P1 | App/Info.plist:32 (NSLocalNetworkUsageDescription) | MacMosh checks on your workhorse over your home network. | MacMosh checks on your remote Mac over your home network. |

AppBundleTests only checks that the text is not empty.

### macmosh-host, the script on the remote Mac

| # | File and line | Before | After |
|---|---|---|---|
| R1 | host/macmosh-host:2, and its generated copy Sources/MacMoshKit/Host/HostScriptSource.swift:8 | # macmosh-host: the script MacMosh keeps on a workhorse (a Mac you reach from another Mac). | # macmosh-host: the script MacMosh keeps on a remote Mac (a Mac you reach from another Mac). |

This is a comment, read only by someone who opens the installed file. None of the messages the script prints contains the word. The generated copy is remade with `scripts/embed-host-script.sh`, which `scripts/check.sh` insists on. MacMosh compares installed scripts by version number only, so the script's version does not change and copies already installed keep the old comment until the next version (section 8).

### VoiceOver

No VoiceOver label holds the word except through the sample Mac's name ("Workhorse, Ready · 6 desks"), which is choice 5. Every other spoken label is built from the sentences above or from a Mac's own name.

### Rows in all

Menu 1, window 5, sheets 0, Settings 4, checklist 14, command output 13, help 33, errors 22, Local Network prompt 1, macmosh-host 1, VoiceOver 0: **94 rows**. Help row H31 stands for 15 identical copies, H33 for 17 arguments, and O2 and E11 for two copies each, so the builder edits about 126 places in the source, plus the 11 comments of section 8 and the generated copy of macmosh-host.

## 3. Typed and keyed names that hold the word

No command, subcommand or flag name holds the word, and neither do the keys `macmosh set` takes or the keys in the `status`, `list` and `add` JSON.

| Name | Where people meet it | What renaming would break | Recommendation |
|---|---|---|---|
| `workhorses.json` (Paths.swift:30) | In Finder, and inside "Can't read MacMosh's saved settings: workhorses.json: not JSON" | Every saved list on every install, unless MacMosh also reads the old file; SampleWindow.swift:53, 18 test lines in 11 files, drive-window.sh (18 places) and the sitting scripts | Keep |
| JSON key `"workhorses"` inside it (WorkhorseStore.swift:109) | Only someone reading the file | Reading every saved list, unless the old key is read too; drive-window.sh's readers (6) and the sitting scripts | Keep |
| `macmosh prepare --json` values `"side": "workhorse"` and `"fix": "atWorkhorse"` (Checklist.swift:10, 15) | Programs that read the checklist | Any such program; ChecklistTests decodes them | Keep |
| Tab-record key `"workhorse"` (TabRecord.swift:28) | Nobody; files on disk | Reading tab records written before the change | Keep |
| Log key `workhorses=N` in "menu refreshed: …" (MenuLog.swift:47) | The log | ci.yml:52, MenuLogTests 4, MenuRefresherTests 1 | Keep |
| Debug sample names `no-workhorses`, `two-workhorses` (SampleMenu.swift:24-25) | Debug builds and CI only | CI's three drive scripts, MenuBarPicturesTests, SampleWindowTests, CI's picture file names | Keep |
| Usage placeholder `<workhorse>` (17 subcommands) and in E18, E19 | `--help`, the missing-argument error, and two power errors | Nothing typed: the argument is positional. PowerTests' 2 lines change with E18 and E19 | Rename to `<mac>` for the reader only (decided with the document) |
| Example address `alex@workhorse` (H3, E12, E20) | Help and errors a person may copy | Nothing. The 57 test lines (in 12 Swift files) and 4 ssh fixture files that use `alex@workhorse` as sample input stay, as they are inputs, not the example | Change to `alex@attic` (decided with the document) |
| CI picture names (`workhorse-submenu`, `first-workhorse`, `second-workhorse`, `no-workhorse-settings`) | CI's results | Nothing outside CI | Keep |

"Rename with the old name still accepted" would only matter for the file name and the JSON keys; none needs renaming for the words people read, so none is proposed.

## 4. The sample Mac named "Workhorse"

**Where it appears.** CI draws its pictures from made-up Macs: Workhorse, Attic, Spare, Den, Loft and Shed.

- Defined once as `SampleMenu.main` (SampleMenu.swift:107: id `workhorse`, name `Workhorse`, address `workhorse`), and used by every menu sample and every window sample. A second sample name holds the word: `Workhorse-in-the-attic-by-the-window`, the sidebar's long name (SampleWindow.swift:101).
- Tests: about 30 lines name it (SampleMenuTests 7, SampleWindowTests 2 spoken labels, WindowPageTests 2, plus test-side copies in MenuStoredCopyTests, MenuTreeTests, MenuLogTests and SetTests) and about 18 more use its id or address.
- Stored menu copies: every-sample-menu.txt and s1-menu.txt each have one "Workhorse · Ready" block with about 10 action lines naming the id; step-1-menu.txt has 1 headline and 9 action lines.
- CI: drive-menu.sh compares the name in 3 lines and the id in 8 action strings; drive-window.sh compares the name in 3 lines, the id in 11 expected commands and 7 element ids.
- README.md:13: the window picture's alt text says "The one called Workhorse is Ready", and both README window pictures (light and dark) show the word three times: in the sidebar, as the page's headline, and in "Workhorse-in-th…".

**What a rename costs.** A rename to another made-up room name (say "Studio", as Attic, Spare, Den, Loft and Shed are taken) touches 2 source lines, about 48 test lines, re-records the 3 stored menu copies (their headers say they are never re-recorded without a reason, and this would be the reason), about 32 CI lines, the README alt text, and new README window pictures from CI's picture job. Nothing in the app a real user runs changes, but the README's first picture, the first thing a reader of the public repository sees, stops showing the word. Because this change already takes new README Settings pictures (section 5), new window pictures in the same pull request cost little.

**Recommendation.** Keep it in this change, so that the stored menu copies differ from today only by "No workhorses yet" (section 6). If the owner wants it gone (choice 5), rename it in its own pull request right after, with new README window pictures.

## 5. The guides and the README

**README.md**, 3 hits and 2 pictures:

- Line 20: the bridging sentence "MacMosh's own menus call it the workhorse." is removed. The first sentence of that bullet stays as it is.
- Line 75: "Its menu says `No workhorses yet`" becomes "Its menu says `No remote Macs yet`".
- Line 13: the alt text names the sample Mac; it follows choice 5.
- The Settings pictures docs/images/settings-light.png and settings-dark.png (line 36) show S1 ("Remove MacMosh from this workhorse…") and S3 ("…before the workhorse answers."). Both are replaced from CI's pictures after the change. Their alt text has no hit and stays. This holds whatever choice 5 says, because these pictures show only Attic and Spare.

**docs/lid-closed.md**, 51 hits on 38 lines:

- Title (1): "Running a workhorse with its lid closed" becomes "Running a remote Mac with its lid closed".
- Definition (2, lines 3 and 5): the plain swap on line 3 would read "a spare Mac laptop that you use as your remote Mac", so line 3 becomes "This guide is for a spare Mac laptop that runs your work and that you want to keep running with its lid shut."; line 5 becomes "The **remote Mac** is the laptop that runs your work. The **daily Mac** is the one you sit at…".
- Prose (29): "the workhorse" becomes "the remote Mac" ("plug the remote Mac into power", "type the remote Mac's login password", "Close the remote Mac's lid.", "one line per remote Mac"), including the troubleshooting rows at lines 110 and 116.
- The sample name the reader replaces (10): `workhorse · Ready`, `This runs on workhorse:`, `workhorse (id) · alex@192.168.1.20 · paired` and `macmosh power workhorse lid on`/`off` use the made-up name `attic` instead, as in "with your Mac's name in place of `attic`". This is a stand-in for the reader's own Mac's name, so "remote Mac" would not fit.
- The test record under "What this project saw" and "What was done" (7): reworded the same way. The guide is a living guide, not a history document; the facts stay the same.
- Issue #91's title, quoted twice (lines 176 and 230): kept as quoted, because it is the issue's real title on GitHub (section 8).

**docs/releasing.md**: no hits. **docs/first-run.md** and the other run records: history, unchanged (section 8).

**Two guide drafts** on the unmerged branch `docs/35-guides` (unlock-from-anywhere.md, 21 hits; fixed-home-address.md, 22 hits) need the same edit before they merge. They are not on `main`, so this change cannot touch them (section 8).

## 6. What pins the words, and what must stay true

**Tests that hold exact words** change with their sentence: 29 test lines in 13 files (DeskFormatWindowTests 4, PairingTests 5, SettingsPageTests 4, FirstWindowTests 3, StatusFormatTests 2, ChecklistTests 2, NameWindowFlowTests 2, PowerTests 2, ButtonRulesTests 1, ConnectTests 1, EndedDeskRunnerTests 1, MenuLogTests 1, MenuModelTests 1). With the recommended choices add RecoveryTests 1 and PowerTests 1 (choice 6) and WindowPageTests 4 (choice 7): 35 lines in 15 files. Two ChecklistTests checks look only for "Remote Login" and "Full Disk Access" inside a step and survive unchanged.

**Stored menu copies** (Tests/MacMoshKitTests/Fixtures/menu, compared by MenuStoredCopyTests): every-sample-menu.txt, s1-menu.txt and step-1-menu.txt each change one line, "No workhorses yet" to "No remote Macs yet". windows-menu.txt has the word only in a header comment, which stays.

**CI.** No CI check compares any sentence this change rewrites. ci.yml:52 checks the log line with `workhorses=0`, which stays. drive-window.sh:964 compares the unreadable-list sentence, where the word is only the file name, which stays. drive-window.sh finds the Add a Mac page by its element id, not its words. Two drive-window.sh check names (lines 2331 and 2508) quote the Settings button's words; they click it by its element id, so they pass either way (section 8).

**Not pinned**: the command's help, its two own messages, the checklist heading C1, P1, R1 and most error sentences. The builder checks those by reading the diff.

**Pictures.** CI's pictures are read after the change to see the new words in place: the menu with nothing saved, the Add a Mac page, Settings with a Mac and with none. The two README Settings pictures are then replaced from them (section 5).

**Two things that must still be true afterwards:**

1. Every stored menu copy differs from today's only by the line "No workhorses yet" becoming "No remote Macs yet": 3 lines in all, nothing else.
2. No check is weakened. Each changed test line changes only the expected words; no expectation is removed, loosened from exact to "contains", or skipped, and the number of expectations in each test file stays the same.

## 7. Words outside the repository (for the owner's eyes only)

The post drafts and the first blog post lean on the word, starting with the blog's title, "MacMosh: turning a spare Mac into a workhorse". Two alternatives:

1. "MacMosh: putting a spare Mac to work"
2. "MacMosh: driving a spare Mac from the one you sit at"

The drafts are rewritten after the owner says yes to this document, and come back to him for a separate yes before anything is posted.

## 8. Open points for the coordinator

1. **Comments in the code.** Rule: update only the comments that quote a rewritten sentence, so they stay true. There are 11: SettingsPage.swift:79, :296 and :372; Sources/MacMoshApp/Window/SettingsPageView.swift:19 and :394; ButtonRules.swift:155; Sources/MacMoshKit/Look/ButtonKind.swift:11 and :21; WindowPage.swift:475; and in CI, drive-window.sh:84 and :1020. The other ~350 comment lines that say "workhorse" stay. Recommended.
2. **The comment at the top of macmosh-host (R1).** Change it and regenerate the embedded copy, without bumping the script's version: installed copies keep the old comment until the next version, which harms nothing. Recommended. The other way is a version bump, which makes every `prepare --fix` reinstall the script for a comment.
3. **CI's own check names and log labels** (9 check names in drive-window.sh, 2 labels in drive-menu.sh, 1 in try-title.sh). Nothing compares them. Recommended: change only the two check names that quote the Settings button (lines 2331 and 2508), so they quote the new words; leave the rest, which describe the sample Mac or the script in CI's own words.
4. **The guide drafts on `docs/35-guides`.** Recommended: apply the same rule there, on that branch, before it merges; not in this change.
5. **Run records**: docs/first-run.md, docs/first-run-notes.md and docs/sittings/* describe past runs. Recommended: history under rule 6, unchanged. The same for the owner's one-off sitting scripts (scripts/sitting-1.sh and scripts/sitting-2/*.sh), unless a sitting is run again.
6. **Issue #91's title** ("Show when a lid-closed workhorse runs hot") is quoted in lid-closed.md. Renaming it is a GitHub edit, outside this step. Recommended: ask the owner separately; if he renames it, update the two quotes.
7. **macmosh-host's own "this Mac's screen"** (exit code 3, lines 457 and 1626) uses "this Mac" for the remote Mac. People never see it through MacMosh: the app turns exit code 3 into its own sentence naming the Mac ("Nobody is logged in at Attic's screen…"). Recommended: leave it.
8. **The stand-in name O13** keeps a capital "The" when a hint places it mid-sentence, as it does today. Recommended: leave that for a later fix.
9. **Choice 1 by name.** If the owner picks "Remove MacMosh from Attic…", the fixed text in SettingsWords becomes text built from the Mac's name, and SettingsPageTests' line follows. CI clicks the button by its element id either way.
10. **Choice 2 and the app's own versions.** If the owner keeps "the MacMosh script", watch for confusion once MacMosh's own releases carry version numbers near the script's (0.x). If it shows up, "macmosh-host" is the fallback, and it changes the same five sentences.
