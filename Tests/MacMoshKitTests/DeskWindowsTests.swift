import Foundation
import Testing
@testable import MacMoshKit

// MARK: Building blocks for a desk with window details (script 0.8.0)

let windowsNow = Date(timeIntervalSince1970: 1_800_000_000)

/// A window of a desk with its `windowinfo` details: its index, id, name and how many tabs show it.
func detailedWindow(_ index: Int, _ id: String, _ name: String, tabs: Int) -> HostStatus.Window {
    HostStatus.Window(index: index, name: name, id: id, deskShows: index == 0, tabs: tabs)
}

/// A `view` line for a tab with this label on that window.
func labelledView(_ desk: String, _ windowId: String, _ label: String?) -> HostStatus.View {
    HostStatus.View(name: "\(desk)+\(label ?? "none")", windowId: windowId, tabs: 1, label: label)
}

func detailedDesk(_ name: String, _ windows: [HostStatus.Window], views: [HostStatus.View] = []) -> HostStatus.Desk {
    HostStatus.Desk(name: DeskName(name)!, windows: windows, windowCount: windows.count,
                    attached: 0, views: views)
}

/// A live tab record of workhorse `attic`, opened ten minutes before `windowsNow`.
func atticRecord(_ label: String, asked: String = "", minutesAgo: Double = 10) -> TabRecord {
    sampleTabRecord(label: label, workhorse: "attic", desk: "any", askedWindow: asked,
                    openedAt: windowsNow.addingTimeInterval(-minutesAgo * 60))
}

/// A Ready result from Attic with these desks and definitions.
func atticResult(_ desks: [HostStatus.Desk], definitions: [HostStatus.Definition] = [], version: String = "0.8.0",
                 mode: ConnectionMode = .mosh) -> CheckResult {
    var s = HostStatus.sampleWithDesk
    s.scriptVersion = version
    s.desks = desks
    s.definitions = definitions
    return .sample(.ready(signIns: true), workhorse: .sample(id: "attic", name: "Attic", mode: mode), status: s,
                   homeReachable: true)
}

func permanentDefinition(_ name: String, keep: Bool = false) -> HostStatus.Definition {
    .init(name: DeskName(name)!, reopen: true, keep: keep, folder: "/Users/alex/\(name)", command: "", permanent: true)
}

/// The desk lines of one result, as the menu sees them with these records and tabs opening in `terminal`.
func deskLines(_ r: CheckResult, records: [TabRecord] = [], terminal: TerminalApp = .iterm2) -> [DeskLine] {
    ButtonRules.desks(r, tabs: TabsOnThisMac(records: records, terminal: terminal), now: windowsNow)
}

/// The line per window of the only desk of a result, or nil when the gate keeps today's shape.
func windowsOf(_ desk: HostStatus.Desk, records: [TabRecord] = [], version: String = "0.8.0",
               mode: ConnectionMode = .mosh, terminal: TerminalApp = .iterm2) -> DeskWindows? {
    deskLines(atticResult([desk], version: version, mode: mode), records: records, terminal: terminal).first?.windows
}

private func connect(_ desk: String, _ rest: String...) -> [String] { ["connect", "attic", desk] + rest }

private let a = "aaaaaaaaaaaaaaaa", b = "bbbbbbbbbbbbbbbb", c = "cccccccccccccccc"

/// The line per window of a desk (menu design 6.1 (a), 6.2 and 6.3), and the gate that decides whether a
/// desk has it (8.3). Pure: the records and the time are given.
@Suite struct DeskWindowsTests {
    // MARK: The gate, its three conditions one by one

    @Test(arguments: [("0.8.0", true), ("0.8.1", true), ("0.10.0", true), ("1.0.0", true),
                      ("0.7.9", false), ("0.7.0", false), ("0.1.0", false), ("", false)])
    func theScriptMustBe080OrNewer(version: String, passes: Bool) {
        let desk = detailedDesk("blog", [detailedWindow(0, "@8", "zsh", tabs: 0)])
        #expect((windowsOf(desk, version: version) != nil) == passes)
    }

    /// The connection the tab will really use, by connect's own rule: Tabs mode is Tabs mode only in iTerm2.
    @Test(arguments: [(ConnectionMode.mosh, TerminalApp.iterm2, true), (.ssh, .iterm2, true), (.tabs, .iterm2, false),
                      (.mosh, .appleTerminal, true), (.ssh, .appleTerminal, true), (.tabs, .appleTerminal, true)])
    func theConnectionMustBeMoshOrPlainSSH(mode: ConnectionMode, terminal: TerminalApp, passes: Bool) {
        let desk = detailedDesk("blog", [detailedWindow(0, "@8", "zsh", tabs: 0)])
        #expect((windowsOf(desk, mode: mode, terminal: terminal) != nil) == passes)
        #expect(WindowLinesGate.passes(atticResult([desk], mode: mode), desk: desk, terminal: terminal) == passes)
    }

    @Test func anOpenDeskNeedsWindowDetailsInTheReport() {
        let plain = detailedDesk("blog", [HostStatus.Window(index: 0, name: "zsh")])
        #expect(windowsOf(plain) == nil)
        let detailed = detailedDesk("blog", [detailedWindow(0, "@8", "zsh", tabs: 0)])
        #expect(windowsOf(detailed) != nil)
    }

    /// An open desk whose window details name no usable window id keeps today's shape, though it passes the gate.
    @Test func anOpenDeskWithNoUsableWindowIdKeepsTodaysShape() {
        let desk = detailedDesk("blog", [detailedWindow(0, "@x", "zsh", tabs: 0)])
        #expect(WindowLinesGate.passes(atticResult([desk]), desk: desk, terminal: .iterm2))
        #expect(windowsOf(desk) == nil)
        let menu = MenuModel.build([.checked(atticResult([desk]))], tabs: TabsOnThisMac(), now: windowsNow)
        #expect(entry(menu.entries, "desk:attic:blog")?.title == "blog (1 window: zsh)")
    }

    /// A closed permanent desk has no windows to detail: the script's version and the connection are enough.
    @Test func aClosedPermanentDeskNeedsOnlyTheVersionAndTheConnection() {
        let closed = { (version: String, mode: ConnectionMode) in
            deskLines(atticResult([], definitions: [permanentDefinition("garden")], version: version, mode: mode)).first?.windows
        }
        #expect(closed("0.8.0", .mosh) != nil)
        #expect(closed("0.8.0", .ssh) != nil)
        #expect(closed("0.7.0", .mosh) == nil)
        #expect(closed("0.8.0", .tabs) == nil)
        #expect(WindowLinesGate.passes(atticResult([]), desk: nil, terminal: .iterm2))
    }

    /// With no tabs given (the board before the menu's first build), no desk has a line per window.
    @Test func withNoTabsGivenNoDeskHasALinePerWindow() {
        let r = atticResult([detailedDesk("blog", [detailedWindow(0, "@8", "zsh", tabs: 0)])])
        #expect(ButtonRules.desks(r).first?.windows == nil)
        #expect(ButtonRules.desks(r) == deskLines(r).map { var d = $0; d.windows = nil; return d })
    }

    // MARK: The first line, and the row's own click, for every combination (menu design 6.2)

    @Test func oneWindowWithNoTabOpensIt() {
        let w = windowsOf(detailedDesk("blog", [detailedWindow(0, "@8", "zsh", tabs: 0)]))
        #expect(w?.first == ActionButton(key: "open", title: "Open blog", action: .tab(connect("blog", "--window", "@8"))))
    }

    @Test func everyWindowWithNoTabOpensATabOnEachInOrder() {
        let w = windowsOf(detailedDesk("api", [detailedWindow(0, "@5", "server", tabs: 0),
                                               detailedWindow(1, "@6", "tests", tabs: 0)]))
        #expect(w?.first == ActionButton(key: "open", title: "Open api in 2 tabs",
                                         action: .tabs([connect("api", "--window", "@5"), connect("api", "--window", "@6")])))
    }

    /// Some windows have no tab, the others have one, findable or not: only those with none get a tab.
    @Test func theWindowsNotInATabAreOpenedAndNoOther() {
        let findable = detailedWindow(0, "@1", "claude", tabs: 1)
        let unfindable = detailedWindow(1, "@2", "zsh", tabs: 1)
        let none1 = detailedWindow(2, "@3", "vim", tabs: 0), none2 = detailedWindow(3, "@4", "logs", tabs: 0)
        let views = [labelledView("website", "@1", a)]
        let one = windowsOf(detailedDesk("website", [findable, unfindable, none1], views: views), records: [atticRecord(a)])
        #expect(one?.first == ActionButton(key: "open", title: "Open the 1 window not in a tab",
                                           action: .tabs([connect("website", "--window", "@3")])))
        let two = windowsOf(detailedDesk("website", [findable, none1, none2], views: views), records: [atticRecord(a)])
        #expect(two?.first == ActionButton(key: "open", title: "Open the 2 windows not in a tab",
                                           action: .tabs([connect("website", "--window", "@3"),
                                                          connect("website", "--window", "@4")])))
        let onlyUnfindable = windowsOf(detailedDesk("website", [unfindable, none1]))
        #expect(onlyUnfindable?.first == ActionButton(key: "open", title: "Open the 1 window not in a tab",
                                                      action: .tabs([connect("website", "--window", "@3")])))
    }

    /// Every window has a tab and at least one can be found: go to the newest tab of the lowest-numbered window
    /// with a findable tab, or open that window if the tab has gone meanwhile.
    @Test func everyWindowInATabWithOneFindableGoesToIt() {
        let single = windowsOf(detailedDesk("notes", [detailedWindow(0, "@7", "zsh", tabs: 1)],
                                            views: [labelledView("notes", "@7", a)]), records: [atticRecord(a)])
        #expect(single?.first == ActionButton(key: "open", title: "Go to notes",
                                              action: .focus(label: a, orOpen: connect("notes", "--window", "@7"))))
        // Window 0's tab can't be found; window 1 has two findable tabs, b the newer; window 2 has c.
        let desk = detailedDesk("website", [detailedWindow(0, "@1", "claude", tabs: 1), detailedWindow(1, "@2", "zsh", tabs: 2),
                                            detailedWindow(2, "@3", "vim", tabs: 1)],
                                views: [labelledView("website", "@2", a), labelledView("website", "@2", b),
                                        labelledView("website", "@3", c)])
        let w = windowsOf(desk, records: [atticRecord(a, minutesAgo: 30), atticRecord(b, minutesAgo: 5), atticRecord(c)])
        #expect(w?.first == ActionButton(key: "open", title: "Go to website",
                                         action: .focus(label: b, orOpen: connect("website", "--window", "@2"))))
    }

    /// Every window has a tab, and none of them can be found here: one new tab, on a window of its own.
    @Test func everyWindowInATabNoneFindableOpensANewTab() {
        for windows in [[detailedWindow(0, "@9", "web", tabs: 1)],
                        [detailedWindow(0, "@9", "web", tabs: 1), detailedWindow(1, "@10", "db", tabs: 2)]] {
            let w = windowsOf(detailedDesk("shop", windows))
            #expect(w?.first == ActionButton(key: "open", title: "Open shop in a new tab",
                                             action: .tab(connect("shop", "--view"))))
        }
    }

    @Test func aClosedPermanentDeskOpensWithAViewOfItsOwn() {
        let lines = deskLines(atticResult([], definitions: [permanentDefinition("garden")]))
        #expect(lines.first?.windows?.first == ActionButton(key: "open", title: "Open garden",
                                                             action: .tab(connect("garden", "--view"))))
        #expect(lines.first?.windows?.title == "garden (closed)")
        #expect(lines.first?.windows?.windows == [] && lines.first?.windows?.newWindow == nil)
    }

    // MARK: The row's title (menu design 6.3)

    @Test func theRowSaysHowManyWindowsAndHowManyAreInTabs() {
        let none = detailedWindow(0, "@1", "a", tabs: 0)
        let unfindable = detailedWindow(1, "@2", "b", tabs: 1)
        let unfindable2 = detailedWindow(2, "@3", "c", tabs: 3)
        let found = detailedWindow(3, "@4", "d", tabs: 1)
        let views = [labelledView("x", "@4", a)]
        let rows: [([HostStatus.Window], String)] = [
            ([none], "x · 1 window"),
            ([unfindable], "x · 1 window, in a tab"),
            ([found], "x · 1 window, in a tab"),
            ([none, unfindable], "x · 2 windows, 1 in a tab"),
            ([none, unfindable, found], "x · 3 windows, 2 in tabs"),
            ([unfindable, found], "x · 2 windows, all in tabs"),
            ([unfindable, unfindable2, found], "x · 3 windows, all in tabs"),
            ([none, detailedWindow(4, "@5", "e", tabs: 0)], "x · 2 windows"),
        ]
        for (windows, title) in rows {
            #expect(windowsOf(detailedDesk("x", windows, views: views), records: [atticRecord(a)])?.title == title)
        }
    }

    // MARK: The window lines

    @Test func aDeskWithOneWindowHasNoWindowLines() {
        let w = windowsOf(detailedDesk("notes", [detailedWindow(0, "@7", "zsh", tabs: 1)],
                                       views: [labelledView("notes", "@7", a)]), records: [atticRecord(a)])
        #expect(w?.windows == [])
    }

    @Test func everyKindOfWindowLine() {
        let desk = detailedDesk("website", [
            detailedWindow(0, "@1", "claude", tabs: 1),   // one findable tab
            detailedWindow(1, "@2", "zsh", tabs: 2),      // two findable tabs, b newer than a
            detailedWindow(2, "@3", "logs", tabs: 2),     // one findable tab and one other
            detailedWindow(3, "@4", "web", tabs: 1),      // only a tab this Mac can't find
            detailedWindow(4, "@5", "vim", tabs: 0),      // no tab
        ], views: [labelledView("website", "@1", c), labelledView("website", "@2", a), labelledView("website", "@2", b),
                   labelledView("website", "@3", "dddddddddddddddd")])
        let w = windowsOf(desk, records: [atticRecord(c), atticRecord(a, minutesAgo: 30), atticRecord(b, minutesAgo: 1),
                                          atticRecord("dddddddddddddddd")])
        #expect(w?.windows == [
            ActionButton(key: "win:@1", title: "claude (in a tab)", action: .focus(label: c, orOpen: connect("website", "--window", "@1"))),
            ActionButton(key: "win:@2", title: "zsh (in 2 tabs)", action: .focus(label: b, orOpen: connect("website", "--window", "@2"))),
            ActionButton(key: "win:@3", title: "logs (in 2 tabs)",
                         action: .focus(label: "dddddddddddddddd", orOpen: connect("website", "--window", "@3"))),
            ActionButton(key: "win:@4", title: "web (open in another tab)", action: .tab(connect("website", "--window", "@4"))),
            ActionButton(key: "win:@5", title: "vim", action: .tab(connect("website", "--window", "@5"))),
        ])
    }

    /// A name used by two windows: the first reads as it is, each later one adds its number.
    @Test func aRepeatedWindowNameGetsTheWindowsNumber() {
        let w = windowsOf(detailedDesk("x", [detailedWindow(0, "@1", "zsh", tabs: 0), detailedWindow(1, "@2", "vim", tabs: 0),
                                             detailedWindow(3, "@4", "zsh", tabs: 1), detailedWindow(4, "@5", "zsh", tabs: 0)]))
        #expect(w?.windows.map(\.title) == ["zsh", "vim", "zsh (window 3) (open in another tab)", "zsh (window 4)"])
    }

    /// A window with no name still has words on its line.
    @Test func aWindowWithNoNameIsCalledByItsNumber() {
        let w = windowsOf(detailedDesk("x", [detailedWindow(0, "@1", "", tabs: 0), detailedWindow(1, "@2", "zsh", tabs: 0)]))
        #expect(w?.windows.map(\.title) == ["window 0", "zsh"])
    }

    // MARK: New window, and the flags line

    @Test func newWindowOpensATabOfItsOwn() {
        let w = windowsOf(detailedDesk("blog", [detailedWindow(0, "@8", "zsh", tabs: 1)]))
        #expect(w?.newWindow == ActionButton(key: "window", title: "New window", action: .tab(connect("blog", "--new-window"))))
    }

    @Test func theFlagsLineHasOnlyTheFlagsThatAreSet() {
        let desk = detailedDesk("website", [detailedWindow(0, "@1", "zsh", tabs: 0)])
        let cases: [([HostStatus.Definition], String?)] = [
            ([], nil),
            ([.init(name: DeskName("website")!, reopen: true, keep: false, folder: "/x", command: "")], nil),
            ([.init(name: DeskName("website")!, reopen: true, keep: true, folder: "/x", command: "")], "kept running"),
            ([permanentDefinition("website")], "permanent"),
            ([permanentDefinition("website", keep: true)], "kept running, permanent"),
        ]
        for (definitions, flags) in cases {
            #expect(deskLines(atticResult([desk], definitions: definitions)).first?.windows?.flags == flags)
        }
    }

    // MARK: What the window's board reads besides the lines (issue #134)

    /// How many tabs show the desk's windows, findable or not, a fresh record not in the report yet included;
    /// and a tab on each window no tab shows, in the desk's order, which "Open the N not in a tab" opens.
    @Test func theTabsThatShowItsWindowsAndTheWindowsNotInATab() {
        let desk = detailedDesk("website", [
            detailedWindow(0, "@1", "claude", tabs: 1),   // one findable tab
            detailedWindow(1, "@2", "zsh", tabs: 2),      // one findable tab and one other
            detailedWindow(2, "@3", "logs", tabs: 1),     // only a tab this Mac can't find
            detailedWindow(3, "@4", "vim", tabs: 0),      // no tab
            detailedWindow(4, "@5", "web", tabs: 0),      // none in the report, but a tab opened on it a minute ago
            detailedWindow(5, "@6", "db", tabs: 0),       // no tab
        ], views: [labelledView("website", "@1", a), labelledView("website", "@2", b)])
        let w = windowsOf(desk, records: [atticRecord(a), atticRecord(b), atticRecord(c, asked: "@5", minutesAgo: 1)])
        #expect(w?.tabs == 5)
        #expect(w?.notInATab == [connect("website", "--window", "@4"), connect("website", "--window", "@6")])

        let allInTabs = windowsOf(detailedDesk("notes", [detailedWindow(0, "@7", "zsh", tabs: 1)]))
        #expect(allInTabs?.tabs == 1 && allInTabs?.notInATab == [])
        let none = windowsOf(detailedDesk("api", [detailedWindow(0, "@5", "server", tabs: 0),
                                                  detailedWindow(1, "@6", "tests", tabs: 0)]))
        #expect(none?.tabs == 0)
        #expect(none?.notInATab == [connect("api", "--window", "@5"), connect("api", "--window", "@6")])
        let closed = deskLines(atticResult([], definitions: [permanentDefinition("garden")])).first?.windows
        #expect(closed?.tabs == 0 && closed?.notInATab == [])
    }

    // MARK: Rules over every combination

    /// Every window kind in every mix of up to three windows, with every first line and window line checked:
    /// no action opens a second tab on a window that has a tab this Mac can find (only `.focus`'s fallback,
    /// which runs when that tab has gone, names such a window).
    @Test func noActionOpensASecondTabOnAWindowWithAFindableTab() {
        let kinds = ["found", "other", "none"]
        var mixes: [[String]] = kinds.map { [$0] }
        for _ in 0..<2 { mixes += mixes.filter { $0.count == mixes.map(\.count).max() }.flatMap { m in kinds.map { m + [$0] } } }
        var checked = 0
        for mix in mixes {
            var windows: [HostStatus.Window] = [], views: [HostStatus.View] = [], records: [TabRecord] = []
            for (i, kind) in mix.enumerated() {
                let id = "@\(i + 1)"
                windows.append(detailedWindow(i, id, "w\(i)", tabs: kind == "none" ? 0 : 1))
                if kind == "found" {
                    let label = String(repeating: "\(i)", count: 16)
                    views.append(labelledView("x", id, label))
                    records.append(atticRecord(label))
                }
            }
            let findable = Set(mix.enumerated().filter { $0.element == "found" }.map { "@\($0.offset + 1)" })
            guard let w = windowsOf(detailedDesk("x", windows, views: views), records: records) else {
                Issue.record("\(mix) should pass the gate"); continue
            }
            for action in [w.first.action] + w.windows.map(\.action) {
                let opened: [[String]]
                switch action {
                case .tab(let args): opened = [args]
                case .tabs(let list): opened = list
                case .focus(_, _): opened = []
                default: opened = []; Issue.record("\(mix): \(action)")
                }
                for args in opened {
                    if let at = args.firstIndex(of: "--window") { #expect(!findable.contains(args[at + 1]), "\(mix): \(args)") }
                }
                checked += 1
            }
            #expect(w.windows.count == (mix.count > 1 ? mix.count : 0))
        }
        #expect(mixes.count == 39 && checked > 100)
    }
}

/// The whole menu with a line per window (menu design 6.1 (a)): the design's own example, the gate keeping
/// today's shape, and the rules that hold over the whole tree.
@Suite struct MenuWindowsTests {
    private func submenu(_ menu: MenuLines, _ id: String) -> [MenuEntry] { entry(menu.entries, id)?.submenu ?? [] }

    /// From script 0.8.0, as the design draws it: 0.11.0 adds only "Name a window…" (MenuStoredCopyTests).
    @Test func theDesignsExampleReadsAsTheDesignDrawsIt() {
        let menu = windowSampleInputs(version: "0.8.0")[0].menu
        let block = menu.entries[0]
        #expect(([block] + block.children).map(\.title) == [
            "Attic · Ready",
            "website · 3 windows, 2 in tabs", "api · 2 windows", "notes · 1 window, in a tab", "blog · 1 window",
            "shop · 2 windows, 1 in a tab", "garden (closed)", "New desk…",
        ])
        #expect(submenu(menu, "desk:attic:website").map(\.title) == [
            "Open the 1 window not in a tab", "", "claude (in a tab)", "zsh (in a tab)", "vim", "", "New window", "",
            "Rename website…", "Remove website…", "kept running, permanent",
        ])
        #expect(submenu(menu, "desk:attic:website").map(\.id) == [
            "open", "sep1", "win:@1", "win:@2", "win:@3", "sep2", "window", "sep3", "rename", "remove", "flags",
        ].map { "desk:attic:website:\($0)" })
        #expect(submenu(menu, "desk:attic:api").map(\.title) == [
            "Open api in 2 tabs", "", "server", "tests", "", "New window", "", "Rename api…", "Remove api…",
        ])
        #expect(submenu(menu, "desk:attic:notes").map(\.title) == ["Go to notes", "", "New window", "", "Rename notes…", "Remove notes…"])
        #expect(submenu(menu, "desk:attic:blog").map(\.title) == ["Open blog", "", "New window", "", "Rename blog…", "Remove blog…"])
        #expect(submenu(menu, "desk:attic:shop").map(\.title) == [
            "Open the 1 window not in a tab", "", "web (open in another tab)", "db", "", "New window", "",
            "Rename shop…", "Remove shop…",
        ])
        #expect(submenu(menu, "desk:attic:garden").map(\.title) == ["Open garden", "", "Rename garden…", "Remove garden…", "permanent"])
        // The flags are grey text; New window opens a tab of its own.
        #expect(entry(menu.entries, "desk:attic:website:flags")?.action == MenuAction.none)
        #expect(entry(menu.entries, "desk:attic:blog:window")?.action == .tab(["connect", "attic", "blog", "--new-window"]))
    }

    /// A desk's row does what its submenu's first line does, whatever that line is.
    @Test func everyDeskRowDoesWhatItsFirstLineDoes() {
        var seen = 0
        for input in windowSampleInputs() {
            for e in allEntries(input.menu.entries) where e.opensSubmenu && e.id.hasPrefix("desk:") {
                #expect(e.action != .none && e.submenu.first?.action == e.action, "\(e.id)")
                seen += 1
            }
        }
        #expect(seen > 30)
    }

    /// With Tabs mode in iTerm2, or a script older than 0.8.0, the menu is exactly what it is without the
    /// gate: the menu of the same report from a script that never had window lines.
    @Test func whenTheGateFailsTheMenuIsTodays() {
        let inputs = windowSampleInputs(version: "0.8.0")
        let today = SampleMenuInput(gathered: [.checked(.sample(.ready(signIns: true), workhorse: .sample(id: "attic", name: "Attic"),
                                                                status: windowsReport(version: "0.1.0"), homeReachable: true))],
                                    now: windowsNow).menu
        #expect(inputs[1].menu == today)
        #expect(inputs[2].menu == today)
        #expect(entry(today.entries, "desk:attic:website")?.title == "website (3 windows: claude, zsh, vim, kept running, permanent)")
        #expect(entry(today.entries, "desk:attic:website:window")?.action == .run(["desk", "window", "attic", "website"]))
        #expect(entry(today.entries, "desk:attic:garden")?.action == .tab(["connect", "attic", "garden"]))
        // Tabs mode outside iTerm2 is mosh, so the gate passes.
        #expect(inputs[3].menu.entries[0].children.map(\.title) == inputs[0].menu.entries[0].children.map(\.title))
    }

    /// A tab opened a minute ago that the report doesn't list yet already counts for the window it asked for.
    @Test func aTabOpenedAMomentAgoCountsBeforeTheReportHasIt() {
        let menu = windowSampleInputs()[4].menu
        #expect(entry(menu.entries, "desk:attic:api")?.title == "api · 2 windows, 1 in a tab")
        #expect(entry(menu.entries, "desk:attic:api:win:@5")?.action
                == .focus(label: "9f3a1c2e5b7d4a60", orOpen: ["connect", "attic", "api", "--window", "@5"]))
        #expect(entry(menu.entries, "desk:attic:api:open")?.title == "Open the 1 window not in a tab")
    }

    /// Two workhorses, one past the gate and one not, each have their own shape.
    @Test func eachWorkhorseHasItsOwnGate() {
        let menu = windowSampleInputs()[5].menu
        #expect(entry(menu.entries, "desk:attic:website")?.title == "website · 3 windows, 2 in tabs")
        #expect(entry(menu.entries, "desk:spare:website")?.title == "website (2 windows: zsh, vim, open in 1 tab)")
    }

    /// Input no report or record file could carry still gives plain words in every action and unique ids: a
    /// window id that isn't `@` and digits, a repeated window id, a label with a space, and the desk twice.
    @Test func oddInputStillGivesPlainWordsAndUniqueIDs() {
        let odd = detailedDesk("website", [detailedWindow(0, "@1; rm", "zsh", tabs: 0), detailedWindow(1, "@2", "vim", tabs: 1),
                                           detailedWindow(2, "@2", "vim", tabs: 0), detailedWindow(3, "", "x", tabs: 0)],
                               views: [labelledView("website", "@2", "not a label"), labelledView("website", "@2", a)])
        let records = [atticRecord("not a label"), atticRecord(a), atticRecord("bad label", asked: "@2", minutesAgo: 0)]
        let menu = SampleMenuInput(gathered: [.checked(atticResult([odd, odd], definitions: [permanentDefinition("website")]))],
                                   tabs: TabsOnThisMac(records: records), now: windowsNow).menu
        var words = 0
        for action in allActions(menu.entries) {
            for word in action.words {
                #expect(PlainWords.isPlain(word), "\(word)")
                words += 1
            }
        }
        #expect(words > 20)
        let ids = allIDs(menu.entries)
        #expect(Set(ids).count == ids.count)
        #expect(entry(menu.entries, "desk:attic:website")?.submenu.contains { $0.id.contains("rm") } == false)
    }
}
