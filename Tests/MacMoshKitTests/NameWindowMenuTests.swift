import Foundation
import Testing
@testable import MacMoshKit

/// The menu's `Name a window…` line in an open desk's submenu (issue 144): there when the workhorse's script is
/// 0.11.0 or newer and the report gives the desk's window ids, in both shapes of the desk's submenu, right after
/// New window; never for a closed desk, an older script or a report without ids.
@Suite struct NameWindowMenuTests {
    private func attic(_ status: HostStatus, mode: ConnectionMode = .mosh) -> CheckResult {
        .sample(.ready(signIns: true), workhorse: .sample(id: "attic", name: "Attic", mode: mode), status: status,
                homeReachable: true)
    }

    private let here = TabsOnThisMac(records: windowsRecords, terminal: .iterm2)

    /// The lines of a desk's submenu, separators as "".
    private func submenu(_ menu: MenuLines, _ desk: String) -> [String] {
        func find(_ entries: [MenuEntry]) -> MenuEntry? {
            for e in entries {
                if e.id == "desk:attic:\(desk)" { return e }
                if let found = find(e.children) { return found }
            }
            return nil
        }
        return find(menu.entries)?.submenu.map { $0.isSeparator ? "" : $0.title } ?? []
    }

    private func line(_ menu: MenuLines, _ desk: String) -> MenuEntry? {
        func find(_ entries: [MenuEntry]) -> MenuEntry? {
            for e in entries {
                if e.id == "desk:attic:\(desk):nameWindow" { return e }
                if let found = find(e.children + e.submenu) { return found }
            }
            return nil
        }
        return find(menu.entries)
    }

    @Test func theGateIsTheScriptsVersionAndTheWindowIds() {
        let report = windowsReport(version: "0.11.0")
        let website = report.desks[0]
        #expect(WindowNameGate.passes(attic(report), desk: website))
        #expect(WindowNameGate.passes(attic(windowsReport(version: "0.12.3")), desk: website))
        #expect(WindowNameGate.passes(attic(windowsReport(version: "1.0.0")), desk: website))
        #expect(!WindowNameGate.passes(attic(windowsReport(version: "0.10.0")), desk: website))
        #expect(!WindowNameGate.passes(attic(windowsReport(version: "0.9.9")), desk: website))
        #expect(!WindowNameGate.passes(attic(windowsReport(version: "")), desk: website))
        // A closed desk has no windows to name.
        #expect(!WindowNameGate.passes(attic(report), desk: nil))
        // A report without the windows' ids.
        var noIds = website
        noIds.windows = noIds.windows.map { HostStatus.Window(index: $0.index, name: $0.name) }
        #expect(!WindowNameGate.passes(attic(report), desk: noIds))
        // The connection doesn't matter: in Tabs mode the line is there too.
        #expect(WindowNameGate.passes(attic(report, mode: .tabs), desk: website))
        #expect(WindowNameGate.firstScriptVersion == DeskFlow.nameWindowNeeds)
    }

    @Test func theLineOpensATabThatAsksWhichWindowAndTheName() {
        let menu = MenuModel.build([.checked(attic(windowsReport(version: "0.11.0")))], tabs: here, now: windowsNow)
        let found = line(menu, "website")
        #expect(found?.title == "Name a window…")
        #expect(found?.action == .tab(["desk", "name-window", "attic", "website"]))
        #expect(found.map { $0.action.words.allSatisfy(PlainWords.isPlain) } == true)
    }

    /// Shape (a): the line comes right after New window, in its group, for every open desk; not for garden.
    @Test func withALinePerWindowItComesRightAfterNewWindow() {
        let menu = MenuModel.build([.checked(attic(windowsReport(version: "0.11.0")))], tabs: here, now: windowsNow)
        #expect(submenu(menu, "website") == ["Open the 1 window not in a tab", "", "claude (in a tab)", "zsh (in a tab)", "vim",
                                             "", "New window", "Name a window…", "",
                                             "Rename website…", "Remove website…", "kept running, permanent"])
        #expect(submenu(menu, "notes") == ["Go to notes", "", "New window", "Name a window…", "", "Rename notes…", "Remove notes…"])
        #expect(submenu(menu, "garden") == ["Open garden", "", "Rename garden…", "Remove garden…", "permanent"])
        for desk in ["website", "api", "notes", "blog", "shop"] { #expect(line(menu, desk) != nil, "\(desk)") }
    }

    /// Shape (b), here in iTerm2's Tabs mode: the line comes right after New window, before Rename… and Remove….
    @Test func withoutALinePerWindowItComesRightAfterNewWindowToo() {
        let menu = MenuModel.build([.checked(attic(windowsReport(version: "0.11.0"), mode: .tabs))], tabs: here, now: windowsNow)
        #expect(submenu(menu, "website") == ["Open website", "New window", "Name a window…", "", "Rename website…", "Remove website…"])
        #expect(submenu(menu, "garden") == ["Open garden", "", "Rename garden…", "Remove garden…"])
        #expect(line(menu, "blog")?.action == .tab(["desk", "name-window", "attic", "blog"]))
    }

    /// Before 0.11.0, or without window ids, neither shape has the line.
    @Test func anOlderScriptOrNoIdsHasNoLine() {
        for mode in [ConnectionMode.mosh, .tabs] {
            let older = MenuModel.build([.checked(attic(windowsReport(version: "0.10.0"), mode: mode))], tabs: here, now: windowsNow)
            #expect(!older.items.contains { $0.title == "Name a window…" }, "\(mode)")
        }
        // HostStatus.sampleWithDesk has no window ids; at 0.11.0 there is still no line.
        var noIds = HostStatus.sampleWithDesk
        noIds.scriptVersion = "0.11.0"
        let menu = MenuModel.build([.checked(.sample(.ready(signIns: true), status: noIds))])
        #expect(!menu.items.contains { $0.title == "Name a window…" })
    }

    @Test func theButtonsOfOneDeskStillHaveDifferentKeys() {
        let buttons = ButtonRules.forDesk(workhorse: "attic", desk: "website", isOpen: true, canNameWindows: true)
        #expect(buttons.map(\.title) == ["Open website", "New window", "Name a window…", "Rename website…", "Remove website…"])
        #expect(Set(buttons.map(\.key)).count == buttons.count)
        #expect(ButtonRules.forDesk(workhorse: "attic", desk: "website", isOpen: false, canNameWindows: true).map(\.title)
                == ["Open website", "Rename website…", "Remove website…"])
        #expect(ButtonRules.forDesk(workhorse: "attic", desk: "website", isOpen: true)
                == ButtonRules.forDesk(workhorse: "attic", desk: "website", isOpen: true, canNameWindows: false))
    }

    /// A name with a space and a full stop is shown whole in the menu, in both shapes.
    @Test func aNameWithASpaceAndAFullStopIsShownWhole() {
        var report = windowsReport(version: "0.11.0")
        report.desks[0].windows[2].name = "front end v1.2"
        let lines = MenuModel.build([.checked(attic(report))], tabs: here, now: windowsNow)
        #expect(submenu(lines, "website").contains("front end v1.2"))
        let tabs = MenuModel.build([.checked(attic(report, mode: .tabs))], tabs: here, now: windowsNow)
        #expect(tabs.items.contains { $0.title == "website (3 windows: claude, zsh, front end v1.2, kept running, permanent)" })
    }
}
