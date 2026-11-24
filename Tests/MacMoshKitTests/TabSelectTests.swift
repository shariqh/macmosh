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

    /// The scripts of the design's section 8.4, changed after review so that nothing acts on a loop's
    /// positional reference once a window may have moved (see `aMatchIsHeldByAReferenceThatDoesNotMove`).
    static let iTermScript = """
    on run argv
        set wanted to item 1 of argv
        tell application "iTerm2"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if (tty of s) is wanted then
                            set theWindow to contents of w
                            set theTab to contents of t
                            set theSession to contents of s
                            select theTab
                            select theSession
                            if miniaturized of theWindow then set miniaturized of theWindow to false
                            select theWindow
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
                        set theWindowID to id of w
                        set selected of t to true
                        if miniaturized of window id theWindowID then set miniaturized of window id theWindowID to false
                        set index of window id theWindowID to 1
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

    /// A loop variable over `windows` is a reference by position ("item 2 of windows"), looked up again each
    /// time it is used, and both terminals list their windows front to back. Once a window is raised or
    /// un-minimized the positions move, so after a match no select or set may go through `w`, `t` or `s`
    /// except before anything has moved: iTerm2 takes the app's own references first (`contents of`), and
    /// Terminal selects the tab first and then names the window by its id.
    @Test func aMatchIsHeldByAReferenceThatDoesNotMove() {
        func afterMatch(_ script: String) -> [String] {
            let lines = script.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            let start = lines.firstIndex { $0.hasPrefix("if (tty of") }!
            return Array(lines[(start + 1)...].prefix { $0 != "return \"ok\"" })
        }
        func words(_ line: String) -> Set<String> { Set(line.split(separator: " ").map(String.init)) }
        let iTerm = afterMatch(ITermLauncher.selectScript)
        #expect(Array(iTerm.prefix(3)) == ["set theWindow to contents of w", "set theTab to contents of t",
                                           "set theSession to contents of s"])
        for line in iTerm.dropFirst(3) {
            #expect(words(line).isDisjoint(with: ["w", "t", "s"]), "\(line)")
        }
        let terminal = afterMatch(AppleTerminalLauncher.selectScript)
        #expect(Array(terminal.prefix(2)) == ["set theWindowID to id of w", "set selected of t to true"])
        for line in terminal.dropFirst(2) {
            #expect(words(line).isDisjoint(with: ["w", "t"]), "\(line)")
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
