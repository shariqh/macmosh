import Foundation
import Testing
@testable import MacMoshKit

/// The rules for which buttons go with which state, read by the menu and (later) the window.
@Suite struct ButtonRulesTests {
    private func titles(_ buttons: [ActionButton]) -> [String] { buttons.map(\.title) }

    @Test func eachStateGetsItsOwnButtonsUnderTheHint() {
        let able = Workhorse.sample(osVersion: "27.3", arch: "arm64")
        let old = Workhorse.sample(osVersion: "15.6", arch: "arm64")
        let rows: [(WorkhorseState, Workhorse, [ActionButton])] = [
            (.ready(signIns: true), .sample(), []),
            (.ready(signIns: false), .sample(),
             [ActionButton(key: "fix", title: "Fix…", action: .tab(["prepare", "mbp", "--restart-desk-server", "--pause"]))]),
            (.waitingForLogin, .sample(),
             [ActionButton(key: "login", title: "Log in…  (opens Screen Sharing)", action: .run(["screen", "mbp"]))]),
            (.locked, able,
             [ActionButton(key: "unlock", title: "Unlock disk…  (you type the Mac's password)", action: .tab(["unlock", "mbp"]))]),
            (.locked, old, []),
            (.cantVerify, .sample(), []),
            (.cantReach(.nothingAnswers), .sample(), []),
            (.notSetUp(.notPaired), .sample(),
             [ActionButton(key: "pair", title: "Pair…", action: .tab(["pair", "mbp"]))]),
            (.notSetUp(.deskServerDown), .sample(),
             [ActionButton(key: "finish", title: "Finish setting up…", action: .tab(["prepare", "mbp", "--fix", "--pause"]))]),
            (.notSetUp(.hostScriptMissing), .sample(),
             [ActionButton(key: "finish", title: "Finish setting up…", action: .tab(["prepare", "mbp", "--fix", "--pause"]))]),
        ]
        for (state, w, want) in rows {
            #expect(ButtonRules.forState(.sample(state, workhorse: w, status: .sampleWithDesk)) == want, "\(state)")
        }
    }

    @Test func aReadyWorkhorseGetsNewDeskShareAndRestart() {
        var desktop = HostStatus.sampleWithDesk
        desktop.battery = .init(present: false, onAC: nil, percent: nil)
        let r = CheckResult.sample(.ready(signIns: true), status: desktop)
        #expect(ButtonRules.forReady(r) == [
            ActionButton(key: "newDesk", title: "New desk…", action: .tab(["desk", "new", "mbp"])),
            ActionButton(key: "share", title: "Share screen", action: .run(["screen", "mbp"])),
            ActionButton(key: "restart", title: "Restart…", action: .tab(["restart", "mbp"])),
        ])
    }

    @Test func aWorkhorseThatIsNotReadyGetsNoReadyButtons() {
        for state in [WorkhorseState.waitingForLogin, .locked, .cantReach(.nothingAnswers), .notSetUp(.notPaired)] {
            #expect(ButtonRules.forReady(.sample(state, status: .sampleWithDesk)).isEmpty, "\(state)")
        }
    }

    /// Changed on purpose for issue #107: the lid switch comes before Restart…, the menu's order.
    @Test func aLaptopAlsoGetsItsLidSwitch() {
        for (lid, title, word) in [(1, "Turn off lid-closed mode…", "off"), (0, "Turn on lid-closed mode…", "on")] as [(Int?, String, String)] {
            var status = HostStatus.sampleWithDesk
            status.power.disableSleep = lid
            let buttons = ButtonRules.forReady(.sample(.ready(signIns: true), status: status))
            #expect(titles(buttons) == ["New desk…", "Share screen", title, "Restart…"])
            #expect(buttons[2] == ActionButton(key: "lid", title: title, action: .tab(["power", "mbp", "lid", word])))
        }
        var unknown = HostStatus.sampleWithDesk
        unknown.power.disableSleep = nil
        #expect(titles(ButtonRules.forReady(.sample(.ready(signIns: true), status: unknown)))[2] == "Turn on lid-closed mode…")
    }

    /// Changed on purpose for issue #107: a desk's buttons start with Open (what a click on the desk's row
    /// does too), and the window line reads New window, since it is in the desk's own submenu.
    @Test func anOpenDeskGetsANewWindowLineAndAClosedOneDoesNot() {
        #expect(ButtonRules.forDesk(workhorse: "mbp", desk: "website", isOpen: true) == [
            ActionButton(key: "open", title: "Open website", action: .tab(["connect", "mbp", "website"])),
            ActionButton(key: "window", title: "New window", action: .run(["desk", "window", "mbp", "website"])),
            ActionButton(key: "rename", title: "Rename website…", action: .tab(["desk", "rename", "mbp", "website"])),
            ActionButton(key: "remove", title: "Remove website…", action: .tab(["desk", "remove", "mbp", "website", "--ask"])),
        ])
        #expect(titles(ButtonRules.forDesk(workhorse: "mbp", desk: "notes", isOpen: false))
                == ["Open notes", "Rename notes…", "Remove notes…"])
        #expect(ButtonRules.connect(workhorse: "mbp", desk: "website") == .tab(["connect", "mbp", "website"]))
    }

    /// The headline's submenu (issue #107): Share screen, a laptop's lid-closed switch, Restart…. New desk…
    /// stays at the top level. None in any other state.
    @Test func aReadyHeadlineGetsShareTheLidSwitchAndRestart() {
        var lid = HostStatus.sampleWithDesk
        lid.power.disableSleep = 1
        #expect(ButtonRules.forHeadline(.sample(.ready(signIns: true), status: lid)) == [
            ActionButton(key: "share", title: "Share screen", action: .run(["screen", "mbp"])),
            ActionButton(key: "lid", title: "Turn off lid-closed mode…", action: .tab(["power", "mbp", "lid", "off"])),
            ActionButton(key: "restart", title: "Restart…", action: .tab(["restart", "mbp"])),
        ])
        var desktop = HostStatus.sampleWithDesk
        desktop.battery = .init(present: false, onAC: nil, percent: nil)
        #expect(titles(ButtonRules.forHeadline(.sample(.ready(signIns: false), status: desktop))) == ["Share screen", "Restart…"])
        #expect(ButtonRules.forHeadline(.sample(.locked, status: .sampleWithDesk)).isEmpty)
        #expect(ButtonRules.newDesk("mbp") == ActionButton(key: "newDesk", title: "New desk…", action: .tab(["desk", "new", "mbp"])))
        // forReady is exactly what the menu builds, in its order: New desk…, then the headline's buttons.
        let r = CheckResult.sample(.ready(signIns: true), status: lid)
        #expect(ButtonRules.forReady(r) == [ButtonRules.newDesk("mbp")] + ButtonRules.forHeadline(r))
    }

    @Test func everyWorkhorseHasTheChecklistAndTheMenuEndsWithTwoButtons() {
        #expect(ButtonRules.checklist("mbp") == ActionButton(key: "checklist", title: "Run the checklist…",
                                                            action: .tab(["prepare", "mbp", "--pause"])))
        #expect(ButtonRules.addAMac == ActionButton(key: "add", title: "Add a Mac…", action: .tab(["pair"])))
        #expect(ButtonRules.checkNow == ActionButton(key: "check", title: "Check now", action: .refresh))
    }

    // MARK: Which desks, and the block of one workhorse (main window, step 2)

    /// The open desks in the report's order, then each closed permanent desk. A definition with no
    /// session that is not permanent is a leftover and gets nothing; a session with no definition
    /// (made by hand) is there, with no definition.
    @Test func theDesksAreTheOpenOnesThenTheClosedPermanentOnes() {
        var s = HostStatus.sampleWithDesk
        s.desks.append(.init(name: DeskName("byhand")!, windows: [.init(index: 0, name: "zsh")],
                             windowCount: 1, attached: 0))
        s.definitions = [
            .init(name: DeskName("notes")!, reopen: true, keep: false, folder: "/Users/alex/notes", command: "",
                  permanent: true),
            .init(name: DeskName("website")!, reopen: true, keep: true, folder: "/Users/alex/site", command: "npm run dev"),
            .init(name: DeskName("shop")!, reopen: true, keep: false, folder: "/Users/alex/shop", command: ""),
        ]
        let desks = ButtonRules.desks(.sample(.ready(signIns: true), status: s))
        #expect(desks.map(\.name) == ["website", "byhand", "notes"])
        #expect(desks.map(\.isOpen) == [true, true, false])
        #expect(desks[0].definition?.folder == "/Users/alex/site")
        #expect(desks[0].isKept && !desks[0].isPermanent)
        #expect(desks[1].definition == nil && desks[1].session?.windowCount == 1)
        #expect(desks[2].session == nil && desks[2].isPermanent)
        #expect(desks[0].buttons == ButtonRules.forDesk(workhorse: "mbp", desk: "website", isOpen: true))
        #expect(desks[2].buttons == ButtonRules.forDesk(workhorse: "mbp", desk: "notes", isOpen: false))
        #expect(ButtonRules.desks(.sample(.ready(signIns: true), status: nil)).isEmpty)
    }

    /// A Ready workhorse's buttons, desks aside, in the order both faces show them: the state's, New
    /// desk…, the rarer ones, the checklist.
    @Test func aReadyBlockHasItsButtonsInTheMenusOrder() {
        let r = CheckResult.sample(.ready(signIns: false), status: .sampleWithDesk, homeReachable: false)
        let block = WorkhorseBlock.of(r, waitingForDeskServer: [], now: formatNow, timeZone: formatZone)
        #expect(block.kind == .ready)
        #expect(block.headline == StatusFormat.headline(r))
        #expect(block.hint == StatusFormat.hint(r))
        #expect(titles(block.buttons) == ["Fix…", "New desk…", "Share screen", "Turn on lid-closed mode…",
                                         "Restart…", "Run the checklist…"])
        #expect(block.buttons == ButtonRules.forState(r) + ButtonRules.forReady(r) + [ButtonRules.checklist("mbp")])
        #expect(block.desks.map(\.name) == ["website"])
        #expect(block.summary == StatusFormat.summaryLine(.sampleWithDesk))
        #expect(block.summaryFacts == StatusFormat.summaryFacts(.sampleWithDesk))
        #expect(block.homeReachable == false)
        #expect(WorkhorseBlock.homeLine(false) == "Home address reachable from here: no")
    }

    @Test func aBlockThatIsNotReadyHasItsStatesButtonAndTheChecklistOnly() {
        let able = Workhorse.sample(osVersion: "27.3", arch: "arm64")
        let r = CheckResult.sample(.locked, workhorse: able, status: .sampleWithDesk, homeReachable: true)
        let block = WorkhorseBlock.of(r, waitingForDeskServer: [], now: formatNow, timeZone: formatZone)
        #expect(block.kind == .other)
        #expect(titles(block.buttons) == ["Unlock disk…  (you type the Mac's password)", "Run the checklist…"])
        #expect(block.desks.isEmpty && block.newDesk == nil && block.rareButtons.isEmpty)
        #expect(block.summary == nil && block.homeReachable == nil)
    }

    /// Waiting for the desk server: its own headline and hint, and only the checklist; only when the
    /// state is "Desk server is off" and the id is in the set.
    @Test func theDeskServerWaitHasItsOwnHeadlineAndOnlyTheChecklist() {
        let down = CheckResult.sample(.notSetUp(.deskServerDown), status: .sampleReady)
        let block = WorkhorseBlock.of(down, waitingForDeskServer: ["mbp"], now: formatNow, timeZone: formatZone)
        #expect(block.kind == .waitingForDeskServer)
        #expect(block.headline == "MacBook Pro · Waiting for the desk server")
        #expect(block.hint == MenuModel.waitingForDeskServerHint)
        #expect(titles(block.buttons) == ["Run the checklist…"])
        #expect(WorkhorseBlock.isWaitingForDeskServer(down, ["mbp"]))
        #expect(!WorkhorseBlock.isWaitingForDeskServer(down, []))
        #expect(!WorkhorseBlock.isWaitingForDeskServer(.sampleReady(), ["mbp"]))
        let notWaiting = WorkhorseBlock.of(down, waitingForDeskServer: [], now: formatNow, timeZone: formatZone)
        #expect(titles(notWaiting.buttons) == ["Finish setting up…", "Run the checklist…"])
    }

    @Test func aWorkhorseThatHasNotAnsweredHasTheChecklistOnly() {
        let block = WorkhorseBlock.stillChecking(.sample(id: "attic", name: "Attic"))
        #expect(block.kind == .stillChecking)
        #expect(block.headline == "Attic · Still checking…")
        #expect(block.hint == nil)
        #expect(block.buttons == [ButtonRules.checklist("attic")])
    }

    // MARK: The menu and the window's board show the same buttons (main window design, 7.3)

    /// For every sample state, the buttons the menu and the board share have the same titles and actions
    /// in the same order. The menu's order is the lines under the headline first, then its submenu's.
    /// The board is built with the tabs the menu was built with (issue #134): a desk's Open button runs
    /// exactly the menu's first line for that desk, and each window's button exactly the menu's line for that
    /// window. The four known differences are named in `windowSide`, `isWindowOnly`, `deskRowClick` and
    /// `flagsLine` below, so a new button on either side fails this test until someone decides where it goes.
    @Test func theMenuAndTheBoardShareTheirButtonsForEverySampleState() throws {
        var inputs = everySampleInput() + moreSampleInputs() + windowSampleInputs()
        let fixture = try HostStatus.parse(fixture("status/desks-board.txt"))
        var off = fixture
        off.signIns = .no
        let attic = Workhorse.sample(id: "attic", name: "Attic")
        inputs.append(SampleMenuInput(gathered: [.checked(.sample(.ready(signIns: true), workhorse: attic,
                                                                  status: fixture, homeReachable: true))]))
        inputs.append(SampleMenuInput(gathered: [.checked(.sample(.ready(signIns: false), workhorse: attic,
                                                                  status: off))]))
        var compared = 0, windowOnly = 0, desks = 0, withWindowLines = 0, windowLines = 0
        for (i, input) in inputs.enumerated() {
            let menu = input.menu
            let board = boardFor(input)
            // The lines outside every workhorse, which the window puts in its sidebar and header.
            let outside = menu.entries.filter { !$0.id.hasPrefix("wh:") && !$0.isSeparator }.map(\.title)
            #expect(outside == (input.gathered.isEmpty ? ["No workhorses yet", "Add a Mac…"] : ["Add a Mac…", "Check now"]),
                    "case \(i)")
            // A saved list edited by hand can repeat an id: the board shows it once, from its first block.
            let blocks = menu.entries.filter { $0.id.hasPrefix("wh:") && !$0.id.contains("#") }
            #expect(blocks.count == board.workhorses.count, "case \(i)")
            // The same symbol, unless an id repeats: then the menu counts every block's state, the board the first.
            if menu.entries.filter({ $0.id.hasPrefix("wh:") && !$0.isSeparator }).count == blocks.count {
                #expect(board.symbol == menu.symbol, "case \(i)")
            }
            for (block, w) in zip(blocks, board.workhorses) {
                #expect(block.id == "wh:\(w.id)", "case \(i)")
                #expect(block.title == w.headline, "case \(i)")
                // The text lines the two faces share: the hint, and the headline submenu's summary and home line.
                #expect(block.children.first { $0.id == "\(block.id):hint" }?.title == w.hint, "case \(i)")
                // The menu draws the summary one fact per line (issue #124); the board keeps the joined line.
                let facts = block.submenu.filter { $0.id.hasPrefix("\(block.id):summary:") }.map(\.title)
                #expect((facts.isEmpty ? nil : facts.joined(separator: " · ")) == w.summary, "case \(i)")
                #expect(block.submenu.first { $0.id == "\(block.id):home" }?.title
                        == w.homeReachable.map(WorkhorseBlock.homeLine), "case \(i)")
                let menuSide = actionLines(block.children.filter { !$0.id.hasPrefix("desk:") } + block.submenu)
                let boardSide = w.buttons.filter { !isWindowOnly($0.action) }
                windowOnly += w.buttons.count - boardSide.count
                #expect(menuSide.map(\.title) == boardSide.map(\.title), "case \(i), \(w.id)")
                #expect(menuSide.map { windowSide($0.action) } == boardSide.map(\.action), "case \(i), \(w.id)")
                compared += boardSide.count

                let rows = block.children.filter { $0.id.hasPrefix("desk:") }
                #expect(rows.count == w.desks.count, "case \(i), \(w.id)")
                // Which desks the menu drew with a line per window: the shared rule, given the menu's tabs.
                let result = input.gathered.lazy.compactMap { entry -> CheckResult? in
                    if case .checked(let r) = entry, r.workhorse.id == w.id { return r }
                    return nil
                }.first
                let gated = Set((result.map { ButtonRules.desks($0, tabs: input.tabs, now: input.now) } ?? [])
                    .filter { $0.windows != nil }.map(\.name))
                for row in rows {
                    let name = try #require(deskName(row, workhorse: w.id))
                    let desk = try #require(w.desks.first { $0.name == name }, "case \(i), \(name)")
                    var lines = actionLines(row.submenu)
                    let open = lines.removeFirst()
                    #expect(open.action == row.action)
                    // The desk's Open button is the menu's first line for that desk, its words and its action.
                    #expect(deskRowClick(open) == desk.open, "case \(i), \(name)")
                    // Each window's button is the menu's line for that window; no window has one the menu lacks.
                    let perWindow = lines.filter(isWindowLine)
                    let onBoard = desk.windows.compactMap { $0.button }
                    #expect(perWindow.map(deskRowClick) == onBoard, "case \(i), \(name)")
                    for line in perWindow {
                        let id = String(line.id.split(separator: ":").last ?? "")
                        #expect(desk.windows.first { $0.id == id }?.button == deskRowClick(line), "case \(i), \(line.id)")
                    }
                    windowLines += perWindow.count
                    lines.removeAll(where: isWindowLine)
                    #expect(lines.map(\.title) == desk.buttons.map(\.title), "case \(i), \(name)")
                    #expect(lines.map { windowSide($0.action) } == desk.buttons.map(\.action), "case \(i), \(name)")
                    if gated.contains(name) {
                        withWindowLines += 1
                        #expect(flagsLine(row) == flagsOnBoard(desk), "case \(i), \(name)")
                    } else {
                        #expect(open.title == "Open \(name)" && perWindow.isEmpty)
                        #expect(flagsLine(row) == nil)
                    }
                    desks += 1
                }
                // Every ended desk's buttons are the window's own.
                for ended in w.ended { #expect(ended.buttons.allSatisfy { isWindowOnly($0.action) }) }
                windowOnly += w.ended.flatMap(\.buttons).count
            }
        }
        #expect(compared > 50 && desks > 15 && windowOnly > 30 && withWindowLines > 20 && windowLines > 20)
    }

    @Test func theNamedDifferencesAreTheOnlyOnes() {
        // The menu's three terminal-tab forms, and what the window does instead.
        #expect(windowSide(.tab(["desk", "new", "mbp"])) == .window(.newDesk(workhorse: "mbp")))
        #expect(windowSide(.tab(["desk", "rename", "mbp", "website"])) == .window(.rename(workhorse: "mbp", desk: "website")))
        #expect(windowSide(.tab(["desk", "remove", "mbp", "website", "--ask"]))
                == .window(.remove(workhorse: "mbp", desk: "website")))
        // Everything else is the menu's own action, unchanged, and BoardAction agrees with this test's list.
        let others: [MenuAction] = [.tab(["connect", "mbp", "website"]), .run(["desk", "window", "mbp", "website"]),
                                    .tab(["desk", "remove", "mbp", "website"]), .refresh, .tab(["pair"])]
        for a in others { #expect(windowSide(a) == .menu(a)) }
        for a in others + [.tab(["desk", "new", "mbp"]), .tab(["desk", "rename", "mbp", "website"]),
                           .tab(["desk", "remove", "mbp", "website", "--ask"])] {
            #expect(BoardAction(a) == windowSide(a))
        }
        // The menu's line-per-window actions (issue #134) are the window's too, unchanged.
        let window = ["connect", "mbp", "website", "--window", "@1"]
        for a: MenuAction in [.tab(window), .tabs([window, window]), .focus(label: "abcd", orOpen: window),
                              .tab(["connect", "mbp", "website", "--view"]), .tab(["connect", "mbp", "website", "--new-window"])] {
            #expect(windowSide(a) == .menu(a) && BoardAction(a) == .menu(a))
        }
        // The flags line is the menu's only grey line on a desk; the board has the flags as values.
        let row = MenuEntry(id: "desk:mbp:website", title: "website", submenu: [
            MenuEntry(id: "desk:mbp:website:flags", title: "kept running, permanent")])
        #expect(flagsLine(row) == "kept running, permanent")
    }

    @Test func noTwoButtonsInOneGroupShareAKey() {
        var lid = HostStatus.sampleWithDesk
        lid.power.disableSleep = 1
        let ready = ButtonRules.forReady(.sample(.ready(signIns: false), status: lid))
        let mixed = ButtonRules.forState(.sample(.ready(signIns: false), status: lid)) + ready + [ButtonRules.checklist("mbp")]
        #expect(Set(mixed.map(\.key)).count == mixed.count)
        let desk = ButtonRules.forDesk(workhorse: "mbp", desk: "website", isOpen: true)
        #expect(Set(desk.map(\.key)).count == desk.count)
    }
}

// MARK: The four known differences between the menu's buttons and the window's (a desk's first line, its
// window lines and New window are no longer among them: since issue #134 the board has the menu's own)

/// 1. The menu's terminal-tab forms of `desk new`, `desk rename` and `desk remove --ask` are, in the
///    window, its New desk form, its Rename form and its Remove confirmation.
private func windowSide(_ action: MenuAction) -> BoardAction {
    guard case .tab(let a) = action, a.first == "desk" else { return .menu(action) }
    if a.count == 3, a[1] == "new" { return .window(.newDesk(workhorse: a[2])) }
    if a.count == 4, a[1] == "rename" { return .window(.rename(workhorse: a[2], desk: a[3])) }
    if a.count == 5, a[1] == "remove", a[4] == "--ask" { return .window(.remove(workhorse: a[2], desk: a[3])) }
    return .menu(action)
}

/// 2. The window's buttons the menu has not: Open the N not in a tab, Start again, Start again and
///    keep it, and Forget.
private func isWindowOnly(_ action: BoardAction) -> Bool {
    switch action {
    case .window(.openAllWithoutTab), .window(.startAgain), .window(.forget): return true
    default: return false
    }
}

/// 3. A line of the menu as a button of the window: the same words and the same action. The first line of a
///    desk's submenu is the desk's Open button in the window, and a window's line is that window's button in
///    the desk's strip (the window's views shorten the titles to "Go to" or "Open", `WindowWords.openOrGoTo`).
private func deskRowClick(_ line: MenuEntry) -> BoardButton {
    BoardButton(title: line.title, action: .menu(line.action))
}

/// A window's line in a desk's submenu, its id `…:win:<window id>`.
private func isWindowLine(_ line: MenuEntry) -> Bool { line.id.contains(":win:@") }

/// 4. With a line per window (menu design 6.1 (a)), the menu shows the desk's flags as one grey line,
///    `…:flags`, where the board has them as values.
private func flagsLine(_ row: MenuEntry) -> String? {
    row.submenu.first { $0.id.hasSuffix(":flags") && $0.action == .none }?.title
}

private func flagsOnBoard(_ desk: BoardDesk) -> String? {
    let set = [desk.keep == true ? "kept running" : nil, desk.permanent == true ? "permanent" : nil].compactMap { $0 }
    return set.isEmpty ? nil : set.joined(separator: ", ")
}

/// The lines that do something, in order: no separators and no text.
private func actionLines(_ entries: [MenuEntry]) -> [MenuEntry] {
    entries.filter { !$0.isSeparator && $0.action != .none }
}

/// The desk a row is for, from its id `desk:<workhorse id>:<desk>`, numbered or not.
private func deskName(_ row: MenuEntry, workhorse id: String) -> String? {
    let prefix = "desk:\(id):"
    guard row.id.hasPrefix(prefix) else { return nil }
    return String(row.id.dropFirst(prefix.count).split(separator: "#").first ?? "")
}

/// The board from the same checks as a sample menu: each answer is `latest` (the first one, for a
/// repeated id), each workhorse not answered yet is in `checking`, every workhorse has one ended desk, and
/// the tabs and time are the ones the menu was built with.
private func boardFor(_ input: SampleMenuInput) -> Board {
    var latest: [String: CheckResult] = [:]
    var order: [Workhorse] = []
    var checking: Set<String> = []
    for entry in input.gathered {
        switch entry {
        case .checked(let r):
            if latest[r.workhorse.id] == nil { latest[r.workhorse.id] = r }
            order.append(r.workhorse)
        case .stillChecking(let w):
            checking.insert(w.id)
            order.append(w)
        }
    }
    let shop = EndedDesk(name: "shop", folder: "/Users/alex/shop", command: nil, reopen: true, keep: false,
                         endedAt: utcDate(2027, 1, 15, 15, 10))
    return BoardModel.build(latest: latest, lastReady: [:], checking: checking, order: order,
                            waitingForDeskServer: input.waitingForDeskServer,
                            tabs: TabsSeen(tabs: input.tabs, at: input.now),
                            ended: Dictionary(order.map { ($0.id, [shop]) }, uniquingKeysWith: { a, _ in a }),
                            results: [:], now: input.now, timeZone: input.timeZone)
}
