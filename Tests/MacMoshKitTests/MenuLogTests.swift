import AppKit
import Foundation
import Testing
@testable import MacMoshKit

/// Collects the lines a refresher wrote to its log.
private final class Lines: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    func add(_ line: String) { lock.withLock { lines.append(line) } }
    var all: [String] { lock.withLock { lines } }
}

@MainActor @Suite struct MenuLogTests {
    private static let path = "/Applications/MacMosh.app/Contents/Helpers/macmosh"

    private func actions(tabs: RecordingTabs = RecordingTabs(),
                         fake: FakeRunner = FakeRunner { _ in FakeRunner.ok() },
                         path: String = MenuLogTests.path) -> MenuActionRunner {
        MenuActionRunner(macmoshPath: path, tabs: tabs, runner: fake, records: scratchTabRecords())
    }

    // MARK: the lines

    @Test func theStartLineHasTheVersion() {
        #expect(MenuLog.started(version: "0.1.0") == "MacMosh 0.1.0 started")
    }

    @Test func theRefreshLineHasTheSymbolAndTheCounts() {
        #expect(MenuLog.refreshed(MenuModel.build([]), workhorses: 0)
                == "menu refreshed: symbol=plus.circle workhorses=0 lines=2")
    }

    /// The main window's line (main window design, section 7.3). CI reads it, and checks that it is not
    /// there at launch.
    @Test func theWindowOpenedLineIsFixedWords() {
        #expect(MenuLog.windowOpened == "window opened")
    }

    /// How the app comes to quit, or not: the icon removed, the last window closed, and the quit itself.
    @Test func theQuitLinesAreFixedWords() {
        #expect(MenuLog.iconRemoved == "menu-bar icon removed: quitting")
        #expect(MenuLog.lastWindowClosed == "last window closed: the app stays")
        #expect(MenuLog.quitting == "app quitting")
    }

    /// Issue #107: a change held back while the menu is open with a submenu, and when it was shown.
    @Test func theHeldChangeLinesAreFixedWords() {
        #expect(MenuLog.held(.open) == "menu held a change: open with a submenu")
        #expect(MenuLog.held(.closing) == "menu held a change: closing with a submenu")
        #expect(MenuLog.heldShown(.closed) == "menu showed the held change: closed")
        #expect(MenuLog.heldShown(.opened) == "menu showed the held change: opened")
    }

    @Test func theTrackingLineNamesTheMenuInOneOfFourFixedWords() {
        #expect(MenuLog.tracking(.mainMenu) == "menu tracking: object=mainMenu")
        #expect(MenuLog.tracking(.statusMenu) == "menu tracking: object=statusMenu")
        #expect(MenuLog.tracking(.popUp) == "menu tracking: object=popUp")
        #expect(MenuLog.tracking(.other) == "menu tracking: object=other")
        #expect(MenuTrackingObject.allCases.map(\.rawValue) == ["mainMenu", "statusMenu", "popUp", "other"])
    }

    @Test func onlyTheMainMenuItselfCountsAsTheMainMenu() {
        let main = NSMenu(title: "Main")
        let sameTitle = NSMenu(title: "Main")
        #expect(MenuTrackingObject.of(main, mainMenu: main) == .mainMenu)
        #expect(MenuTrackingObject.of(sameTitle, mainMenu: main) == .other)
        #expect(MenuTrackingObject.of(NSMenu(title: "Other"), mainMenu: nil) == .other)
        #expect(MenuTrackingObject.of(nil, mainMenu: main) == .other)
        #expect(MenuTrackingObject.of(nil, mainMenu: nil) == .other)
    }

    @Test func anActionLineNamesOnlyTheSubcommand() {
        #expect(MenuLog.asked(.tab(["connect", "workhorse", "website"])) == "menu action: tab connect")
        #expect(MenuLog.asked(.run(["desk", "window", "workhorse", "website"])) == "menu action: run desk")
        #expect(MenuLog.asked(.tab([])) == "menu action: tab")
        #expect(MenuLog.asked(.refresh) == "menu action: refresh")
        #expect(MenuLog.asked(.none) == "menu action: none")
        #expect(MenuLog.finished(.tab(["connect", "workhorse", "website"]), summary: "tab opened")
                == "menu action done: tab connect: tab opened")
    }

    /// The two tab actions of issue #120: the subcommand of the first tab, never a desk, a window or a label.
    @Test func theTabsAndFocusLinesNameOnlyTheSubcommand() {
        let open = ["connect", "workhorse", "website", "--window", "@3"]
        #expect(MenuLog.asked(.tabs([open, open])) == "menu action: tabs connect")
        #expect(MenuLog.asked(.tabs([])) == "menu action: tabs")
        #expect(MenuLog.asked(.focus(label: "9f3a1c2e", orOpen: open)) == "menu action: focus connect")
        #expect(MenuLog.asked(.focus(label: "9f3a1c2e", orOpen: [])) == "menu action: focus")
        #expect(MenuLog.finished(.focus(label: "9f3a1c2e", orOpen: open), summary: "tab selected")
                == "menu action done: focus connect: tab selected")
        #expect(MenuLog.finished(.tabs([open]), summary: "tabs opened: 1")
                == "menu action done: tabs connect: tabs opened: 1")
    }

    /// Each way a focus action ends, in fixed words: never a label, a device, a desk or a terminal's text.
    @Test func theFocusSummariesAreFixedWords() {
        #expect(MenuLog.tabSelected == "tab selected")
        #expect(MenuLog.tabGone(.noRecord, then: "opened a new one") == "tab gone (no record), opened a new one")
        #expect(MenuLog.tabGone(.processEnded, then: "opened a new one") == "tab gone (process ended), opened a new one")
        #expect(MenuLog.tabGone(.noDevice, then: "opened a new one") == "tab gone (no terminal device), opened a new one")
        #expect(MenuLog.tabGone(.notInTerminal, then: "then tab did not open")
                == "tab gone (not in the terminal), then tab did not open")
        let fromITerm = "31:99: execution error: iTerm got an error: Can’t get window 1 of workhorse. (-1719)"
        #expect(MenuLog.selectFailure(fromITerm) == "tab not selected (error -1719)")
        #expect(MenuLog.selectFailure("Terminal did not answer in time.") == "tab not selected (no answer in time)")
        #expect(MenuLog.selectFailure("something about workhorse") == "tab not selected")
        #expect(MenuLog.selectFailure("") == "tab not selected")
    }

    @Test func clearedRecordsAreCountedNotNamed() {
        #expect(MenuLog.recordsCleared(2) == "tab records cleared: 2")
    }

    @Test func theTabsSummariesAreNumbersAndFixedWords() {
        #expect(MenuLog.tabsOpened(3, anotherWay: 0) == "tabs opened: 3")
        #expect(MenuLog.tabsOpened(3, anotherWay: 2) == "tabs opened: 3 (another way: 2)")
        #expect(MenuLog.tabsStopped(opened: 1, of: 3, then: "tab did not open (error -1728)")
                == "tabs opened: 1 of 3, then tab did not open (error -1728)")
    }

    @Test func aTabFailureKeepsOnlyTheErrorNumber() {
        let fromITerm = "31:99: execution error: iTerm got an error: Can’t get window 1 of workhorse. (-1719)"
        #expect(MenuLog.tabFailure(fromITerm) == "tab did not open (error -1719)")
        #expect(MenuLog.tabFailure("iTerm2 did not answer in time.") == "tab did not open (no answer in time)")
        #expect(MenuLog.tabFailure("something about workhorse (not a number)") == "tab did not open")
        #expect(MenuLog.tabFailure("") == "tab did not open")
    }

    // MARK: what an action came to

    @Test func aTabThatOpenedSaysSo() async {
        let outcome = await actions().outcome(of: .tab(["pair"]), title: "Add a Mac…")
        #expect(outcome == ActionOutcome(summary: "tab opened", notice: nil))
    }

    @Test func aTabOpenedTheOtherWayKeepsItsSentenceOutOfTheSummary() async {
        let tabs = RecordingTabs(notice: "macOS hasn't let MacMosh control iTerm2, so the tab was opened another way.")
        let outcome = await actions(tabs: tabs).outcome(of: .tab(["pair"]), title: "Add a Mac…")
        #expect(outcome.summary == "tab opened another way")
        #expect(outcome.notice == "macOS hasn't let MacMosh control iTerm2, so the tab was opened another way.")
    }

    @Test func aTabThatDidNotOpenIsSummedUpWithoutItsWords() async {
        let failed = RecordingTabs(failure: LaunchError.failed("execution error: workhorse said no. (-1728)"))
        let outcome = await actions(tabs: failed).outcome(of: .tab(["connect", "workhorse", "website"]), title: "website")
        #expect(outcome.summary == "tab did not open (error -1728)")
        #expect(outcome.notice == "The tab didn't open. execution error: workhorse said no. (-1728)")

        let denied = RecordingTabs(failure: LaunchError.automationDenied(.iterm2))
        #expect(await actions(tabs: denied).outcome(of: .tab(["pair"]), title: "Add a Mac…").summary
                == "not allowed to control the terminal app")

        struct Other: Error {}
        let other = RecordingTabs(failure: Other())
        #expect(await actions(tabs: other).outcome(of: .tab(["pair"]), title: "Add a Mac…").summary
                == "tab did not open")
    }

    @Test func anAppPathATabCantCarryIsSummedUp() async {
        let moved = actions(path: "/Users/alex/My Apps/MacMosh.app/Contents/Helpers/macmosh")
        #expect(await moved.outcome(of: .tab(["pair"]), title: "Add a Mac…").summary
                == "the app's path can't go in a tab")
    }

    @Test func aBackgroundCommandIsSummedUpByItsExitCode() async {
        #expect(await actions().outcome(of: .run(["screen", "workhorse"]), title: "Share screen")
                == ActionOutcome(summary: "ran", notice: nil))
        let fake = FakeRunner { _ in FakeRunner.failed(4, stderr: "macmosh: Can't reach workhorse.\n") }
        let outcome = await actions(fake: fake).outcome(of: .run(["screen", "workhorse"]), title: "Share screen")
        #expect(outcome.summary == "run failed (exit code 4)")
        #expect(outcome.notice == "macmosh: Can't reach workhorse.")
    }

    @Test func anActionWithNothingToRunSaysSo() async {
        #expect(await actions().outcome(of: .refresh, title: "Check now")
                == ActionOutcome(summary: "nothing to run", notice: nil))
        #expect(await actions().outcome(of: .none, title: "x").summary == "nothing to run")
    }

    // MARK: what the refresher writes

    @Test func aRefreshIsLoggedOnlyWhenTheMenuChanges() async {
        let lines = Lines()
        let r = MenuRefresher(load: { [] }, gather: { _ in [] }, save: { _ in }, log: { lines.add($0) })
        await r.refresh()
        await r.refresh()
        #expect(lines.all == ["menu refreshed: symbol=plus.circle workhorses=0 lines=2"])
    }

    @Test func aDamagedListIsLoggedWithoutItsWords() async {
        let lines = Lines()
        let r = MenuRefresher(load: { throw StoreError.unreadable("workhorses.json: not JSON") },
                              gather: { _ in [] }, save: { _ in }, log: { lines.add($0) })
        await r.refresh()
        await r.refresh()
        #expect(lines.all == ["menu refreshed: the saved list can't be read"])
    }

    @Test func anActionIsLoggedBeforeAndAfterWithNoNamesInIt() async {
        let lines = Lines()
        let r = MenuRefresher(load: { [.sample(id: "workhorse", name: "Workhorse Mac")] },
                              gather: { list in list.map { .checked(.sampleReady(id: $0.id, name: $0.name)) } },
                              save: { _ in }, log: { lines.add($0) })
        await r.perform(.line("website (1 window)", .tab(["connect", "workhorse", "website"])), using: actions())
        #expect(lines.all == [
            "menu action: tab connect",
            "menu action done: tab connect: tab opened",
            MenuLog.refreshed(r.menu, workhorses: 1),
        ])
        #expect(lines.all.last?.hasPrefix("menu refreshed: symbol=checkmark.circle workhorses=1 lines=") == true)
        #expect(!lines.all.contains { $0.localizedCaseInsensitiveContains("workhorse ") || $0.contains("website") })
    }

    @Test func openingTheMenuIsLoggedAndChecksAgain() async {
        let lines = Lines()
        let r = MenuRefresher(load: { [] }, gather: { _ in [] }, save: { _ in }, log: { lines.add($0) })
        await r.menuOpened()
        #expect(lines.all == ["menu opened", "menu refreshed: symbol=plus.circle workhorses=0 lines=2"])
        #expect(r.menu.items.map(\.title) == ["No workhorses yet", "Add a Mac…"])
    }
}
