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
        MenuActionRunner(macmoshPath: path, tabs: tabs, runner: fake)
    }

    // MARK: the lines

    @Test func theStartLineHasTheVersion() {
        #expect(MenuLog.started(version: "0.1.0") == "MacMosh 0.1.0 started")
    }

    @Test func theRefreshLineHasTheSymbolAndTheCounts() {
        #expect(MenuLog.refreshed(MenuModel.build([]), workhorses: 0)
                == "menu refreshed: symbol=plus.circle workhorses=0 lines=2")
    }

    @Test func theTrackingLineNamesTheMenuInOneOfFourFixedWords() {
        #expect(MenuLog.tracking(.mainMenu) == "menu tracking: object=mainMenu")
        #expect(MenuLog.tracking(.statusMenu) == "menu tracking: object=statusMenu")
        #expect(MenuLog.tracking(.popUp) == "menu tracking: object=popUp")
        #expect(MenuLog.tracking(.other) == "menu tracking: object=other")
        #expect(MenuTrackingObject.allCases.map(\.rawValue) == ["mainMenu", "statusMenu", "popUp", "other"])
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
