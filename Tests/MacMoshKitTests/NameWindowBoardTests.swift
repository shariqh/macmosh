import Foundation
import Testing
@testable import MacMoshKit

/// The window's buttons for naming a window (issue 144): in a desk's details, a small "Name…" on each listed
/// window, and "Name its window…" in the strip of a desk with one window; the sheet they open; and where a name
/// shows. All of it only from script 0.11.0 on, with window ids in the report.
private let menuTabs = TabsSeen(tabs: TabsOnThisMac(records: windowsRecords, terminal: .iterm2), at: windowsNow)

private func attic(_ mode: ConnectionMode = .mosh) -> Workhorse { .sample(id: "attic", name: "Attic", mode: mode) }

private func check(_ status: HostStatus, mode: ConnectionMode = .mosh) -> CheckResult {
    .sample(.ready(signIns: true), workhorse: attic(mode), status: status, answeredAt: "192.168.1.20", homeReachable: true)
}

private func board(_ status: HostStatus, mode: ConnectionMode = .mosh, tabs: TabsSeen? = menuTabs) -> BoardWorkhorse {
    BoardModel.build(latest: ["attic": check(status, mode: mode)], lastReady: [:], checking: [], order: [attic(mode)],
                     waitingForDeskServer: [], tabs: tabs, now: windowsNow, timeZone: formatZone).workhorses[0]
}

private func desk(_ w: BoardWorkhorse, _ name: String) -> BoardDesk { w.desks.first { $0.name == name }! }

private func nameButton(_ desk: String, _ window: String) -> BoardButton {
    BoardButton(title: "Name…", action: .window(.nameWindow(workhorse: "attic", desk: desk, window: window)))
}

@Suite struct NameWindowBoardTests {
    // MARK: the board

    @Test func eachWindowOfADeskWithSeveralHasANameButton() {
        let w = board(windowsReport(version: "0.11.0"))
        let website = desk(w, "website")
        #expect(website.windows.map(\.nameButton) == ["@1", "@2", "@3"].map { nameButton("website", $0) })
        #expect(website.buttons.map(\.title) == ["New window", "Rename website…", "Remove website…"])
        // The menu's own window lines are still each window's other button.
        #expect(website.windows.map { $0.button?.title } == ["claude (in a tab)", "zsh (in a tab)", "vim"])
        #expect(desk(w, "api").windows.map(\.nameButton) == ["@5", "@6"].map { nameButton("api", $0) })
    }

    @Test func aDeskWithOneWindowHasNameItsWindowInItsStrip() {
        let w = board(windowsReport(version: "0.11.0"))
        let blog = desk(w, "blog")
        #expect(blog.buttons.map(\.title) == ["New window", "Name its window…", "Rename blog…", "Remove blog…"])
        #expect(blog.buttons[1].action == .window(.nameWindow(workhorse: "attic", desk: "blog", window: "@8")))
        #expect(blog.windows.map(\.nameButton) == [nil])
        #expect(desk(w, "garden").buttons.map(\.title) == ["Rename garden…", "Remove garden…"])
    }

    /// Not past the menu's line-per-window gate (iTerm2's Tabs mode, or before the menu's first build): the same
    /// buttons, since naming needs only the script and the ids.
    @Test func theButtonsDontNeedTheMenusLinePerWindow() {
        for w in [board(windowsReport(version: "0.11.0"), mode: .tabs), board(windowsReport(version: "0.11.0"), tabs: nil)] {
            #expect(desk(w, "website").windows.map(\.nameButton) == ["@1", "@2", "@3"].map { nameButton("website", $0) })
            #expect(desk(w, "website").windows.allSatisfy { $0.button == nil })
            #expect(desk(w, "blog").buttons.map(\.title) == ["New window", "Name its window…", "Rename blog…", "Remove blog…"])
        }
    }

    @Test func anOlderScriptOrNoIdsHasNoNameButtons() {
        for w in [board(windowsReport(version: "0.10.0")), board(windowsReport(version: "0.10.0"), mode: .tabs)] {
            #expect(w.desks.allSatisfy { $0.windows.allSatisfy { $0.nameButton == nil } })
            #expect(!w.desks.contains { $0.buttons.contains { $0.title == "Name its window…" || $0.title == "Name a window…" } })
        }
        // desks-board.txt at 0.11.0: website and api have ids, garden, recipes and blog don't.
        var fixture = try! HostStatus.parse(fixture("status/desks-board.txt"))
        fixture.scriptVersion = "0.11.0"
        let w = board(fixture, tabs: nil)
        #expect(desk(w, "website").windows.allSatisfy { $0.nameButton != nil })
        for name in ["garden", "recipes", "blog"] {
            #expect(desk(w, name).windows.allSatisfy { $0.nameButton == nil }, "\(name)")
            #expect(!desk(w, name).buttons.contains { $0.title == "Name its window…" }, "\(name)")
        }
    }

    @Test func theGreyedListHasNone() {
        let good = check(windowsReport(version: "0.11.0"))
        let locked = CheckResult.sample(.locked, workhorse: attic())
        let w = BoardModel.build(latest: ["attic": locked], lastReady: ["attic": good], checking: [], order: [attic()],
                                 waitingForDeskServer: [], tabs: menuTabs, now: windowsNow, timeZone: formatZone).workhorses[0]
        let greyed = w.lastReadyDesks ?? []
        #expect(!greyed.isEmpty)
        #expect(greyed.allSatisfy { $0.buttons.isEmpty && $0.windows.allSatisfy { $0.nameButton == nil } })
    }

    // MARK: the page

    @Test func theDetailsListEachWindowWithItsOpenAndNameButtons() {
        let row = DeskRow(desk(board(windowsReport(version: "0.11.0")), "website"))
        #expect(row.windowLines.map(\.id) == ["@1", "@2", "@3"])
        #expect(row.windowLines.map(\.title) == ["claude", "zsh", "vim"])
        #expect(row.windowLines.map(\.help) == ["claude (in a tab)", "zsh (in a tab)", "vim"])
        #expect(row.windowLines.map { $0.button?.title } == ["Go to", "Go to", "Open"])
        #expect(row.windowLines.map(\.name) == ["@1", "@2", "@3"].map { nameButton("website", $0) })
        #expect(row.detailButtons.map(\.title) == ["New window", "Rename…", "Remove…"])
    }

    /// Without the menu's window lines, the windows are still listed, by name, with only their Name… button.
    @Test func withoutTheMenusWindowLinesTheWindowsAreListedForNaming() {
        var report = windowsReport(version: "0.11.0")
        report.desks[0].windows[1].name = ""
        let row = DeskRow(desk(board(report, mode: .tabs), "website"))
        #expect(row.windowLines.map(\.title) == ["claude", "window 1", "vim"])
        #expect(row.windowLines.allSatisfy { $0.state == nil })
        #expect(row.windowLines.allSatisfy { $0.button == nil })
        #expect(row.windowLines.map(\.name) == ["@1", "@2", "@3"].map { nameButton("website", $0) })
        // At 0.10.0 in Tabs mode there is nothing to list.
        #expect(DeskRow(desk(board(windowsReport(version: "0.10.0"), mode: .tabs), "website")).windowLines.isEmpty)
    }

    @Test func aDeskWithOneWindowHasNoListAndNameItsWindowInItsStrip() {
        let row = DeskRow(desk(board(windowsReport(version: "0.11.0")), "blog"))
        #expect(row.windowLines.isEmpty)
        #expect(row.detailButtons.map(\.title) == ["New window", "Name its window…", "Rename…", "Remove…"])
    }

    @Test func whileAWindowIsNamedTheDesksButtonsAreOffAndItsRowSaysNaming() {
        let website = desk(board(windowsReport(version: "0.11.0")), "website")
        let row = DeskRow(website, activity: WindowActivity(busy: ["website": .nameWindow]))
        #expect(row.status == "Naming…")
        #expect(row.windowLines.allSatisfy { $0.name?.isEnabled == false && $0.button?.isEnabled == false })
        #expect(row.detailButtons.allSatisfy { !$0.isEnabled })
        let blog = DeskRow(desk(board(windowsReport(version: "0.11.0")), "blog"), activity: WindowActivity(busy: ["blog": .nameWindow]))
        #expect(blog.detailButtons.map(\.title) == ["New window", "Name its window…", "Rename…", "Remove…"])
        #expect(blog.detailButtons.allSatisfy { !$0.isEnabled })
        #expect(DeskRow(website, activity: WindowActivity(updating: ["website"])).status == "Updating…")
    }

    /// A name with a space and a full stop is shown whole: in the row's list of names, and in the details, with and
    /// without the menu's window lines.
    @Test func aNameWithASpaceAndAFullStopIsShownWhole() {
        var report = windowsReport(version: "0.11.0")
        report.desks[0].windows[2].name = "front end v1.2"
        for mode in [ConnectionMode.mosh, .tabs] {
            let row = DeskRow(desk(board(report, mode: mode), "website"))
            #expect(row.windows == "claude, zsh, front end v1.2", "\(mode)")
            #expect(row.windowLines.last?.title == "front end v1.2", "\(mode)")
        }
    }

    // MARK: the sheet

    private func form(_ window: String = "@3", desk: String = "website", version: String = "0.11.0") -> WindowNameForm? {
        WindowNameForm(check: check(windowsReport(version: version)), desk: desk, window: window)
    }

    @Test func theSheetNamesTheDeskAndTheWindowAndHoldsItsName() throws {
        let f = try #require(form())
        #expect(f.title == "Name a window of website")
        #expect(f.label == "Name for window 2 (vim)")
        #expect(f.name == "vim")
        #expect(f.windowID == "@3" && f.number == 2 && f.desk == "website" && f.workhorseID == "attic")
        #expect(WindowNameForm.Words.useProgramsName == "Use its program's name")
        #expect(WindowNameForm.Words.cancel == "Cancel")
        #expect(WindowNameForm.Words.name == "Name")
        #expect(WindowNameForm.Words.naming == "Naming…")
        #expect(try #require(form("@8", desk: "blog")).label == "Name for window 0 (zsh)")
    }

    @Test func thereIsNoSheetForAWindowOrDeskTheCheckDoesntHaveOrAnOlderScript() {
        #expect(form("@40") == nil)
        #expect(form("@1", desk: "garden") == nil)
        #expect(form("@1", desk: "nowhere") == nil)
        #expect(form("@3", version: "0.10.0") == nil)
    }

    /// Name is off until the name is valid and differs from the one it has; the line under the field is the rule,
    /// or why the name can't be used.
    @Test func nameIsOffUntilTheNameIsValidAndDifferent() throws {
        var f = try #require(form())
        #expect(!f.canName)
        #expect(f.help == WindowName.rule && !f.helpIsProblem)
        f.name = "front end"
        #expect(f.canName)
        #expect(f.naming == .named(WindowName("front end")!))
        #expect(f.help == WindowName.rule && !f.helpIsProblem)
        for (typed, why) in [("-x", "A window name can't start with -."), ("--auto", "A window name can't start with -."),
                             ("a#b", "A window name uses letters, digits, spaces, -, _ and full stops only."),
                             (" vim", "A window name can't start or end with a space."), ("", "Type a name."),
                             (String(repeating: "x", count: 33), "A window name is 32 characters at most.")] {
            f.name = typed
            #expect(!f.canName, "\(typed)")
            #expect(f.naming == nil, "\(typed)")
            #expect(f.help == why && f.helpIsProblem, "\(typed)")
        }
        f.name = "vim"
        #expect(!f.canName && !f.helpIsProblem)
    }

    /// A window with no name: the label says only its number, and any valid name differs.
    @Test func aWindowWithNoName() throws {
        var report = windowsReport(version: "0.11.0")
        report.desks[0].windows[1].name = ""
        var f = try #require(WindowNameForm(check: check(report), desk: "website", window: "@2"))
        #expect(f.label == "Name for window 1")
        #expect(f.name == "")
        #expect(!f.canName)
        f.name = "logs"
        #expect(f.canName)
    }
}
