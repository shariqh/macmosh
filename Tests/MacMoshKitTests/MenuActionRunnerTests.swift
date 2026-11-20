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

    @Test func theTabTitleIsTheDeskForConnect() {
        #expect(MenuActionRunner.tabTitle(for: ["connect", "mbp", "website"]) == "website")
        #expect(MenuActionRunner.tabTitle(for: ["restart", "mbp"]) == "restart")
        #expect(MenuActionRunner.tabTitle(for: ["pair"]) == "pair")
        #expect(MenuActionRunner.tabTitle(for: ["connect", "mbp"]) == "connect")
        #expect(MenuActionRunner.tabTitle(for: []) == "macmosh")
    }
}
