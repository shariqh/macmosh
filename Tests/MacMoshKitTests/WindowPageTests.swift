import Foundation
import Testing
@testable import MacMoshKit

/// The workhorse Attic, whose user is alex.
private let attic = Workhorse.sample(id: "attic", name: "Attic", user: "alex", osVersion: "27.3", arch: "arm64")

/// The recorded report `Fixtures/status/desks-board.txt`, after `edit` has changed its text.
private func report(_ edit: (String) -> String = { $0 }) throws -> HostStatus {
    try HostStatus.parse(edit(fixture("status/desks-board.txt")))
}

private let checkedAt = utcDate(2027, 1, 15, 14, 2)
private let readyAt = utcDate(2027, 1, 15, 8, 57)

private func result(_ state: WorkhorseState, status: HostStatus?, at: Date = checkedAt,
                    workhorse: Workhorse = attic) -> CheckResult {
    .sample(state, workhorse: workhorse, status: status, homeReachable: status == nil ? nil : true, checkedAt: at)
}

/// Attic's block on the board, as `BoardModel.build` makes it.
private func boardWorkhorse(_ latest: CheckResult?, lastReady: CheckResult? = nil,
                            checking: Bool = false) throws -> BoardWorkhorse {
    let board = BoardModel.build(latest: latest.map { [$0.workhorse.id: $0] } ?? [:],
                                 lastReady: lastReady.map { [$0.workhorse.id: $0] } ?? [:],
                                 checking: checking ? ["attic"] : [], order: [attic], waitingForDeskServer: [],
                                 now: formatNow, timeZone: formatZone)
    return try #require(board.workhorses.first)
}

private func page(_ latest: CheckResult?, lastReady: CheckResult? = nil, checking: Bool = false) throws -> WorkhorsePage {
    WorkhorsePage(try boardWorkhorse(latest, lastReady: lastReady, checking: checking), now: formatNow,
                  timeZone: formatZone)
}

private func titles(_ buttons: [BoardButton]) -> [String] { buttons.map(\.title) }

@Suite struct WindowPageTests {
    // MARK: The words the window shows and the menu doesn't

    @Test func theWindowsNameAndTheMenuLine() {
        #expect(WindowWords.title == "MacMosh")
        #expect(WindowWords.windowID == "main")
        #expect(WindowWords.openLine == "Open MacMosh")
    }

    @Test func tabsAreCountedInWords() {
        #expect(WindowWords.tabs(0) == "No tab")
        #expect(WindowWords.tabs(1) == "In 1 tab")
        #expect(WindowWords.tabs(2) == "In 2 tabs")
        #expect(WindowWords.tabs(11) == "In 11 tabs")
    }

    @Test func theCheckedTimeIsTheMenusShortTime() {
        #expect(WindowWords.checked(utcDate(2027, 1, 15, 14, 2), now: formatNow, timeZone: formatZone) == "Checked 14:02")
        #expect(WindowWords.checked(utcDate(2027, 1, 14, 9, 5), now: formatNow, timeZone: formatZone)
                == "Checked yesterday 09:05")
        #expect(WindowWords.checking == "Checking…")
    }

    @Test func theFixedWordsAreTheDesigns() {
        #expect(WindowWords.keptWhenItExits == "Kept when it exits")
        #expect(WindowWords.doesntComeBack == "Doesn't come back after a restart")
        #expect(WindowWords.notMadeWithMacMosh == "Not made with MacMosh: folder and restart not known")
        #expect(WindowWords.closed == "(closed)")
        #expect(WindowWords.open == "Open")
        #expect(WindowWords.desks == "Desks")
        #expect(WindowWords.keepsItsCommandRunning == "Keeps its command running")
    }

    // MARK: A Ready workhorse's page

    @Test func aReadyPageHasTheHeaderTheDeskButtonsAndTheRarerButtonsAtTheFoot() throws {
        let p = try page(result(.ready(signIns: true), status: try report()))
        #expect(p.id == "attic")
        #expect(p.headline == "Attic · Ready")
        #expect(p.hint == nil)
        #expect(p.summary == "Sign-ins working · Awake on power · Lid-closed mode on · On power, 100%")
        #expect(p.checked == "Checked 14:02")
        #expect(p.checking == nil)
        #expect(p.checkNow == BoardButton(title: "Check now", action: .menu(.refresh)))
        #expect(p.underHint.isEmpty)
        #expect(p.desksHeading == "Desks")
        #expect(titles(p.deskButtons) == ["Open the 2 not in a tab", "New desk…"])
        #expect(titles(p.foot) == ["Share screen", "Turn off lid-closed mode…", "Restart…", "Run the checklist…"])
        #expect(p.home == "Home address reachable from here: yes")
        #expect(p.desks.map(\.name) == ["api", "blog", "garden", "notes", "recipes", "website"])
        #expect(p.noDesks == nil && p.stale == nil && p.result == nil)
    }

    /// Every button of the board is on the page once, in the board's order.
    @Test func everyButtonOfTheBoardIsOnThePageOnceInItsOrder() throws {
        let w = try boardWorkhorse(result(.ready(signIns: false), status: try report {
            $0.replacingOccurrences(of: "signins\tok", with: "signins\toff")
        }))
        let p = WorkhorsePage(w, now: formatNow, timeZone: formatZone)
        #expect(titles(p.underHint) == ["Fix…"])
        #expect(p.underHint + p.deskButtons + p.foot == w.buttons)
        #expect(p.hint == "Tools that keep logins in the keychain look signed out here.")
    }

    @Test func aCheckThatIsRunningSaysCheckingAndKeepsEverything() throws {
        let r = result(.ready(signIns: true), status: try report())
        let still = try page(r, lastReady: r, checking: true)
        let done = try page(r, lastReady: r)
        #expect(still.checking == "Checking…")
        #expect(still.checked == "Checked 14:02")
        var same = still
        same.checking = nil
        #expect(same == done)
    }

    @Test func aWorkhorseThatHasNeverAnsweredHasNoTimeAndOnlyTheChecklist() throws {
        let p = try page(nil, checking: true)
        #expect(p.headline == "Attic · Still checking…")
        // The headline already says it is checking, so the header doesn't say so twice.
        #expect(p.checked == nil && p.checking == nil)
        #expect(p.underHint.isEmpty && p.deskButtons.isEmpty && titles(p.foot) == ["Run the checklist…"])
        #expect(p.desksHeading == nil && p.desks.isEmpty && p.noDesks == nil && p.home == nil)
    }

    @Test func aReadyWorkhorseWithNoDesksSaysSo() throws {
        let empty = try report { text in
            text.split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.hasPrefix("desk\t") && !$0.hasPrefix("window") && !$0.hasPrefix("def\t") && !$0.hasPrefix("view\t") }
                .joined(separator: "\n")
        }
        let p = try page(result(.ready(signIns: true), status: empty))
        #expect(p.desks.isEmpty)
        #expect(p.noDesks == "No desks yet.")
        #expect(titles(p.deskButtons) == ["New desk…"])
    }

    // MARK: The desk rows

    private func rows() throws -> [String: DeskRow] {
        let p = try page(result(.ready(signIns: true), status: try report()))
        return Dictionary(uniqueKeysWithValues: p.desks.map { ($0.name, $0) })
    }

    @Test func anOpenDeskShowsItsWindowsItsTabsAndItsFolder() throws {
        let r = try rows()
        let website = try #require(r["website"])
        #expect(website.id == "website")
        #expect(website.windows == "claude, zsh, vim")
        #expect(website.tabs == "In 2 tabs")
        #expect(website.second == "~/Development/website")
        #expect(website.open == BoardButton(title: "Open", action: .menu(.tab(["connect", "attic", "website"]))))
        let api = try #require(r["api"])
        #expect(api.windows == "server, tests" && api.tabs == "In 1 tab" && api.second == "~/Development/api")
    }

    @Test func theSecondLineSaysOnlyWhatIsUnusual() throws {
        let r = try rows()
        #expect(r["garden"]?.second == "~/Development/garden · Kept when it exits")
        #expect(r["garden"]?.tabs == "No tab")
        #expect(r["recipes"]?.second == "/opt/projects/recipes · Doesn't come back after a restart")
        #expect(r["blog"]?.second == "Not made with MacMosh: folder and restart not known")
    }

    @Test func aClosedDeskSaysClosedAndHasNoTabCount() throws {
        let notes = try #require(try rows()["notes"])
        #expect(notes.windows == "(closed)")
        #expect(notes.tabs == nil)
        #expect(notes.second == "~/notes · Kept when it exits")
        #expect(notes.open?.action == .menu(.tab(["connect", "attic", "notes"])))
    }

    @Test func theDetailStripHasTheFourLinesAndTheButtons() throws {
        let website = try #require(try rows()["website"])
        #expect(website.detail == [
            DetailLine(label: "Folder", value: "~/Development/website"),
            DetailLine(label: "Starts with", value: "claude --continue"),
            DetailLine(label: "After a restart", value: "Comes back"),
            DetailLine(label: "When its last shell exits", value: "Remove the desk"),
        ])
        #expect(website.facts == ["Keeps its command running"])
        #expect(website.detailButtons == [
            BoardButton(title: "New window", action: .menu(.run(["desk", "window", "attic", "website"]))),
            BoardButton(title: "Rename…", action: .window(.rename(workhorse: "attic", desk: "website"))),
            BoardButton(title: "Remove…", action: .window(.remove(workhorse: "attic", desk: "website"))),
        ])
    }

    @Test func theDetailStripSaysAPlainShellKeptAndNotComingBack() throws {
        let r = try rows()
        #expect(r["api"]?.detail.first { $0.label == "Starts with" }?.value == "A plain shell")
        #expect(r["api"]?.facts == [])
        #expect(r["garden"]?.detail.last == DetailLine(label: "When its last shell exits", value: "Keep it, closed"))
        #expect(r["recipes"]?.detail.first { $0.label == "After a restart" }?.value == "Doesn't come back")
        // A closed desk has no window to add to.
        #expect(titles(r["notes"]?.detailButtons ?? []) == ["Rename…", "Remove…"])
    }

    /// A desk made by hand: nothing is known to show in the strip but its buttons.
    @Test func aDeskNotMadeWithMacMoshHasNoDetailLines() throws {
        let blog = try #require(try rows()["blog"])
        #expect(blog.detail.isEmpty && blog.facts.isEmpty)
        #expect(titles(blog.detailButtons) == ["New window", "Rename…", "Remove…"])
        #expect(blog.windows == "claude, zsh" && blog.tabs == "In 1 tab")
    }

    @Test func anOpenDeskWithNoWindowNamesCountsItsWindows() {
        let one = BoardDesk(name: "x", isOpen: true, windows: [BoardWindow(index: 0, name: "", id: nil, tabs: nil)],
                            windowCount: 1, tabsOpen: 0, folder: nil, command: nil, reopen: nil, keep: nil,
                            permanent: nil, madeByMacMosh: false, open: nil, buttons: [])
        #expect(DeskRow(one).windows == "1 window")
        var two = one
        two.windowCount = 2
        #expect(DeskRow(two).windows == "2 windows")
    }

    // MARK: Going to a tab, and a desk's windows, by the menu's rules (issue #134)

    /// The row's one button says "Go to" when a click goes to a tab, and "Open" for anything else.
    @Test func theRowsButtonSaysGoToOnlyWhenItGoesToATab() {
        #expect(WindowWords.goTo == "Go to" && WindowWords.open == "Open")
        #expect(WindowWords.openOrGoTo(.menu(.focus(label: "3f9a2c71e5b7d4a6", orOpen: ["connect", "attic", "notes"]))) == "Go to")
        let others: [BoardAction] = [
            .menu(.tab(["connect", "attic", "blog", "--window", "@8"])), .menu(.tab(["connect", "attic", "garden", "--view"])),
            .menu(.tabs([["connect", "attic", "api", "--window", "@5"]])), .menu(.tab(["connect", "attic", "website"])),
            .menu(.run(["desk", "window", "attic", "website"])), .window(.newDesk(workhorse: "attic")),
        ]
        for action in others { #expect(WindowWords.openOrGoTo(action) == "Open", "\(action)") }
    }

    /// The rows of the menu design's example, with the records and the time the menu's last build had.
    private func rowsWithTabs() throws -> [String: DeskRow] {
        let r = CheckResult.sample(.ready(signIns: true), workhorse: attic, status: windowsReport(), homeReachable: true,
                                   checkedAt: checkedAt)
        let board = BoardModel.build(latest: ["attic": r], lastReady: [:], checking: [], order: [attic],
                                     waitingForDeskServer: [],
                                     tabs: TabsSeen(tabs: TabsOnThisMac(records: windowsRecords, terminal: .iterm2), at: windowsNow),
                                     now: formatNow, timeZone: formatZone)
        let page = WorkhorsePage(try #require(board.workhorses.first), now: formatNow, timeZone: formatZone)
        return Dictionary(uniqueKeysWithValues: page.desks.map { ($0.name, $0) })
    }

    /// The row's button is "Open" or "Go to", with the menu's own words beside it for the help tag; the tabs are
    /// counted on the desk's windows; the strip lists each window with the menu's words and a small button.
    @Test func aDeskRowCarriesTheMenusActionsAndWords() throws {
        let r = try rowsWithTabs()
        func onWindow(_ desk: String, _ id: String) -> [String] { ["connect", "attic", desk, "--window", id] }
        let website = try #require(r["website"])
        #expect(website.open == BoardButton(title: "Open", action: .menu(.tabs([onWindow("website", "@3")]))))
        #expect(website.openWords == "Open the 1 window not in a tab")
        #expect(website.tabs == "In 2 tabs")
        #expect(website.windowLines == [
            WindowLine(id: "@1", words: "claude (in a tab)",
                       button: BoardButton(title: "Go to", action: .menu(.focus(label: "3f9a2c71e5b7d4a6",
                                                                               orOpen: onWindow("website", "@1"))))),
            WindowLine(id: "@2", words: "zsh (in a tab)",
                       button: BoardButton(title: "Go to", action: .menu(.focus(label: "b04e5d12c3a4f5e6",
                                                                               orOpen: onWindow("website", "@2"))))),
            WindowLine(id: "@3", words: "vim", button: BoardButton(title: "Open", action: .menu(.tab(onWindow("website", "@3"))))),
        ])
        #expect(website.detailButtons.map(\.title) == ["New window", "Rename…", "Remove…"])
        #expect(website.detailButtons.first?.action == .menu(.tab(["connect", "attic", "website", "--new-window"])))

        let notes = try #require(r["notes"])
        #expect(notes.open == BoardButton(title: "Go to", action: .menu(.focus(label: "c1d2e3f4a5b6c7d8",
                                                                              orOpen: onWindow("notes", "@7")))))
        #expect(notes.openWords == "Go to notes" && notes.tabs == "In 1 tab" && notes.windowLines.isEmpty)

        let api = try #require(r["api"])
        #expect(api.open?.title == "Open" && api.openWords == "Open api in 2 tabs" && api.tabs == "No tab")
        #expect(api.windowLines.map(\.words) == ["server", "tests"] && api.windowLines.map(\.button.title) == ["Open", "Open"])
        #expect(r["blog"]?.windowLines == [])   // one window: the row's button is that window's
        let garden = try #require(r["garden"])
        #expect(garden.open == BoardButton(title: "Open", action: .menu(.tab(["connect", "attic", "garden", "--view"]))))
        #expect(garden.openWords == "Open garden" && garden.tabs == nil)
        #expect(try #require(r["shop"]).windowLines.map(\.words) == ["web (open in another tab)", "db"])
    }

    /// Without the menu's tabs (before its first build), a row is what it was: Open, the desk's own connect, and
    /// no window lines.
    @Test func withoutTheMenusTabsARowIsWhatItWas() throws {
        let website = try #require(try rows()["website"])
        #expect(website.open == BoardButton(title: "Open", action: .menu(.tab(["connect", "attic", "website"]))))
        #expect(website.openWords == "Open website" && website.windowLines.isEmpty)
    }

    // MARK: The greyed list under a workhorse that is not Ready

    @Test func lockedHasItsHintItsOneButtonAndTheGreyedListWithItsHeading() throws {
        let ready = result(.ready(signIns: true), status: try report(), at: readyAt)
        let p = try page(result(.locked, status: nil), lastReady: ready)
        #expect(p.headline == "Attic · Locked after a restart")
        #expect(p.hint == "The disk is locked until someone types the Mac's password.")
        #expect(titles(p.underHint) == ["Unlock disk…  (you type the Mac's password)"])
        #expect(p.deskButtons.isEmpty && p.desks.isEmpty && p.desksHeading == nil && p.noDesks == nil)
        #expect(titles(p.foot) == ["Run the checklist…"])
        let stale = try #require(p.stale)
        #expect(stale.heading == "Desks before the restart (checked 08:57)")
        #expect(stale.lines == [
            "These come back once it is unlocked and logged in:",
            "api, garden, notes, website.",
            "These don't come back: blog, recipes.",
        ])
    }

    @Test func waitingForLoginPromisesALogIn() throws {
        let ready = result(.ready(signIns: true), status: try report(), at: readyAt)
        let waiting = try report { $0.replacingOccurrences(of: "console\talex", with: "console\t")
            .replacingOccurrences(of: "server\tup", with: "server\tdown") }
        let p = try page(result(.waitingForLogin, status: waiting), lastReady: ready)
        #expect(titles(p.underHint) == ["Log in…  (opens Screen Sharing)"])
        #expect(p.stale?.heading == "Desks before the restart (checked 08:57)")
        #expect(p.stale?.lines.first == "These come back once someone logs in:")
    }

    @Test func anyOtherStateListsTheDesksWithNoPromise() throws {
        let ready = result(.ready(signIns: true), status: try report(), at: readyAt)
        let p = try page(result(.cantVerify, status: nil), lastReady: ready)
        #expect(p.underHint.isEmpty)
        #expect(p.stale == StaleDesks(heading: "Desks at the last good check (08:57)",
                                      lines: ["api, blog, garden, notes, recipes, website."]))
    }

    @Test func oneDeskThatDoesntComeBackIsNamedSo() {
        let back = StaleDesks.lines(comingBack: ["api"], notComingBack: ["recipes"], after: "x:")
        #expect(back == ["x:", "api.", "This one doesn't come back: recipes."])
        #expect(StaleDesks.lines(comingBack: [], notComingBack: ["a", "b"], after: "x:") == ["These don't come back: a, b."])
        #expect(StaleDesks.lines(comingBack: ["a", "b"], notComingBack: [], after: "x:") == ["x:", "a, b."])
    }

    @Test func noGreyedListWithoutAReadyCheckSinceMacMoshStarted() throws {
        let p = try page(result(.locked, status: nil))
        #expect(p.stale == nil)
    }

    // MARK: The sidebar and the selection

    @Test func theSidebarListsEachWorkhorseWithItsSymbolThenAddAMac() throws {
        let den = Workhorse.sample(id: "den", name: "Den", user: "alex")
        let board = BoardModel.build(
            latest: ["attic": result(.ready(signIns: true), status: try report()),
                     "den": result(.locked, status: nil, workhorse: den)],
            lastReady: [:], checking: [], order: [attic, den], waitingForDeskServer: [], now: formatNow,
            timeZone: formatZone)
        #expect(SidebarItem.list(board) == [
            SidebarItem(selection: .workhorse("attic"), title: "Attic", symbol: "checkmark.circle"),
            SidebarItem(selection: .workhorse("den"), title: "Den", symbol: "lock.circle"),
            SidebarItem(selection: .addMac, title: "Add a Mac…", symbol: "plus"),
        ])
    }

    @Test func theSelectionIsTheFirstWorkhorseUnlessOneIsChosenAndStillThere() throws {
        let den = Workhorse.sample(id: "den", name: "Den", user: "alex")
        let board = BoardModel.build(latest: [:], lastReady: [:], checking: [], order: [attic, den],
                                     waitingForDeskServer: [], now: formatNow, timeZone: formatZone)
        #expect(WindowSelection.resolve(nil, board: board) == .workhorse("attic"))
        #expect(WindowSelection.resolve(.workhorse("den"), board: board) == .workhorse("den"))
        #expect(WindowSelection.resolve(.workhorse("gone"), board: board) == .workhorse("attic"))
        #expect(WindowSelection.resolve(.addMac, board: board) == .addMac)
    }

    @Test func withNoWorkhorseTheAddAMacPageIsSelected() {
        let empty = BoardModel.build(latest: [:], lastReady: [:], checking: [], order: [], waitingForDeskServer: [],
                                     now: formatNow, timeZone: formatZone)
        #expect(WindowSelection.resolve(nil, board: empty) == .addMac)
        #expect(WindowSelection.resolve(.workhorse("attic"), board: empty) == .addMac)
        #expect(SidebarItem.list(empty) == [SidebarItem(selection: .addMac, title: "Add a Mac…", symbol: "plus")])
    }

    /// A saved list that can't be read is not an empty one: the window says what the menu says, and
    /// doesn't invite the person to add a Mac. A list it read before stays on screen.
    @Test func anUnreadableListIsNotTheAddAMacPage() {
        let empty = BoardModel.build(latest: [:], lastReady: [:], checking: [], order: [], waitingForDeskServer: [],
                                     now: formatNow, timeZone: formatZone)
        #expect(WindowSelection.resolve(nil, board: empty, listUnreadable: true) == .unreadableList)
        #expect(WindowSelection.resolve(.addMac, board: empty, listUnreadable: true) == .unreadableList)
        #expect(WindowSelection.resolve(nil, board: empty, listUnreadable: false) == .addMac)
        let kept = BoardModel.build(latest: [:], lastReady: [:], checking: [], order: [attic], waitingForDeskServer: [],
                                    now: formatNow, timeZone: formatZone)
        #expect(WindowSelection.resolve(nil, board: kept, listUnreadable: true) == .workhorse("attic"))
    }

    // MARK: The Add a Mac page

    @Test func theAddAMacPageSaysWhatToSwitchOnAndHasTheMenusButton() {
        let p = AddMacPage.standard
        #expect(p.heading == "Add a Mac")
        #expect(p.lines == [
            "At the other Mac, turn on these two in System Settings > General > Sharing:",
            "Remote Login, so MacMosh can reach it.",
            "Screen Sharing, so you can log in to it after a restart.",
            "The button below opens a terminal tab, where the first connection asks for the other Mac's password. MacMosh never sees it.",
        ])
        #expect(p.button == BoardButton(title: "Add a Mac…", action: .menu(.tab(["pair"]))))
        #expect(p.button.title == ButtonRules.addAMac.title)
    }

    // MARK: While a window action runs (step 4)

    private func activePage(_ activity: WindowActivity, version: String = "0.8.0") throws -> WorkhorsePage {
        let status = try report { $0.replacingOccurrences(of: "macmosh-host\t1\t0.8.0", with: "macmosh-host\t1\t\(version)") }
        return WorkhorsePage(try boardWorkhorse(result(.ready(signIns: true), status: status)), now: formatNow,
                             timeZone: formatZone, activity: activity)
    }

    @Test func aDeskWithAnActionRunningSaysSoAndItsButtonsAreOff() throws {
        let p = try activePage(WindowActivity(busy: ["api": .rename]))
        let api = try #require(p.desks.first { $0.name == "api" })
        #expect(api.status == "Renaming…")
        #expect(api.detailButtons.map(\.title) == ["New window", "Renaming…", "Remove…"])
        #expect(api.detailButtons.allSatisfy { !$0.isEnabled })
        #expect(api.open?.isEnabled == false)
        // Another desk stays usable.
        let website = try #require(p.desks.first { $0.name == "website" })
        #expect(website.status == nil && website.detailButtons.allSatisfy(\.isEnabled) && website.open?.isEnabled == true)
        let removing = try activePage(WindowActivity(busy: ["website": .remove]))
        #expect(removing.desks.first { $0.name == "website" }?.detailButtons.last?.title == "Removing…")
    }

    @Test func newDeskIsOffWhileOneIsBeingMade() throws {
        let p = try activePage(WindowActivity(making: true))
        let newDesk = try #require(p.deskButtons.first { $0.action == .window(.newDesk(workhorse: "attic")) })
        #expect(newDesk.title == "Making…" && !newDesk.isEnabled)
        #expect(try activePage(WindowActivity()).deskButtons.allSatisfy(\.isEnabled))
    }

    @Test func aRowSaysUpdatingUntilTheCheckLands() throws {
        let p = try activePage(WindowActivity(updating: ["website", "gone"], arriving: ["garden-planner"]))
        #expect(p.desks.first { $0.name == "website" }?.status == "Updating…")
        #expect(p.desks.first { $0.name == "website" }?.hasStrip == true)
        // A new desk the check has not brought yet has a row of its own, in name order. A desk renamed or
        // removed has none once the check has taken it away.
        let names = p.desks.map(\.name)
        #expect(names == ["api", "blog", "garden", "garden-planner", "notes", "recipes", "website"])
        let placeholder = try #require(p.desks.first { $0.name == "garden-planner" })
        #expect(placeholder.status == "Updating…" && placeholder.windows == "" && placeholder.open == nil)
        #expect(placeholder.detailButtons.isEmpty && placeholder.second == "" && placeholder.detail.isEmpty)
        #expect(!placeholder.hasStrip)
        // Once the check has brought it, its own row says Updating… until the mark is taken off.
        let arrived = try activePage(WindowActivity(arriving: ["website"]))
        #expect(arrived.desks.filter { $0.name == "website" }.count == 1)
        #expect(arrived.desks.first { $0.name == "website" }?.status == "Updating…")
    }

    /// Section 7.2: Rename needs script 0.6.0, so with an older one its button is hidden.
    @Test func renameIsHiddenForAScriptOlderThan060() throws {
        let old = try activePage(WindowActivity(), version: "0.5.2")
        #expect(old.desks.first { $0.name == "website" }?.detailButtons.map(\.title) == ["New window", "Remove…"])
        #expect(old.canKeepClosed)
        let older = try activePage(WindowActivity(), version: "0.4.0")
        #expect(!older.canKeepClosed)
        let now = try activePage(WindowActivity(), version: "0.6.0")
        #expect(now.desks.first { $0.name == "website" }?.detailButtons.map(\.title) == ["New window", "Rename…", "Remove…"])
    }

    @Test func theResultLineIsTheWorkhorses() throws {
        let board = BoardModel.build(latest: ["attic": result(.ready(signIns: true), status: try report())], lastReady: [:],
                                     checking: [], order: [attic], waitingForDeskServer: [],
                                     results: ["attic": "Created the desk garden-planner on Attic."], now: formatNow, timeZone: formatZone)
        let p = WorkhorsePage(try #require(board.workhorses.first), now: formatNow, timeZone: formatZone)
        #expect(p.result == "Created the desk garden-planner on Attic.")
        // The menu's notice is the same sentence: the page shows it once.
        #expect(p.notice("Created the desk garden-planner on Attic.") == nil)
        #expect(p.notice("The tab didn't open.") == "The tab didn't open.")
    }
}
