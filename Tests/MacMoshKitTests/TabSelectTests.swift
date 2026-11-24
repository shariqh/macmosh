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

    /// The scripts of the design's section 8.4, word for word.
    static let iTermScript = """
    on run argv
        set wanted to item 1 of argv
        tell application "iTerm2"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if (tty of s) is wanted then
                            select w
                            select t
                            select s
                            activate
                            return "ok"
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        return "gone"
    end run
    """

    static let terminalScript = """
    on run argv
        set wanted to item 1 of argv
        tell application "Terminal"
            repeat with w in windows
                repeat with t in tabs of w
                    if (tty of t) is wanted then
                        if miniaturized of w then set miniaturized of w to false
                        set selected of t to true
                        set index of w to 1
                        activate
                        return "ok"
                    end if
                end repeat
            end repeat
        end tell
        return "gone"
    end run
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
