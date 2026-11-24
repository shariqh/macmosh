import Foundation
import Testing
@testable import MacMoshKit

/// Bringing a tab forward by its terminal device (menu design 8.4, issue #120). Every test uses a stand-in
/// runner, so no script is run and no terminal is touched.
@Suite struct TabSelectTests {
    private static let denied = "execution error: Not authorized to send Apple events to Terminal. (-1743)"

    private func opener(_ settings: AppSettings = AppSettings(), installed: Set<String> = [],
                        runner: FakeRunner) -> TabOpener {
        TabOpener(runner: runner, settings: settings,
                  temporaryFolder: FileManager.default.temporaryDirectory.appendingPathComponent("macmosh-test-unused"),
                  fileExists: { installed.contains($0) })
    }

    /// The scripts of the design's section 8.4 since issue #129: three steps, each a fresh search by the
    /// device, and a one-line answer. CI's "Terminal scripts" job runs these texts against the real apps.
    static let iTermScript = """
    on run argv
        repeat with i from 1 to 3
            set step to character i of "ABC"
            try
                if not atStep(step, item 1 of argv) then return "gone"
            on error number n
                return "failed " & step & " " & n
            end try
        end repeat
        return "ok"
    end run

    on atStep(step, wanted)
        tell application "iTerm2"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if (tty of s) is wanted then
                            if step is "A" then
                                if miniaturized of w then set miniaturized of w to false
                            else if step is "B" then
                                select w
                            else
                                select t
                                select s
                                activate
                            end if
                            return true
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        return false
    end atStep
    """

    static let terminalScript = """
    on run argv
        repeat with i from 1 to 3
            set step to character i of "ABC"
            try
                if not atStep(step, item 1 of argv) then return "gone"
            on error number n
                return "failed " & step & " " & n
            end try
        end repeat
        return "ok"
    end run

    on atStep(step, wanted)
        tell application "Terminal"
            repeat with w in windows
                repeat with t in tabs of w
                    if (tty of t) is wanted then
                        if step is "A" then
                            if miniaturized of w then set miniaturized of w to false
                        else if step is "B" then
                            activate
                        else
                            set selected of t to true
                            set index of w to 1
                        end if
                        return true
                    end if
                end repeat
            end repeat
        end tell
        return false
    end atStep
    """

    // MARK: the exact call

    @Test func iTermIsAskedWithItsScriptAndTheDeviceAsASeparateArgument() async throws {
        let runner = FakeRunner { _ in FakeRunner.ok("ok\n") }
        let answer = try await opener(runner: runner).select(tty: "/dev/ttys004", terminal: .iterm2)
        #expect(answer == .selected)
        #expect(runner.calls.count == 1)
        #expect(runner.calls[0].argv == ["osascript", "-e", Self.iTermScript, "/dev/ttys004"])
        #expect(runner.calls[0].timeout == .seconds(120))
        #expect(runner.calls[0].environment.isEmpty)
        #expect(runner.calls[0].stdin == nil)
        #expect(ITermLauncher.selectScript == Self.iTermScript)
    }

    @Test func terminalIsAskedWithItsScriptAndTheDeviceAsASeparateArgument() async throws {
        let runner = FakeRunner { _ in FakeRunner.ok("ok\n") }
        let answer = try await opener(runner: runner).select(tty: "/dev/ttys012", terminal: .terminal)
        #expect(answer == .selected)
        #expect(runner.calls.map(\.argv) == [["osascript", "-e", Self.terminalScript, "/dev/ttys012"]])
        #expect(AppleTerminalLauncher.selectScript == Self.terminalScript)
    }

    /// A loop variable over `windows` is a reference by position ("item 2 of windows"), and both terminals list
    /// their windows front to back. So each step searches again, and a step that matches does its one thing
    /// and returns: no reference outlives a command that can move a window. In iTerm2, step A un-minimizes,
    /// B raises the window, C selects the tab and the session and activates iTerm2. In Terminal, A un-minimizes,
    /// B activates Terminal, C selects the tab and raises its window (activating last let Terminal put its
    /// previous front window back on top in CI).
    @Test func eachStepSearchesAgainAndDoesOneThing() {
        func branches(_ script: String) -> [String] {
            let lines = script.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            let start = lines.firstIndex { $0.hasPrefix("if (tty of") }!
            return Array(lines[(start + 1)...].prefix { $0 != "return true" })
        }
        #expect(branches(ITermLauncher.selectScript) == [
            "if step is \"A\" then", "if miniaturized of w then set miniaturized of w to false",
            "else if step is \"B\" then", "select w",
            "else", "select t", "select s", "activate",
            "end if",
        ])
        #expect(branches(AppleTerminalLauncher.selectScript) == [
            "if step is \"A\" then", "if miniaturized of w then set miniaturized of w to false",
            "else if step is \"B\" then", "activate",
            "else", "set selected of t to true", "set index of w to 1",
            "end if",
        ])
        for script in [ITermLauncher.selectScript, AppleTerminalLauncher.selectScript] {
            #expect(script.contains("repeat with i from 1 to 3\n        set step to character i of \"ABC\""))
            #expect(script.contains("return \"failed \" & step & \" \" & n"))
        }
    }

    /// Inside a `tell` block `contents` is the terminal's own property (iTerm2's session, Terminal's tab), which
    /// is what stopped the earlier iTerm2 script with error -1728 (issue #129). Neither script names an object by
    /// id either: CI has not run one.
    @Test func noWordThatMeansSomethingElseInsideTheTell() {
        for script in [ITermLauncher.selectScript, AppleTerminalLauncher.selectScript] {
            #expect(!script.contains("contents"))
            #expect(!script.contains(" id "))
        }
    }

    /// The device is never part of the script's text.
    @Test func theDeviceIsNeverInTheScript() {
        #expect(!ITermLauncher.selectScript.contains("/dev/"))
        #expect(!AppleTerminalLauncher.selectScript.contains("/dev/"))
    }

    /// A record whose terminal is unknown uses the rule a new tab uses: the setting, else iTerm2 when it is
    /// installed, else Terminal.
    @Test func anUnknownTerminalIsChosenAsANewTabsIs() async throws {
        let iTerm = FakeRunner { _ in FakeRunner.ok("ok") }
        _ = try await opener(installed: ["/Applications/iTerm.app"], runner: iTerm).select(tty: "/dev/ttys004", terminal: .unknown)
        #expect(iTerm.calls[0].argv[2] == Self.iTermScript)

        let terminal = FakeRunner { _ in FakeRunner.ok("ok") }
        _ = try await opener(installed: [], runner: terminal).select(tty: "/dev/ttys004", terminal: .unknown)
        #expect(terminal.calls[0].argv[2] == Self.terminalScript)

        let chosen = FakeRunner { _ in FakeRunner.ok("ok") }
        _ = try await opener(AppSettings(terminal: .appleTerminal), installed: ["/Applications/iTerm.app"], runner: chosen)
            .select(tty: "/dev/ttys004", terminal: .unknown)
        #expect(chosen.calls[0].argv[2] == Self.terminalScript)
    }

    /// The record names its own terminal, so the setting doesn't change which one is asked.
    @Test func aKnownTerminalIsAskedWhateverTheSetting() async throws {
        let runner = FakeRunner { _ in FakeRunner.ok("ok") }
        _ = try await opener(AppSettings(terminal: .appleTerminal), runner: runner).select(tty: "/dev/ttys004", terminal: .iterm2)
        #expect(runner.calls[0].argv[2] == Self.iTermScript)
    }

    // MARK: the answers

    @Test func goneMeansTheTerminalHasNoSuchTab() async throws {
        let runner = FakeRunner { _ in FakeRunner.ok("gone\n") }
        #expect(try await opener(runner: runner).select(tty: "/dev/ttys004", terminal: .iterm2) == .gone)
    }

    @Test func anyOtherAnswerIsAFailure() async throws {
        let runner = FakeRunner { _ in FakeRunner.ok("maybe\n") }
        await #expect(throws: LaunchError.failed("iTerm2 gave an answer MacMosh doesn't know.")) {
            try await opener(runner: runner).select(tty: "/dev/ttys004", terminal: .iterm2)
        }
    }

    /// A step that stopped (issue #129): `failed <step> <error number>`, the step A, B or C.
    @Test func aStepThatStoppedIsNamedWithItsErrorNumber() async throws {
        let iTerm = FakeRunner { _ in FakeRunner.ok("failed A -1728\n") }
        await #expect(throws: LaunchError.selectStopped(.iterm2, step: .a, error: -1728)) {
            try await opener(runner: iTerm).select(tty: "/dev/ttys004", terminal: .iterm2)
        }
        let terminal = FakeRunner { _ in FakeRunner.ok("failed B -1719") }
        await #expect(throws: LaunchError.selectStopped(.appleTerminal, step: .b, error: -1719)) {
            try await opener(runner: terminal).select(tty: "/dev/ttys004", terminal: .terminal)
        }
        let last = FakeRunner { _ in FakeRunner.ok("failed C -10006\n") }
        await #expect(throws: LaunchError.selectStopped(.iterm2, step: .c, error: -10006)) {
            try await opener(runner: last).select(tty: "/dev/ttys004", terminal: .iterm2)
        }
    }

    /// Each step runs inside its own `try`, so a refusal comes back as a step's answer, not as osascript's
    /// error: it is still a refusal, worded as before.
    @Test func aRefusalInsideAStepIsStillARefusal() async throws {
        for step in ["A", "B", "C"] {
            let runner = FakeRunner { _ in FakeRunner.ok("failed \(step) -1743\n") }
            await #expect(throws: LaunchError.automationDenied(.iterm2)) {
                try await opener(runner: runner).select(tty: "/dev/ttys004", terminal: .iterm2)
            }
        }
    }

    @Test(arguments: ["failed", "failed A", "failed D -1728", "failed a -1728", "failed A -17x28", "failed A -1728 more",
                      "failed  A -1728", "failedA -1728", "ok then", "OK", "Gone"])
    func aMisshapenAnswerIsAFailure(_ said: String) async throws {
        let runner = FakeRunner { _ in FakeRunner.ok(said + "\n") }
        await #expect(throws: LaunchError.failed("iTerm2 gave an answer MacMosh doesn't know.")) {
            try await opener(runner: runner).select(tty: "/dev/ttys004", terminal: .iterm2)
        }
    }

    /// The sentence for a stopped step: the app, what the step was doing, and the error number.
    @Test func aStoppedStepHasAPlainReason() {
        #expect(LaunchError.stoppedReason(.iterm2, step: .a, error: -1728)
                == "iTerm2 couldn't un-minimize the tab's window (error -1728).")
        #expect(LaunchError.stoppedReason(.appleTerminal, step: .b, error: -1719)
                == "Terminal couldn't bring the tab's window to the front (error -1719).")
        #expect(LaunchError.stoppedReason(.iterm2, step: .c, error: -10006)
                == "iTerm2 couldn't select the tab (error -10006).")
    }

    @Test func aRefusalIsNamedForTheTerminal() async throws {
        let runner = FakeRunner { _ in FakeRunner.failed(1, stderr: Self.denied) }
        await #expect(throws: LaunchError.automationDenied(.appleTerminal)) {
            try await opener(runner: runner).select(tty: "/dev/ttys004", terminal: .terminal)
        }
        // No command file: bringing a tab forward has no other way.
        #expect(runner.calls.count == 1)
    }

    @Test func otherFailuresSayWhat() async throws {
        let runner = FakeRunner { _ in FakeRunner.failed(1, stderr: "execution error: iTerm2 got an error. (-1728)\n") }
        await #expect(throws: LaunchError.failed("execution error: iTerm2 got an error. (-1728)")) {
            try await opener(runner: runner).select(tty: "/dev/ttys004", terminal: .iterm2)
        }
        let slow = FakeRunner { _ in CommandResult(exitCode: 15, stdout: "", stderr: "", timedOut: true) }
        await #expect(throws: LaunchError.failed("Terminal did not answer in time.")) {
            try await opener(runner: slow).select(tty: "/dev/ttys004", terminal: .terminal)
        }
    }

    // MARK: the device is checked first

    @Test(arguments: ["", "/dev/ttys", "/dev/tty004", "/dev/ttys00a", "/dev/ttys004 ", "/dev/ttys004\n",
                      "/dev/ttys004\"; do shell script \"x", "dev/ttys004", "/dev/ttys\u{0664}", "/dev/../ttys004"])
    func aDeviceThatIsNotATerminalIsGoneWithoutAsking(_ tty: String) async throws {
        let runner = FakeRunner { _ in FakeRunner.ok("ok") }
        #expect(try await opener(runner: runner).select(tty: tty, terminal: .iterm2) == .gone)
        #expect(runner.calls.isEmpty)
        #expect(!TabRecord.isTerminalDevice(tty))
    }

    @Test func aTerminalDeviceIsDevTtysAndDigits() {
        for good in ["/dev/ttys0", "/dev/ttys004", "/dev/ttys123"] {
            #expect(TabRecord.isTerminalDevice(good), "\(good)")
        }
    }
}
