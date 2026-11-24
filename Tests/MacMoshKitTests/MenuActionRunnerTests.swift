import Foundation
import Testing
@testable import MacMoshKit

@Suite struct MenuActionRunnerTests {
    private static let path = "/Applications/MacMosh.app/Contents/Helpers/macmosh"

    private func runner(tabs: RecordingTabs = RecordingTabs(), fake: FakeRunner = FakeRunner { _ in FakeRunner.ok() },
                        path: String = MenuActionRunnerTests.path) -> MenuActionRunner {
        MenuActionRunner(macmoshPath: path, tabs: tabs, runner: fake)
    }

    @Test func aTabActionOpensATabRunningTheBundledCommand() async throws {
        let tabs = RecordingTabs()
        let runner = MenuActionRunner(macmoshPath: "/Applications/MacMosh.app/Contents/Helpers/macmosh",
                                      tabs: tabs, runner: FakeRunner { _ in FakeRunner.ok() })
        let said = await runner.perform(.tab(["connect", "mbp", "website"]), title: "website (2 windows: zsh, vim)")
        #expect(said == nil)
        #expect(tabs.opened.map(\.line) == ["/Applications/MacMosh.app/Contents/Helpers/macmosh connect mbp website"])
        #expect(tabs.titles == ["website"])
    }

    @Test func anAppInAFolderWithASpaceSaysToMoveIt() async {
        let tabs = RecordingTabs()
        let runner = MenuActionRunner(macmoshPath: "/Users/alex/My Apps/MacMosh.app/Contents/Helpers/macmosh",
                                      tabs: tabs, runner: FakeRunner { _ in FakeRunner.ok() })
        let said = await runner.perform(.tab(["pair"]), title: "Add a Mac…")
        #expect(said == "MacMosh can't open terminal tabs from where it is now. Move it to the Applications folder and open it again.")
        #expect(tabs.opened.isEmpty)
    }

    @Test func aRunActionRunsTheBundledCommandWithATimeLimit() async {
        let fake = FakeRunner { _ in FakeRunner.ok() }
        let said = await runner(fake: fake).perform(.run(["desk", "window", "mbp", "website"]), title: "New window in website")
        #expect(said == nil)
        #expect(fake.calls.count == 1)
        #expect(fake.calls.first?.argv == [Self.path, "desk", "window", "mbp", "website"])
        #expect(fake.calls.first?.timeout == .seconds(30))
    }

    @Test func aFailedRunActionSaysWhatTheCommandSaid() async {
        let fake = FakeRunner { _ in FakeRunner.failed(4, stderr: "macmosh: first line\nmacmosh: There is no desk called website.\n") }
        let said = await runner(fake: fake).perform(.run(["screen", "mbp"]), title: "Share screen")
        #expect(said == "macmosh: There is no desk called website.")
    }

    @Test func aFailedRunActionWithNothingPrintedGivesTheExitCode() async {
        let fake = FakeRunner { _ in FakeRunner.failed(3) }
        let said = await runner(fake: fake).perform(.run(["screen", "mbp"]), title: "Share screen")
        #expect(said == "That didn't work (exit code 3).")
        let blank = FakeRunner { _ in FakeRunner.failed(5, stderr: "\n  \n") }
        #expect(await runner(fake: blank).perform(.run(["screen", "mbp"]), title: "x") == "That didn't work (exit code 5).")
    }

    @Test func theTabOpenersNoticeIsPassedOn() async {
        let tabs = RecordingTabs(notice: "macOS hasn't let MacMosh control iTerm2, so the tab was opened another way.")
        let said = await runner(tabs: tabs).perform(.tab(["prepare", "mbp", "--pause"]), title: "Run the checklist…")
        #expect(said == "macOS hasn't let MacMosh control iTerm2, so the tab was opened another way.")
    }

    @Test func aTabThatDidNotOpenSaysWhy() async {
        let failed = RecordingTabs(failure: LaunchError.failed("iTerm2 is not installed."))
        #expect(await runner(tabs: failed).perform(.tab(["pair"]), title: "Add a Mac…")
                == "The tab didn't open. iTerm2 is not installed.")
        let denied = RecordingTabs(failure: LaunchError.automationDenied(.appleTerminal))
        let said = await runner(tabs: denied).perform(.tab(["pair"]), title: "Add a Mac…")
        #expect(said?.contains("System Settings > Privacy & Security > Automation") == true)
    }

    @Test func aNoneActionDoesNothing() async {
        let tabs = RecordingTabs()
        let fake = FakeRunner { _ in FakeRunner.ok() }
        #expect(await runner(tabs: tabs, fake: fake).perform(.none, title: "Home address reachable from here: yes") == nil)
        #expect(await runner(tabs: tabs, fake: fake).perform(.refresh, title: "Check now") == nil)
        #expect(tabs.opened.isEmpty)
        #expect(fake.calls.isEmpty)
    }

    // MARK: several tabs (issue #120)

    private static let windows = (1...3).map { ["connect", "mbp", "website", "--window", "@\($0)"] }

    /// A runner whose pause notes itself in the stand-in's events, so the order can be read.
    private func pausing(_ tabs: RecordingTabs) -> MenuActionRunner {
        MenuActionRunner(macmoshPath: Self.path, tabs: tabs, runner: FakeRunner { _ in FakeRunner.ok() },
                         pause: { tabs.note("pause \($0)") })
    }

    @Test func severalTabsOpenInOrderWithAPauseBetweenEach() async {
        let tabs = RecordingTabs()
        let outcome = await pausing(tabs).outcome(of: .tabs(Self.windows), title: "Open website in 3 tabs")
        #expect(outcome == ActionOutcome(summary: "tabs opened: 3", notice: nil))
        #expect(tabs.events == [
            "open \(Self.path) connect mbp website --window @1",
            "pause 0.4 seconds",
            "open \(Self.path) connect mbp website --window @2",
            "pause 0.4 seconds",
            "open \(Self.path) connect mbp website --window @3",
        ])
        #expect(tabs.titles == ["website", "website", "website"])
        #expect(MenuActionRunner.tabsPause == .milliseconds(400))
    }

    @Test func severalTabsStopAtTheFirstThatFailsAndSayHowManyOpened() async {
        let tabs = RecordingTabs(failure: LaunchError.failed("execution error: iTerm2 got an error. (-1728)"), failFrom: 1)
        let outcome = await pausing(tabs).outcome(of: .tabs(Self.windows), title: "Open website in 3 tabs")
        #expect(tabs.events == [
            "open \(Self.path) connect mbp website --window @1",
            "pause 0.4 seconds",
            "open \(Self.path) connect mbp website --window @2",
        ])
        #expect(outcome.summary == "tabs opened: 1 of 3, then tab did not open (error -1728)")
        #expect(outcome.notice == "1 of 3 tabs opened. The tab didn't open. execution error: iTerm2 got an error. (-1728)")
    }

    /// The first failing gives exactly the notice a single tab gives today.
    @Test func whenTheFirstTabFailsTheNoticeIsASingleTabs() async {
        let denied = RecordingTabs(failure: LaunchError.automationDenied(.iterm2))
        let outcome = await pausing(denied).outcome(of: .tabs(Self.windows), title: "x")
        let single = await runner(tabs: RecordingTabs(failure: LaunchError.automationDenied(.iterm2)))
            .outcome(of: .tab(Self.windows[0]), title: "x")
        #expect(denied.events.count == 1)
        #expect(outcome.notice == single.notice)
        #expect(outcome.notice == "macOS hasn't let MacMosh control iTerm2. To allow it: System Settings > Privacy & Security > Automation.")
        #expect(outcome.summary == "tabs opened: 0 of 3, then not allowed to control the terminal app")

        let moved = MenuActionRunner(macmoshPath: "/Users/alex/My Apps/MacMosh.app/Contents/Helpers/macmosh",
                                     tabs: RecordingTabs(), runner: FakeRunner { _ in FakeRunner.ok() })
        let movedOutcome = await moved.outcome(of: .tabs(Self.windows), title: "x")
        #expect(movedOutcome.notice == MenuActionRunner.moveIt)
        #expect(movedOutcome.summary == "tabs opened: 0 of 3, then the app's path can't go in a tab")
    }

    @Test func tabsOpenedAnotherWayKeepTheFirstNotice() async {
        let tabs = RecordingTabs(notice: "macOS hasn't let MacMosh control iTerm2, so the tab was opened another way.")
        let outcome = await pausing(tabs).outcome(of: .tabs(Self.windows), title: "x")
        #expect(outcome.summary == "tabs opened: 3 (another way: 3)")
        #expect(outcome.notice == "macOS hasn't let MacMosh control iTerm2, so the tab was opened another way.")
    }

    @Test func noTabsOpensNothingAndDoesNotPause() async {
        let tabs = RecordingTabs()
        #expect(await pausing(tabs).outcome(of: .tabs([]), title: "x") == ActionOutcome(summary: "tabs opened: 0", notice: nil))
        #expect(tabs.events.isEmpty)
    }

    @Test func theTabTitleIsTheDeskForConnect() {
        #expect(MenuActionRunner.tabTitle(for: ["connect", "mbp", "website"]) == "website")
        #expect(MenuActionRunner.tabTitle(for: ["restart", "mbp"]) == "restart")
        #expect(MenuActionRunner.tabTitle(for: ["pair"]) == "pair")
        #expect(MenuActionRunner.tabTitle(for: ["connect", "mbp"]) == "connect")
        #expect(MenuActionRunner.tabTitle(for: []) == "macmosh")
    }
}
