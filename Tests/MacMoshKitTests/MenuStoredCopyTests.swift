import Foundation
import Testing
@testable import MacMoshKit

/// What the menu showed before it was built as a tree (issue #108), kept in
/// `Fixtures/menu/every-sample-menu.txt`. Every case of `everySampleMenu()`, then every case of
/// `moreSampleMenus()`, must still give exactly those lines: the same symbol, and for each line the
/// same title, indent, action and separator.
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

    @Test func theStoredCopyCoversEveryKindOfLine() throws {
        let items = try storedMenus().flatMap(\.items)
        #expect(items.contains { $0.isSeparator })
        #expect(items.contains { $0.action == .refresh })
        #expect(items.contains { if case .tab = $0.action { return true }; return false })
        #expect(items.contains { if case .run = $0.action { return true }; return false })
        #expect(Set(items.map(\.indent)) == [0, 1, 2])
    }
}

/// Menus `everySampleMenu()` doesn't reach: the wait for the desk server, open, kept, permanent,
/// closed and leftover desks, a laptop with lid-closed mode on, no home-address light, a time in a
/// hint, an older Mac that can't be unlocked over ssh, and two workhorses with a desk of the same name.
func moreSampleMenus() -> [Menu] {
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
        MenuModel.build([.checked(serverDown)], waitingForDeskServer: ["mbp"]),
        MenuModel.build([.checked(serverDown)]),
        MenuModel.build([.checked(.sample(.ready(signIns: true), status: desks, homeReachable: true))]),
        MenuModel.build([.checked(.sample(.ready(signIns: true), status: desktop))]),
        MenuModel.build([.checked(seen)], now: formatNow, timeZone: formatZone),
        MenuModel.build([.checked(.sample(.locked, workhorse: old))]),
        MenuModel.build([
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

/// Reads the stored copy. Lines starting with `#` are notes. `menu <n> symbol=<symbol>` starts a case;
/// each line after it is `<indent> TAB <line|separator> TAB <action> TAB <title>`, where the action is
/// `none`, `refresh`, `tab <arguments>` or `run <arguments>`. Arguments are plain words, so a space
/// separates them.
func storedMenus() throws -> [StoredMenu] {
    var menus: [StoredMenu] = []
    for line in try fixture("menu/every-sample-menu.txt").split(separator: "\n", omittingEmptySubsequences: true) {
        if line.hasPrefix("#") { continue }
        if line.hasPrefix("menu ") {
            guard let at = line.range(of: " symbol=") else { throw StoredCopyError.badLine(String(line)) }
            menus.append(StoredMenu(symbol: String(line[at.upperBound...]), items: []))
            continue
        }
        let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard !menus.isEmpty, fields.count == 4, let indent = Int(fields[0]),
              fields[1] == "line" || fields[1] == "separator" else { throw StoredCopyError.badLine(String(line)) }
        menus[menus.count - 1].items.append(
            MenuItem(title: fields[3], action: try storedAction(fields[2]), indent: indent,
                     isSeparator: fields[1] == "separator"))
    }
    return menus
}

private func storedAction(_ text: String) throws -> MenuAction {
    let words = text.split(separator: " ").map(String.init)
    switch words.first {
    case "none": return .none
    case "refresh": return .refresh
    case "tab": return .tab(Array(words.dropFirst()))
    case "run": return .run(Array(words.dropFirst()))
    default: throw StoredCopyError.badLine(text)
    }
}

enum StoredCopyError: Error {
    case badLine(String)
}
