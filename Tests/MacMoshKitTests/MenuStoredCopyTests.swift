import Foundation
import Testing
@testable import MacMoshKit

/// What the menu shows, kept in `Fixtures/menu/every-sample-menu.txt`. Every case of
/// `everySampleMenu()`, then every case of `moreSampleMenus()`, must give exactly those lines: the same
/// symbol, and for each line the same title, indent, action, separator, and place in or out of a submenu.
/// `Fixtures/menu/step-1-menu.txt` keeps the menu as it was before any line opened a submenu (issue
/// #108); issue #107 changed only the Ready blocks, and every action is still there.
@Suite struct MenuStoredCopyTests {
    @Test func everySampleMenuIsTheStoredCopy() throws {
        let stored = try storedMenus()
        let now = everySampleMenu() + moreSampleMenus()
        #expect(everySampleMenu().count == 11)
        #expect(stored.count == 11 + moreSampleMenus().count)
        #expect(now.count == stored.count)
        for (i, (want, got)) in zip(stored, now).enumerated() {
            #expect(got.symbol == want.symbol, "menu \(i)")
            #expect(got.items.count == want.items.count, "menu \(i)")
            for (j, (w, g)) in zip(want.items, got.items).enumerated() {
                #expect(g == w, "menu \(i), line \(j)")
            }
        }
    }

    /// The menus with a line per window (issue #124), kept in `Fixtures/menu/windows-menu.txt`.
    @Test func everyWindowSampleMenuIsTheStoredCopy() throws {
        let stored = try storedMenus("menu/windows-menu.txt")
        let now = windowSampleInputs().map(\.menu)
        #expect(stored.count == now.count)
        for (i, (want, got)) in zip(stored, now).enumerated() {
            #expect(got.symbol == want.symbol, "menu \(i)")
            #expect(got.items.count == want.items.count, "menu \(i)")
            for (j, (w, g)) in zip(want.items, got.items).enumerated() {
                #expect(g == w, "menu \(i), line \(j)")
            }
        }
    }

    /// The format reads back what it writes, for every kind of action.
    @Test func theStoredFormatReadsBackEveryAction() throws {
        let menus = everySampleMenu() + moreSampleMenus() + windowSampleInputs().map(\.menu)
        let text = storedText(menus)
        let back = try storedMenus(text: text)
        #expect(back.map(\.items) == menus.map(\.items))
        #expect(back.map(\.symbol) == menus.map(\.symbol))
        #expect(try storedAction("tabs connect a b --window @1 | connect a b --window @2")
                == .tabs([["connect", "a", "b", "--window", "@1"], ["connect", "a", "b", "--window", "@2"]]))
        #expect(try storedAction("focus 0123abcd connect a b --window @1")
                == .focus(label: "0123abcd", orOpen: ["connect", "a", "b", "--window", "@1"]))
    }

    @Test func theStoredCopyCoversEveryKindOfLine() throws {
        let items = try (storedMenus() + storedMenus("menu/windows-menu.txt")).flatMap(\.items)
        #expect(items.contains { $0.isSeparator })
        #expect(items.contains { $0.action == .refresh })
        #expect(items.contains { if case .tab = $0.action { return true }; return false })
        #expect(items.contains { if case .run = $0.action { return true }; return false })
        #expect(items.contains { if case .tabs = $0.action { return true }; return false })
        #expect(items.contains { if case .focus = $0.action { return true }; return false })
        #expect(Set(items.map(\.indent)) == [0, 1, 2])
        #expect(items.contains { $0.opensSubmenu && $0.action == .none })
        #expect(items.contains { $0.opensSubmenu && $0.action != .none })
        #expect(items.contains { $0.inSubmenu && $0.isSeparator })
        #expect(items.contains { $0.inSubmenu && !$0.isSeparator })
    }

    /// Main's copy before issue #124 (`Fixtures/menu/s1-menu.txt`, kept as it was) is every sample's menu now,
    /// line for line, but for one change made on purpose: the summary line in a Ready workhorse's submenu is
    /// drawn one fact per line, the same words split where the line joined them with " · ". None of these
    /// samples passes the gate for a line per window (an older script, or no window details), so nothing else
    /// may differ.
    @Test func everyGatedOffMenuIsMainsCopyWithTheSummaryOneFactPerLine() throws {
        let main = try storedMenus("menu/s1-menu.txt")
        let now = everySampleMenu() + moreSampleMenus()
        #expect(main.count == now.count)
        var split = 0
        for (i, (was, menu)) in zip(main, now).enumerated() {
            #expect(menu.symbol == was.symbol, "menu \(i)")
            var want: [MenuItem] = []
            for item in was.items {
                let isSummary = item.inSubmenu && !item.isSeparator && item.action == .none
                    && (item.title.hasPrefix("Sign-ins working · ") || item.title.hasPrefix("Sign-ins off · "))
                guard isSummary else { want.append(item); continue }
                split += 1
                for fact in item.title.components(separatedBy: " · ") {
                    var line = item
                    line.title = fact
                    want.append(line)
                }
            }
            #expect(menu.items == want, "menu \(i)")
        }
        #expect(split == 8)
    }

    /// Every block that is not Ready (every other state, "Still checking…", "Waiting for the desk
    /// server", "No workhorses yet") is exactly step 1's, line for line. A Ready block keeps its headline.
    @Test func onlyTheReadyBlocksChangedSinceStep1() throws {
        let before = try storedMenus("menu/step-1-menu.txt")
        let now = everySampleMenu() + moreSampleMenus()
        #expect(before.count == now.count)
        var ready = 0, other = 0
        for (i, (was, menu)) in zip(before, now).enumerated() {
            #expect(menu.symbol == was.symbol, "menu \(i)")
            let wasBlocks = blocks(was.items), nowBlocks = blocks(menu.items)
            #expect(wasBlocks.count == nowBlocks.count, "menu \(i)")
            for (j, (w, n)) in zip(wasBlocks, nowBlocks).enumerated() {
                if isReady(w) {
                    ready += 1
                    #expect(n.first?.title == w.first?.title, "menu \(i), block \(j)")
                    #expect(n.first?.opensSubmenu == true, "menu \(i), block \(j)")
                } else {
                    other += 1
                    #expect(n == w, "menu \(i), block \(j)")
                }
            }
        }
        #expect(ready == 8)   // cases 0, 1, 13 and 14, and two each in 10 and 17
        #expect(other > 20)
    }

    /// Nothing the menu could do is lost: each case offers the same actions, with the same arguments, as
    /// in step 1. The desk's row and its `Open` line share one action, so the set is the same.
    @Test func everyCaseOffersTheSameActionsAsInStep1() throws {
        let before = try storedMenus("menu/step-1-menu.txt")
        let now = everySampleMenu() + moreSampleMenus()
        for (i, (was, menu)) in zip(before, now).enumerated() {
            let wasActions = was.items.map(\.action).filter { $0 != .none }
            let nowActions = allActions(menu.entries)
            for a in wasActions { #expect(nowActions.contains(a), "menu \(i): \(a) is gone") }
            for a in nowActions { #expect(wasActions.contains(a), "menu \(i): \(a) is new") }
        }
    }
}

/// The lines split at each top-level separator: one block per workhorse, then the last lines.
private func blocks(_ items: [MenuItem]) -> [[MenuItem]] {
    var out: [[MenuItem]] = [[]]
    for item in items {
        if item.isSeparator && item.indent == 0 { out.append([]) } else { out[out.count - 1].append(item) }
    }
    return out
}

private func isReady(_ block: [MenuItem]) -> Bool {
    guard let head = block.first, head.indent == 0 else { return false }
    return head.title.hasSuffix(" · Ready") || head.title.hasSuffix(" · Ready, sign-ins off")
}

/// Every action in a tree other than `.none`: rows, primary actions, submenu lines and the lines under them.
func allActions(_ entries: [MenuEntry]) -> [MenuAction] {
    entries.flatMap { e in
        (e.action == .none ? [] : [e.action]) + allActions(e.submenu) + allActions(e.children)
    }
}

/// Menus `everySampleMenu()` doesn't reach: the wait for the desk server, open, kept, permanent,
/// closed and leftover desks, a laptop with lid-closed mode on, no home-address light, a time in a
/// hint, an older Mac that can't be unlocked over ssh, and two workhorses with a desk of the same name.
func moreSampleMenus() -> [MenuLines] { moreSampleInputs().map(\.menu) }

/// What `moreSampleMenus()` is built from, in its order.
func moreSampleInputs() -> [SampleMenuInput] {
    var desks = HostStatus.sampleWithDesk
    desks.power.disableSleep = 1
    desks.desks.append(.init(name: DeskName("notes")!, windows: [.init(index: 0, name: "zsh")],
                             windowCount: 1, attached: 0))
    desks.definitions = [
        .init(name: DeskName("website")!, reopen: true, keep: true, folder: "/Users/alex/site",
              command: "npm run dev", permanent: true),
        .init(name: DeskName("api")!, reopen: false, keep: false, folder: "/Users/alex/api", command: "",
              permanent: true),
        .init(name: DeskName("scratch")!, reopen: false, keep: false, folder: "/Users/alex/x", command: ""),
    ]
    var desktop = HostStatus.sampleWithDesk
    desktop.battery = .init(present: false, onAC: nil, percent: nil)
    let serverDown = CheckResult.sample(.notSetUp(.deskServerDown), status: .sampleReady)
    let seen = CheckResult.sample(.cantReach(.nothingAnswers), workhorse: .sample(lastSeen: utcDate(2027, 1, 15, 14, 2)))
    let old = Workhorse.sample(osVersion: "15.6", arch: "arm64")
    return [
        SampleMenuInput(gathered: [.checked(serverDown)], waitingForDeskServer: ["mbp"]),
        SampleMenuInput(gathered: [.checked(serverDown)]),
        SampleMenuInput(gathered: [.checked(.sample(.ready(signIns: true), status: desks, homeReachable: true))]),
        SampleMenuInput(gathered: [.checked(.sample(.ready(signIns: true), status: desktop))]),
        SampleMenuInput(gathered: [.checked(seen)], now: formatNow, timeZone: formatZone),
        SampleMenuInput(gathered: [.checked(.sample(.locked, workhorse: old))]),
        SampleMenuInput(gathered: [
            .checked(.sampleReady(id: "workhorse", name: "Workhorse")),
            .checked(.sampleReady(id: "daily-mac", name: "Daily Mac")),
            .stillChecking(.sample(id: "attic", name: "Attic")),
            .checked(.sample(.notSetUp(.deskServerDown), workhorse: .sample(id: "spare", name: "Spare"),
                             status: .sampleReady)),
        ], waitingForDeskServer: ["spare"]),
    ]
}

/// One stored case: its symbol and its lines.
struct StoredMenu {
    var symbol: String
    var items: [MenuItem]
}

/// Reads a stored copy. Lines starting with `#` are notes. `menu <n> symbol=<symbol>` starts a case;
/// each line after it is `<indent> TAB <kind> TAB <action> TAB <title>`, where the kind is `line`,
/// `separator`, `submenu` (a row that opens one), `sub-line` or `sub-separator`, and the action is
/// `none`, `refresh`, `tab <arguments>`, `run <arguments>`, `tabs <arguments> | <arguments> …` (one list
/// of arguments per tab, in order) or `focus <label> <arguments>` (the tab to bring forward, then what to
/// open when it has gone). Arguments are plain words, which never hold a space or `|`, so a space separates
/// them and `|` separates two tabs.
func storedMenus(_ name: String = "menu/every-sample-menu.txt") throws -> [StoredMenu] {
    try storedMenus(text: fixture(name))
}

func storedMenus(text: String) throws -> [StoredMenu] {
    var menus: [StoredMenu] = []
    for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
        if line.hasPrefix("#") { continue }
        if line.hasPrefix("menu ") {
            guard let at = line.range(of: " symbol=") else { throw StoredCopyError.badLine(String(line)) }
            menus.append(StoredMenu(symbol: String(line[at.upperBound...]), items: []))
            continue
        }
        let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        let kinds = ["line", "separator", "submenu", "sub-line", "sub-separator"]
        guard !menus.isEmpty, fields.count == 4, let indent = Int(fields[0]),
              kinds.contains(fields[1]) else { throw StoredCopyError.badLine(String(line)) }
        menus[menus.count - 1].items.append(
            MenuItem(title: fields[3], action: try storedAction(fields[2]), indent: indent,
                     isSeparator: fields[1].hasSuffix("separator"), opensSubmenu: fields[1] == "submenu",
                     inSubmenu: fields[1].hasPrefix("sub-")))
    }
    return menus
}

func storedAction(_ text: String) throws -> MenuAction {
    let words = text.split(separator: " ").map(String.init)
    switch words.first {
    case "none": return .none
    case "refresh": return .refresh
    case "tab": return .tab(Array(words.dropFirst()))
    case "run": return .run(Array(words.dropFirst()))
    case "tabs": return .tabs(words.dropFirst().split(separator: "|").map(Array.init))
    case "focus" where words.count >= 3: return .focus(label: words[1], orOpen: Array(words.dropFirst(2)))
    default: throw StoredCopyError.badLine(text)
    }
}

/// The words of an action as a stored copy writes them; `storedAction` reads them back.
func storedWords(_ action: MenuAction) -> String {
    switch action {
    case .none: return "none"
    case .refresh: return "refresh"
    case .tab(let a): return (["tab"] + a).joined(separator: " ")
    case .run(let a): return (["run"] + a).joined(separator: " ")
    case .tabs(let list): return "tabs " + list.map { $0.joined(separator: " ") }.joined(separator: " | ")
    case .focus(let label, let orOpen): return (["focus", label] + orOpen).joined(separator: " ")
    }
}

/// Menus as a stored copy holds them, cases numbered from 0, with no notes.
func storedText(_ menus: [MenuLines]) -> String {
    menus.enumerated().map { i, menu in
        "menu \(i) symbol=\(menu.symbol)\n" + menu.items.map { item in
            let kind = item.isSeparator ? (item.inSubmenu ? "sub-separator" : "separator")
                : item.opensSubmenu ? "submenu" : item.inSubmenu ? "sub-line" : "line"
            return "\(item.indent)\t\(kind)\t\(storedWords(item.action))\t\(item.title)\n"
        }.joined()
    }.joined()
}

enum StoredCopyError: Error {
    case badLine(String)
}
