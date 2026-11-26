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
        #expect(p.name == "Attic" && p.pill == StatePill(word: "Ready", tone: .ready))
    }

    /// Design 6.4: the foot keeps its buttons at the left in order, and Restart… alone at the right; one primary
    /// button on the page.
    @Test func theFootPutsRestartAloneAtTheRight() throws {
        let p = try page(result(.ready(signIns: true), status: try report()))
        #expect(titles(p.footLeft) == ["Share screen", "Turn off lid-closed mode…", "Run the checklist…"] && p.footRight?.title == "Restart…")
        #expect((p.underHint + p.deskButtons + p.foot).filter { ButtonKind.of($0.action) == .primary }.count == 1)
        let locked = try page(result(.locked, status: nil))
        #expect(titles(locked.footLeft) == ["Run the checklist…"] && locked.footRight == nil)
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
        #expect(website.windowWords == "claude, zsh, vim")
        #expect(website.state.word == "In 2 tabs")
        #expect(website.secondLine.whole == "~/Development/website")
        #expect(website.open == BoardButton(title: "Open", action: .menu(.tab(["connect", "attic", "website"]))))
        let api = try #require(r["api"])
        #expect(api.windowWords == "server, tests" && api.state.word == "In 1 tab" && api.secondLine.whole == "~/Development/api")
    }

    @Test func theSecondLineSaysOnlyWhatIsUnusual() throws {
        let r = try rows()
        #expect(r["garden"]?.secondLine.whole == "~/Development/garden · Kept when it exits")
        #expect(r["garden"]?.state.word == "No tab")
        #expect(r["recipes"]?.secondLine.whole == "/opt/projects/recipes · Doesn't come back after a restart")
        #expect(r["blog"]?.secondLine.help == "Not made with MacMosh: folder and restart not known")
    }

    @Test func aClosedDeskSaysClosedAndHasNoTabCount() throws {
        let notes = try #require(try rows()["notes"])
        #expect(notes.windowWords == "")
        #expect(notes.state.kind == .closed)
        #expect(notes.secondLine.whole == "~/notes · Kept when it exits")
        #expect(notes.open?.action == .menu(.tab(["connect", "attic", "notes"])))
    }

    @Test func theDetailStripHasTheThreeLinesAndTheButtons() throws {
        let website = try #require(try rows()["website"])
        #expect(website.detail == [
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
        #expect(blog.windowWords == "claude, zsh" && blog.state.word == "In 1 tab")
    }

    @Test func anOpenDeskWithNoWindowNamesCountsItsWindows() {
        let one = BoardDesk(name: "x", isOpen: true, windows: [BoardWindow(index: 0, name: "", id: nil, tabs: nil)],
                            windowCount: 1, tabsOpen: 0, folder: nil, command: nil, reopen: nil, keep: nil,
                            permanent: nil, madeByMacMosh: false, open: nil, buttons: [])
        #expect(DeskRow(one).windowWords == "1 window")
        var two = one
        two.windowCount = 2
        #expect(DeskRow(two).windowWords == "2 windows")
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
    private func rowsWithTabs(_ status: HostStatus = windowsReport(), mode: ConnectionMode = .mosh) throws -> [String: DeskRow] {
        let w = Workhorse.sample(id: "attic", name: "Attic", user: "alex", mode: mode)
        let r = CheckResult.sample(.ready(signIns: true), workhorse: w, status: status, homeReachable: true,
                                   checkedAt: checkedAt)
        let board = BoardModel.build(latest: ["attic": r], lastReady: [:], checking: [], order: [w],
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
        #expect(website.state.word == "In 2 tabs")
        #expect(website.windowLines == [
            WindowLine(id: "@1", title: "claude", state: .inTabs(1), help: "claude (in a tab)",
                       button: BoardButton(title: "Go to", action: .menu(.focus(label: "3f9a2c71e5b7d4a6",
                                                                               orOpen: onWindow("website", "@1"))))),
            WindowLine(id: "@2", title: "zsh", state: .inTabs(1), help: "zsh (in a tab)",
                       button: BoardButton(title: "Go to", action: .menu(.focus(label: "b04e5d12c3a4f5e6",
                                                                               orOpen: onWindow("website", "@2"))))),
            WindowLine(id: "@3", title: "vim", state: .notInATab, help: "vim",
                       button: BoardButton(title: "Open", action: .menu(.tab(onWindow("website", "@3"))))),
        ])
        #expect(website.detailButtons.map(\.title) == ["New window", "Rename…", "Remove…"])
        #expect(website.detailButtons.first?.action == .menu(.tab(["connect", "attic", "website", "--new-window"])))

        let notes = try #require(r["notes"])
        #expect(notes.open == BoardButton(title: "Go to", action: .menu(.focus(label: "c1d2e3f4a5b6c7d8",
                                                                              orOpen: onWindow("notes", "@7")))))
        #expect(notes.openWords == "Go to notes" && notes.state.word == "In 1 tab" && notes.windowLines.isEmpty)

        let api = try #require(r["api"])
        #expect(api.open?.title == "Open" && api.openWords == "Open api in 2 tabs" && api.state.word == "No tab")
        #expect(api.windowLines.map(\.title) == ["server", "tests"] && api.windowLines.map { $0.button?.title } == ["Open", "Open"])
        #expect(r["blog"]?.windowLines == [])   // one window: the row's button is that window's
        let garden = try #require(r["garden"])
        #expect(garden.open == BoardButton(title: "Open", action: .menu(.tab(["connect", "attic", "garden", "--view"]))))
        #expect(garden.openWords == "Open garden" && garden.state.kind == .closed)
        #expect(try #require(r["shop"]).windowLines.map(\.help) == ["web (open in another tab)", "db"])
    }

    // MARK: The opened details (look design 6.6)

    @Test func aWindowLineIsItsNameThenItsState() throws {
        let r = try rowsWithTabs()
        let website = try #require(r["website"])
        #expect(website.windowLines.map(\.title) == ["claude", "zsh", "vim"])
        #expect(website.windowLines.map(\.state) == [.inTabs(1), .inTabs(1), .notInATab])
        #expect(website.windowLines.map(\.help) == ["claude (in a tab)", "zsh (in a tab)", "vim"])
        #expect(website.windowLines.map(\.cell) == [.lit, .lit, .unlit])
        let shop = try #require(r["shop"])
        #expect(shop.windowLines.map(\.title) == ["web", "db"] && shop.windowLines.map(\.state) == [.inAnotherTab, .notInATab])
        #expect(shop.windowLines.first?.help == "web (open in another tab)" && shop.windowLines.first?.cell == .lit)
    }

    @Test func aWindowLineWithoutTheMenusFactsHasNoStateOrCell() throws {   // Review Focus 3
        let tabs = try rowsWithTabs(windowsReport(version: "0.11.0"), mode: .tabs)
        #expect(tabs["website"]?.windowLines.map(\.title) == ["claude", "zsh", "vim"])
        var seen = 0
        for row in tabs.values {
            for line in row.windowLines {
                #expect(line.state == nil && line.cell == nil && line.button == nil && line.name != nil && line.help == line.title,
                        "\(row.name)")
                seen += 1
            }
        }
        #expect(seen > 0)
        var twice = windowsReport(version: "0.11.0")   // a repeated name keeps the menu's "name (window N)" here too
        twice.desks[0].windows[1].name = "claude"
        #expect(try rowsWithTabs(twice, mode: .tabs)["website"]?.windowLines.map(\.title) == ["claude", "claude (window 1)", "vim"])
    }

    @Test func theFactsLeaveOutTheFolderTheRowShows() throws {
        let r = try rows()
        #expect(r["website"]?.detail == [DetailLine(label: "Starts with", value: "claude --continue"),
                                         DetailLine(label: "After a restart", value: "Comes back"),
                                         DetailLine(label: "When its last shell exits", value: "Remove the desk")])
        for row in r.values {
            #expect(!row.detail.contains { $0.label == "Folder" }, "\(row.name)")
            if !row.detail.isEmpty { #expect(row.secondLine.folder != nil, "\(row.name)") }
        }
    }

    @Test func theDetailsFootPutsRemoveAloneAtTheRight() throws {
        let r = try rowsWithTabs()
        let website = try #require(r["website"])
        #expect(titles(website.detailSplit.left) == ["New window", "Rename…"] && website.detailSplit.right?.title == "Remove…")
        #expect(titles(try #require(r["garden"]).detailSplit.left) == ["Rename…"])   // closed: no New window
        let named = try rowsWithTabs(windowsReport(version: "0.11.0"))
        let blog = try #require(named["blog"]).detailSplit   // one window: Name its window… at the left
        #expect(titles(blog.left).contains("Name its window…") && blog.right?.title == "Remove…")
        #expect(ButtonSplit([], apart: .destructive) == ButtonSplit(left: [], right: nil))
    }

    /// The first button of the kind stands apart and every other keeps its order at the left; with none of that kind,
    /// all stay at the left.
    @Test func aSplitTakesTheFirstOfItsKindAndKeepsTheRestInOrder() {
        let rename = BoardButton(title: "Rename…", action: .window(.rename(workhorse: "attic", desk: "api")))
        let remove = BoardButton(title: "Remove…", action: .window(.remove(workhorse: "attic", desk: "api")))
        let forget = BoardButton(title: "Forget", action: .window(.forget(workhorse: "attic", desk: "api")))
        #expect(ButtonSplit([rename, remove, forget], apart: .destructive) == ButtonSplit(left: [rename, forget], right: remove))
        #expect(ButtonSplit([rename], apart: .destructive) == ButtonSplit(left: [rename], right: nil))
    }

    /// Without the menu's tabs (before its first build), a row is what it was: Open, the desk's own connect, and
    /// no window lines.
    @Test func withoutTheMenusTabsARowIsWhatItWas() throws {
        let website = try #require(try rows()["website"])
        #expect(website.open == BoardButton(title: "Open", action: .menu(.tab(["connect", "attic", "website"]))))
        #expect(website.openWords == "Open website" && website.windowLines.isEmpty)
    }

    // MARK: The cells on a desk's tile (look design 6.5)

    /// An open desk "shop" made by hand, with `windows` windows w0… (ids @1…), each in `inTabs` tabs when given.
    private func desk(windows: Int, inTabs: [Int]?, tabsOpen: Int) -> BoardDesk {
        BoardDesk(name: "shop", isOpen: true,
                  windows: (0..<windows).map { i in
                      BoardWindow(index: i, name: "w\(i)", id: "@\(i + 1)", tabs: inTabs?[i], inTabs: inTabs?[i])
                  },
                  windowCount: windows, tabsOpen: tabsOpen, folder: nil, command: nil, reopen: nil, keep: nil,
                  permanent: nil, madeByMacMosh: false, open: nil, buttons: [])
    }

    @Test func eachWindowInATabLightsItsCell() throws {
        let r = try rowsWithTabs()
        #expect(r["website"]?.cells == DeskCells(cells: [.lit, .lit, .unlit], more: false) && r["garden"]?.cells.cells == [.hollow])
        #expect(r["api"]?.cells.cells == [.unlit, .unlit] && r["shop"]?.cells.cells == [.lit, .unlit])
        #expect(r["notes"]?.cells.cells == [.lit] && r["blog"]?.cells.cells == [.unlit])
        #expect(DeskCells.most == 6 && DeskCells.shownWithMore == 5)
    }

    @Test func withoutPerWindowCountsTheCellsLightFromTheFirst() throws {   // Review Focus 3
        let r = try rows()   // no menu tabs
        #expect(r["website"]?.cells == DeskCells(cells: [.lit, .lit, .unlit], more: false))
        #expect(r["blog"]?.cells == DeskCells(cells: [.lit, .unlit], more: false) && r["notes"]?.cells.cells == [.hollow])
        var seen = 0
        for (status, mode) in [(windowsReport(version: "0.1.0"), ConnectionMode.mosh), (windowsReport(), .tabs)] {
            for row in try rowsWithTabs(status, mode: mode).values where row.cells.cells != [.hollow] {
                let lit = row.cells.cells.prefix { $0 == .lit }.count
                #expect(row.cells.cells.dropFirst(lit).allSatisfy { $0 == .unlit }, "\(row.name)")
                seen += 1
            }
        }
        #expect(seen == 10)
        #expect(DeskCells(desk(windows: 3, inTabs: nil, tabsOpen: 12)) == DeskCells(cells: [.lit, .lit, .lit], more: false))
        // Counts known for some windows only: the fallback, from the first.
        var some = desk(windows: 3, inTabs: [0, 0, 1], tabsOpen: 1)
        some.windows[0].inTabs = nil
        #expect(DeskCells(some).cells == [.lit, .unlit, .unlit])
    }

    @Test func nineWindowsShowFiveCellsAndThePlus() {   // Review Focus 2
        let nine = desk(windows: 9, inTabs: [0, 1, 0, 0, 0, 0, 0, 1, 0], tabsOpen: 2)
        #expect(DeskCells(nine) == DeskCells(cells: [.unlit, .lit, .unlit, .unlit, .unlit], more: true) && DeskRow(nine).state.word == "In 2 tabs")
        #expect(DeskRow(nine).state == DeskStateCell(word: "In 2 tabs", kind: .inTabs))
        #expect(DeskCells(desk(windows: 9, inTabs: nil, tabsOpen: 7)) == DeskCells(cells: Array(repeating: .lit, count: 5), more: true))
        #expect(DeskCells(desk(windows: 6, inTabs: nil, tabsOpen: 0)) == DeskCells(cells: Array(repeating: .unlit, count: 6), more: false))
        #expect(DeskCells(desk(windows: 7, inTabs: nil, tabsOpen: 0)).cells.count == 5)
    }

    /// An open desk the report gives no window for has no cells; nor has the row of a desk just made.
    @Test func noWindowsNoCells() throws {
        #expect(DeskCells(desk(windows: 0, inTabs: nil, tabsOpen: 0)) == DeskCells(cells: [], more: false))
        let arriving = try activePage(WindowActivity(arriving: ["garden-planner"]))
        #expect(arriving.desks.first { $0.name == "garden-planner" }?.cells == DeskCells(cells: [], more: false))
    }

    // MARK: The row's state cell, second line, tag and spoken label (look design 6.5)

    @Test func eachRowSaysItsStateInItsCell() throws {
        #expect(WindowWords.madeByHand == "Made by hand" && WindowWords.closedState == "Closed")
        let r = try rows()
        #expect(r["website"]?.state == DeskStateCell(word: "In 2 tabs", kind: .inTabs))
        #expect(r["garden"]?.state == DeskStateCell(word: "No tab", kind: .noTab))
        #expect(r["notes"]?.state == DeskStateCell(word: "Closed", kind: .closed))
        #expect(r["notes"]?.windowWords == "")
        #expect(r["website"]?.windowWords == "claude, zsh, vim" && r["blog"]?.windowWords == "claude, zsh")
        let busy = try activePage(WindowActivity(busy: ["api": .rename], arriving: ["garden-planner"]))
        #expect(busy.desks.first { $0.name == "api" }?.state == DeskStateCell(word: "Renaming…", kind: .busy))
        let arriving = try #require(busy.desks.first { $0.name == "garden-planner" })
        #expect(arriving.state == DeskStateCell(word: "Updating…", kind: .busy) && arriving.cells.cells.isEmpty)
        #expect(arriving.windowWords == "" && arriving.secondLine.whole == "" && arriving.spokenLabel == "garden-planner, Updating…")
        let updating = try activePage(WindowActivity(updating: ["website"]))
        #expect(updating.desks.first { $0.name == "website" }?.state == DeskStateCell(word: "Updating…", kind: .busy))
        #expect(DeskStateKind.inTabs.textRole == .good && DeskStateKind.closed.textRole == .secondary)
        #expect(DeskStateKind.noTab.textRole == .secondary && DeskStateKind.busy.textRole == .secondary)
    }

    @Test func anOpenDeskWithNoWindowNamesSaysHowManyWindows() {
        let one = BoardDesk(name: "x", isOpen: true, windows: [BoardWindow(index: 0, name: "", id: nil, tabs: nil)],
                            windowCount: 1, tabsOpen: 0, folder: nil, command: nil, reopen: nil, keep: nil, permanent: nil,
                            madeByMacMosh: false, open: nil, buttons: [])
        #expect(DeskRow(one).windowWords == "1 window" && DeskRow(one).spokenLabel == "x, 1 window, Made by hand, No tab")
    }

    @Test func aHandMadeDeskHasTheTagWithTodaysSentenceAsHelp() throws {
        let blog = try #require(try rows()["blog"])
        #expect(blog.secondLine.tag == "Made by hand" && blog.secondLine.whole == "Made by hand" && blog.secondLine.fitted(4) == "Made by hand")
        #expect(blog.secondLine.help == "Not made with MacMosh: folder and restart not known")
        #expect(blog.secondLine.folder == nil && blog.secondLine.facts.isEmpty)
    }

    @Test func theFolderIsCutInTheMiddleAndTheFactsStay() throws {
        let recipes = try #require(try rows()["recipes"]).secondLine
        #expect(recipes.folder == "/opt/projects/recipes" && recipes.facts == ["Doesn't come back after a restart"] && recipes.tag == nil)
        #expect(recipes.whole == "/opt/projects/recipes · Doesn't come back after a restart" && recipes.fitted(57) == recipes.whole)
        #expect(recipes.fitted(46) == "/opt…cipes · Doesn't come back after a restart")
        #expect(recipes.fitted(10) == "/o…es · Doesn't come back after a restart")
        #expect(recipes.help == recipes.whole)
        let website = try #require(try rows()["website"]).secondLine
        #expect(website.fitted(12) == "~/Dev…ebsite" && website.help == "~/Development/website")
        #expect(website.ladder.first == website.whole)
    }

    @Test func aLongFolderIsCutOnlyAsFarAsTheRoomNeeds() throws {
        let recipes = try #require(try rows()["recipes"]).secondLine
        let ladder = recipes.ladder
        #expect(ladder.first == recipes.whole && ladder.last == recipes.fitted(0))
        #expect(zip(ladder, ladder.dropFirst()).allSatisfy { $0.count == $1.count + 1 })
        #expect(ladder.allSatisfy { $0.hasSuffix(" · Doesn't come back after a restart") })
        #expect(ladder.count == recipes.whole.count - recipes.fitted(0).count + 1)
        #expect(try #require(try rows()["blog"]).secondLine.ladder == ["Made by hand"])
    }

    @Test func theWindowNamesAreCutOnlyWhenAFewLettersStay() throws {
        let r = try rows()
        #expect(r["website"]?.windowWordsAtFewest == "clau…" && r["notes"]?.windowWordsAtFewest == "")
        let one = BoardDesk(name: "x", isOpen: true, windows: [BoardWindow(index: 0, name: "zsh", id: "@1", tabs: 1)], windowCount: 1,
                            tabsOpen: 1, folder: nil, command: nil, reopen: nil, keep: nil, permanent: nil, madeByMacMosh: false,
                            open: nil, buttons: [])
        #expect(DeskRow(one).windowWordsAtFewest == "zsh")
    }

    @Test func theSpokenLabelIsNameWindowsSecondLineThenState() throws {
        let r = try rows()
        #expect(r["website"]?.spokenLabel == "website, claude, zsh, vim, ~/Development/website, In 2 tabs")
        #expect(r["blog"]?.spokenLabel == "blog, claude, zsh, Made by hand, In 1 tab")
        #expect(r["notes"]?.spokenLabel == "notes, ~/notes · Kept when it exits, Closed")
        // CI reads a row's label from its start: the name, then the window names (look design 3).
        for row in r.values where !row.windowWords.isEmpty {
            #expect(row.spokenLabel.hasPrefix("\(row.name), \(row.windowWords), "), "\(row.name)")
        }
    }

    @Test func aLongNameStaysWholeAndTheSecondLineKeepsItsFacts() {   // Review Focus 1
        let long = "garden-planner-for-the-allotment-by-the-river"
        let d = BoardDesk(name: long, isOpen: true, windows: [BoardWindow(index: 0, name: "zsh", id: "@1", tabs: 1)],
                          windowCount: 1, tabsOpen: 1, folder: "~/Development/\(long)", command: nil, reopen: true,
                          keep: false, permanent: true, madeByMacMosh: true, open: nil, buttons: [])
        let row = DeskRow(d)
        #expect(row.spokenLabel == "\(long), zsh, ~/Development/\(long) · Kept when it exits, In 1 tab")
        #expect(row.secondLine.fitted(40).hasSuffix(" · Kept when it exits") && row.secondLine.fitted(40).count == 40)
        #expect(row.secondLine.help == "~/Development/\(long) · Kept when it exits")
        #expect(LookSize.nameMaxWidth == 200)
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
            SidebarItem(selection: .settings, title: "Settings", symbol: "gearshape"),
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
        #expect(SidebarItem.list(empty) == [SidebarItem(selection: .addMac, title: "Add a Mac…", symbol: "plus"),
                                            SidebarItem(selection: .settings, title: "Settings", symbol: "gearshape")])
    }

    /// Settings stays chosen whatever the board holds (issue 157): with workhorses, with none, and with a saved list
    /// that can't be read, where its page shows This Mac's terminal and the store's sentence in place of the
    /// workhorses' sections.
    @Test func settingsStaysChosenWithOrWithoutWorkhorsesAndWithAnUnreadableList() {
        let empty = BoardModel.build(latest: [:], lastReady: [:], checking: [], order: [], waitingForDeskServer: [],
                                     now: formatNow, timeZone: formatZone)
        let kept = BoardModel.build(latest: [:], lastReady: [:], checking: [], order: [attic], waitingForDeskServer: [],
                                    now: formatNow, timeZone: formatZone)
        #expect(WindowSelection.resolve(.settings, board: kept) == .settings)
        #expect(WindowSelection.resolve(.settings, board: empty) == .settings)
        #expect(WindowSelection.resolve(.settings, board: empty, listUnreadable: true) == .settings)
        #expect(WindowSelection.resolve(.settings, board: kept, listUnreadable: true) == .settings)
        // Nothing chosen still opens on the first workhorse, Add a Mac, or the store's sentence.
        #expect(WindowSelection.resolve(nil, board: empty, listUnreadable: true) == .unreadableList)
    }

    /// A saved list that can't be read is not an empty one: the window says what the menu says, and
    /// doesn't invite the person to add a Mac. A list it read before stays on screen.
    /// Look design 6.7: a heading, the menu's sentence, then the next step; the two fixed parts are proposed, and the
    /// owner approves them in the pull request.
    @Test func anUnreadableListHasAHeadingTheSentenceAndANextStep() {
        let problem = StatusFormat.storeMessage(StoreError.unreadable("workhorses.json: not JSON"))
        #expect(ListProblemPage(problem: problem) == ListProblemPage(
            heading: "MacMosh can't list your Macs", problem: "Can't read MacMosh's saved settings: workhorses.json: not JSON",
            nextStep: "Once the file can be read again, your Macs come back at the next check."))
        let newer = ListProblemPage(problem: StatusFormat.storeMessage(StoreError.newerVersion(2)))
        #expect(newer.problem == "MacMosh's saved settings are from a newer version (2). Update MacMosh."
                && newer.heading == ListProblemPage.headingWords && newer.nextStep == ListProblemPage.nextStepWords)
    }

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
        #expect(api.state == DeskStateCell(word: "Renaming…", kind: .busy))
        #expect(api.detailButtons.map(\.title) == ["New window", "Renaming…", "Remove…"])
        #expect(api.detailButtons.allSatisfy { !$0.isEnabled })
        #expect(api.open?.isEnabled == false)
        // Another desk stays usable.
        let website = try #require(p.desks.first { $0.name == "website" })
        #expect(website.state.kind != .busy && website.detailButtons.allSatisfy(\.isEnabled) && website.open?.isEnabled == true)
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
        #expect(p.desks.first { $0.name == "website" }?.state == DeskStateCell(word: "Updating…", kind: .busy))
        #expect(p.desks.first { $0.name == "website" }?.hasStrip == true)
        // A new desk the check has not brought yet has a row of its own, in name order. A desk renamed or
        // removed has none once the check has taken it away.
        let names = p.desks.map(\.name)
        #expect(names == ["api", "blog", "garden", "garden-planner", "notes", "recipes", "website"])
        let placeholder = try #require(p.desks.first { $0.name == "garden-planner" })
        #expect(placeholder.state == DeskStateCell(word: "Updating…", kind: .busy) && placeholder.windowWords == ""
                && placeholder.open == nil)
        #expect(placeholder.detailButtons.isEmpty && placeholder.secondLine.whole == "" && placeholder.detail.isEmpty)
        #expect(!placeholder.hasStrip)
        // Once the check has brought it, its own row says Updating… until the mark is taken off.
        let arrived = try activePage(WindowActivity(arriving: ["website"]))
        #expect(arrived.desks.filter { $0.name == "website" }.count == 1)
        #expect(arrived.desks.first { $0.name == "website" }?.state == DeskStateCell(word: "Updating…", kind: .busy))
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

    // MARK: The result slot (look design 6.3)

    /// Attic's Ready page with that result line and kind.
    private func pageWithResult(_ sentence: String, kind: ResultKind) throws -> WorkhorsePage {
        let board = BoardModel.build(latest: ["attic": result(.ready(signIns: true), status: try report())], lastReady: [:],
                                     checking: [], order: [attic], waitingForDeskServer: [],
                                     results: ["attic": sentence], resultKinds: ["attic": kind], now: formatNow,
                                     timeZone: formatZone)
        return WorkhorsePage(try #require(board.workhorses.first), now: formatNow, timeZone: formatZone)
    }

    @Test func theResultSlotHoldsTheResultOrTheNotice() throws {
        let made = "Created the desk garden-planner on Attic.", tab = "The tab didn't open."
        let p = try pageWithResult(made, kind: .done)
        #expect(p.resultKind == .done && p.result == made)
        let alone = ResultSlot(sentence: made, kind: .done, isResult: true, notice: nil, sentenceLines: 2)
        #expect(p.resultSlot(notice: nil) == alone && p.resultSlot(notice: made) == alone)
        #expect(p.resultSlot(notice: tab) == ResultSlot(sentence: made, kind: .done, isResult: true, notice: tab, sentenceLines: 1))
        let none = try page(result(.ready(signIns: true), status: try report()))
        #expect(none.resultKind == nil)
        #expect(none.resultSlot(notice: nil) == nil)
        #expect(none.resultSlot(notice: tab) == ResultSlot(sentence: tab, kind: nil, isResult: false, notice: nil, sentenceLines: 2))
    }

    @Test func aLongFailedResultKeepsItsWholeSentenceInTwoLines() throws {   // Review Focus 5
        let long = "The desk garden-planner wasn't made. Attic already has a desk with that name. Pick another name."
        let slot = try #require(try pageWithResult(long, kind: .failed).resultSlot(notice: long))
        #expect(slot.sentence == long && slot.kind == .failed && slot.sentenceLines == 2 && slot.notice == nil)
        #expect(ResultKind.failed.textRole == .cannot && ResultKind.done.textRole == .secondary)
    }

    /// A call that passed the time limit may still have worked: neither done nor failed, in secondary words.
    @Test func aTimedOutResultIsNeitherDoneNorFailed() throws {
        let unsure = "MacMosh didn't hear back from Attic about website within 15 seconds. The next check shows whether it was removed."
        let slot = try #require(try pageWithResult(unsure, kind: .unknown).resultSlot(notice: unsure))
        #expect(slot == ResultSlot(sentence: unsure, kind: .unknown, isResult: true, notice: nil, sentenceLines: 2))
        #expect(ResultKind.unknown.textRole == .secondary)
    }
}
