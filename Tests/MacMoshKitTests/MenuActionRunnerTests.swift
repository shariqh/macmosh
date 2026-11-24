import Foundation
import Testing
@testable import MacMoshKit

@Suite struct MenuActionRunnerTests {
    private static let path = "/Applications/MacMosh.app/Contents/Helpers/macmosh"

    private func runner(tabs: RecordingTabs = RecordingTabs(), fake: FakeRunner = FakeRunner { _ in FakeRunner.ok() },
                        path: String = MenuActionRunnerTests.path) -> MenuActionRunner {
        MenuActionRunner(macmoshPath: path, tabs: tabs, runner: fake, records: scratchTabRecords())
    }

    @Test func aTabActionOpensATabRunningTheBundledCommand() async throws {
        let tabs = RecordingTabs()
        let runner = MenuActionRunner(macmoshPath: "/Applications/MacMosh.app/Contents/Helpers/macmosh",
                                      tabs: tabs, runner: FakeRunner { _ in FakeRunner.ok() }, records: scratchTabRecords())
        let said = await runner.perform(.tab(["connect", "mbp", "website"]), title: "website (2 windows: zsh, vim)")
        #expect(said == nil)
        #expect(tabs.opened.map(\.line) == ["/Applications/MacMosh.app/Contents/Helpers/macmosh connect mbp website"])
        #expect(tabs.titles == ["website"])
    }

    @Test func anAppInAFolderWithASpaceSaysToMoveIt() async {
        let tabs = RecordingTabs()
        let runner = MenuActionRunner(macmoshPath: "/Users/alex/My Apps/MacMosh.app/Contents/Helpers/macmosh",
                                      tabs: tabs, runner: FakeRunner { _ in FakeRunner.ok() }, records: scratchTabRecords())
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
                         records: scratchTabRecords(), pause: { tabs.note("pause \($0)") })
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
                                     tabs: RecordingTabs(), runner: FakeRunner { _ in FakeRunner.ok() }, records: scratchTabRecords())
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

    // MARK: bringing a tab forward (issue #120)

    private static let label = "9f3a1c2e9f3a1c2e"
    private static let started: Int64 = 1_800_000_000_123_456
    private static let fallback = ["connect", "mbp", "website", "--window", "@3"]
    private static let focus = MenuAction.focus(label: label, orOpen: fallback)
    private static let closed = "That tab has closed, so MacMosh opened a new one."

    /// A record store holding one record for `label`, whose process runs unless `running` says otherwise.
    private func records(tty: String = "/dev/ttys004", terminal: TabRecord.Terminal = .iterm2,
                         running: [Int32: Int64] = [4242: started]) throws -> TabRecordStore {
        let store = scratchTabRecords(running: running)
        try store.write(sampleTabRecord(label: Self.label, pid: 4242, started: Self.started, tty: tty, terminal: terminal))
        return store
    }

    private func focusing(_ tabs: RecordingTabs, _ store: TabRecordStore,
                          fake: FakeRunner = FakeRunner { _ in FakeRunner.ok() }) -> MenuActionRunner {
        MenuActionRunner(macmoshPath: Self.path, tabs: tabs, runner: fake, records: store)
    }

    @Test func aLiveTabIsBroughtForwardByItsDeviceInItsTerminal() async throws {
        let tabs = RecordingTabs(selection: .success(.selected))
        let store = try records(tty: "/dev/ttys004", terminal: .terminal)
        let fake = FakeRunner { _ in FakeRunner.ok() }
        let outcome = await focusing(tabs, store, fake: fake).outcome(of: Self.focus, title: "vim (in a tab)")
        #expect(outcome == ActionOutcome(summary: "tab selected", notice: nil))
        #expect(tabs.events == ["select /dev/ttys004 terminal"])
        #expect(store.record(label: Self.label) != nil)
        // Not the background helper: nothing ran `macmosh`.
        #expect(fake.calls.isEmpty)
    }

    @Test func aRecordOfAnUnknownTerminalIsHandedOnAsUnknown() async throws {
        let tabs = RecordingTabs()
        _ = await focusing(tabs, try records(terminal: .unknown)).outcome(of: Self.focus, title: "x")
        #expect(tabs.events == ["select /dev/ttys004 unknown"])
    }

    @Test func aTabTheTerminalCantFindIsRemovedAndOpenedAgain() async throws {
        let tabs = RecordingTabs(selection: .success(.gone))
        let store = try records()
        let outcome = await focusing(tabs, store).outcome(of: Self.focus, title: "x")
        #expect(tabs.events == ["select /dev/ttys004 iterm2", "open \(Self.path) connect mbp website --window @3"])
        #expect(tabs.titles == ["website"])
        #expect(outcome == ActionOutcome(summary: "tab gone (not in the terminal), opened a new one", notice: Self.closed))
        #expect(store.record(label: Self.label) == nil)
    }

    @Test func noRecordOpensANewTabWithoutAsking() async throws {
        let tabs = RecordingTabs()
        let outcome = await focusing(tabs, scratchTabRecords()).outcome(of: Self.focus, title: "x")
        #expect(tabs.events == ["open \(Self.path) connect mbp website --window @3"])
        #expect(outcome == ActionOutcome(summary: "tab gone (no record), opened a new one", notice: Self.closed))
    }

    @Test(arguments: [[Int32: Int64](), [4242: 1_800_000_999_000_000]])
    func aRecordWhoseProcessEndedIsRemovedAndOpenedAgain(_ running: [Int32: Int64]) async throws {
        let tabs = RecordingTabs()
        let store = try records(running: running)
        let outcome = await focusing(tabs, store).outcome(of: Self.focus, title: "x")
        #expect(tabs.events == ["open \(Self.path) connect mbp website --window @3"])
        #expect(outcome == ActionOutcome(summary: "tab gone (process ended), opened a new one", notice: Self.closed))
        #expect(store.record(label: Self.label) == nil)
    }

    @Test(arguments: ["", "/dev/tty004", "/dev/ttys004; x", "/dev/ttys"])
    func aRecordWithNoUsableDeviceIsRemovedAndOpenedAgain(_ tty: String) async throws {
        let tabs = RecordingTabs()
        let store = try records(tty: tty)
        let outcome = await focusing(tabs, store).outcome(of: Self.focus, title: "x")
        #expect(tabs.events == ["open \(Self.path) connect mbp website --window @3"])
        #expect(outcome == ActionOutcome(summary: "tab gone (no terminal device), opened a new one", notice: Self.closed))
        #expect(store.record(label: Self.label) == nil)
    }

    /// A word that is not a label never names a file, so nothing is read or removed, and a new tab opens.
    @Test(arguments: ["../9f3a1c2e9f3a1c2e", "", "9F3A1C2E", "9f3a 1c2e"])
    func aWordThatIsNotALabelIsTreatedAsGone(_ word: String) async throws {
        let tabs = RecordingTabs()
        let store = try records()
        let outcome = await focusing(tabs, store).outcome(of: .focus(label: word, orOpen: Self.fallback), title: "x")
        #expect(tabs.events == ["open \(Self.path) connect mbp website --window @3"])
        #expect(outcome.summary == "tab gone (no record), opened a new one")
        #expect(store.record(label: Self.label) != nil)
    }

    /// A refusal gives the sentence opening a tab gives, word for word, and keeps the record.
    @Test func aRefusalGivesTodaysSentence() async throws {
        let tabs = RecordingTabs(selection: .failure(LaunchError.automationDenied(.iterm2)))
        let store = try records()
        let outcome = await focusing(tabs, store).outcome(of: Self.focus, title: "x")
        let single = await runner(tabs: RecordingTabs(failure: LaunchError.automationDenied(.iterm2)))
            .outcome(of: .tab(Self.fallback), title: "x")
        #expect(outcome == single)
        #expect(outcome == ActionOutcome(summary: "not allowed to control the terminal app",
                                         notice: "macOS hasn't let MacMosh control iTerm2. To allow it: System Settings > Privacy & Security > Automation."))
        #expect(tabs.events == ["select /dev/ttys004 iterm2"])
        #expect(store.record(label: Self.label) != nil)
    }

    @Test func anyOtherFailureSaysTheTabCouldntBeBroughtForward() async throws {
        let failed = RecordingTabs(selection: .failure(LaunchError.failed("execution error: iTerm2 got an error. (-1728)")))
        let store = try records()
        let outcome = await focusing(failed, store).outcome(of: Self.focus, title: "x")
        #expect(outcome == ActionOutcome(summary: "tab not selected (error -1728)",
                                         notice: "Couldn't bring that tab forward. execution error: iTerm2 got an error. (-1728)"))
        #expect(failed.events == ["select /dev/ttys004 iterm2"])
        #expect(store.record(label: Self.label) != nil)

        let slow = RecordingTabs(selection: .failure(LaunchError.failed("iTerm2 did not answer in time.")))
        #expect(await focusing(slow, try records()).outcome(of: Self.focus, title: "x")
                == ActionOutcome(summary: "tab not selected (no answer in time)",
                                 notice: "Couldn't bring that tab forward. iTerm2 did not answer in time."))

        struct Other: Error {}
        let other = RecordingTabs(selection: .failure(Other()))
        #expect(await focusing(other, try records()).outcome(of: Self.focus, title: "x")
                == ActionOutcome(summary: "tab not selected", notice: "Couldn't bring that tab forward."))
    }

    /// When the new tab doesn't open either, that failure is what is said.
    @Test func aFallbackThatFailsSaysWhy() async throws {
        let tabs = RecordingTabs(failure: LaunchError.failed("execution error: iTerm2 got an error. (-1728)"))
        let outcome = await focusing(tabs, scratchTabRecords()).outcome(of: Self.focus, title: "x")
        #expect(outcome == ActionOutcome(summary: "tab gone (no record), then tab did not open (error -1728)",
                                         notice: "The tab didn't open. execution error: iTerm2 got an error. (-1728)"))
        let moved = MenuActionRunner(macmoshPath: "/Users/alex/My Apps/MacMosh.app/Contents/Helpers/macmosh",
                                     tabs: RecordingTabs(), runner: FakeRunner { _ in FakeRunner.ok() },
                                     records: scratchTabRecords())
        #expect(await moved.outcome(of: Self.focus, title: "x").notice == MenuActionRunner.moveIt)
    }

    @Test func aFallbackOpenedAnotherWaySaysBoth() async throws {
        let other = "macOS hasn't let MacMosh control iTerm2, so the tab was opened another way."
        let outcome = await focusing(RecordingTabs(notice: other), scratchTabRecords()).outcome(of: Self.focus, title: "x")
        #expect(outcome == ActionOutcome(summary: "tab gone (no record), opened a new one another way",
                                         notice: "\(Self.closed) \(other)"))
    }

    @Test func theTabTitleIsTheDeskForConnect() {
        #expect(MenuActionRunner.tabTitle(for: ["connect", "mbp", "website"]) == "website")
        #expect(MenuActionRunner.tabTitle(for: ["restart", "mbp"]) == "restart")
        #expect(MenuActionRunner.tabTitle(for: ["pair"]) == "pair")
        #expect(MenuActionRunner.tabTitle(for: ["connect", "mbp"]) == "connect")
        #expect(MenuActionRunner.tabTitle(for: []) == "macmosh")
    }
}
