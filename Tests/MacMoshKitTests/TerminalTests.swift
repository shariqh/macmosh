import Foundation
import Testing
@testable import MacMoshKit

@Suite struct TerminalTests {
    private static let denied = "execution error: Not authorized to send Apple events to Terminal. (-1743)"

    private func command(_ arguments: [String] = ["connect", "mbp", "website"]) throws -> TabCommand {
        try TabCommand(macmoshPath: "/usr/local/bin/macmosh", arguments: arguments)
    }

    private func scratchFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("macmosh-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    // MARK: what a tab may run

    @Test(arguments: [["connect", "mbp", "a b"], ["x;y"], ["$(id)"], [""], ["a'b"], ["a\nb"]])
    func unsafeArgumentsAreRefused(_ arguments: [String]) {
        #expect(throws: TabCommandError.self) { try TabCommand(macmoshPath: "/usr/local/bin/macmosh", arguments: arguments) }
    }

    @Test func safeArgumentsAreAccepted() throws {
        for argument in ["pair", "alex@workhorse.example.ts.net", "192.168.1.20", "my_desk-2"] {
            let c = try TabCommand(macmoshPath: "/usr/local/bin/macmosh", arguments: [argument])
            #expect(c.argv == ["/usr/local/bin/macmosh", argument])
        }
        #expect(try command().line == "/usr/local/bin/macmosh connect mbp website")
    }

    @Test func theProgramsOwnPathIsCheckedToo() {
        #expect(throws: TabCommandError.self) { try TabCommand(macmoshPath: "/Users/a b/macmosh", arguments: []) }
        #expect(throws: TabCommandError.self) { try TabCommand(macmoshPath: "", arguments: ["pair"]) }
    }

    @Test func nonASCIILookalikesAndTrailingNewlinesAreRefused() {
        for bad in ["caf\u{E9}", "a\n", "\u{FF21}", "a\u{0}b", "a\tb", "~", "a*b", "a\\b", "a\"b", "a&b", "a|b", "a`b"] {
            #expect(throws: TabCommandError.self) { try TabCommand(macmoshPath: "/usr/local/bin/macmosh", arguments: [bad]) }
        }
    }

    // MARK: the AppleScript launchers

    @Test func theCommandIsAnArgumentNeverPartOfTheScript() async throws {
        let runner = FakeRunner { _ in FakeRunner.ok() }
        let command = try TabCommand(macmoshPath: "/usr/local/bin/macmosh", arguments: ["connect", "mbp", "website"])
        try await ITermLauncher(runner: runner).openTab(command, title: "website")
        let argv = runner.calls[0].argv
        #expect(argv[0] == "osascript" && argv[1] == "-e")
        #expect(argv.last == "/usr/local/bin/macmosh connect mbp website")
        #expect(!argv[2].contains("macmosh connect"))
    }

    @Test func theITermScriptIsTheOneThatWorkedInSittingOne() async throws {
        let runner = FakeRunner { _ in FakeRunner.ok() }
        try await ITermLauncher(runner: runner).openTab(try command(), title: "website")
        let script = runner.calls[0].argv[2]
        #expect(script.contains("on run argv"))
        #expect(script.contains("tell application \"iTerm2\""))
        #expect(script.contains("activate"))
        #expect(script.contains("create window with default profile command (item 1 of argv)"))
        #expect(script.contains("create tab with default profile command (item 1 of argv)"))
        #expect(script.contains("count of windows"))
        #expect(runner.calls[0].argv.count == 4)
    }

    @Test func theTerminalScriptIsDoScriptWithTheCommandAsAnArgument() async throws {
        let runner = FakeRunner { _ in FakeRunner.ok() }
        try await AppleTerminalLauncher(runner: runner).openTab(try command(), title: "website")
        let argv = runner.calls[0].argv
        #expect(argv[0] == "osascript" && argv[1] == "-e")
        #expect(argv[2].contains("do script (item 1 of argv)"))
        #expect(argv[2].contains("tell application \"Terminal\""))
        #expect(!argv[2].contains(" in "))
        #expect(!argv[2].contains("new tab"))
        #expect(argv.last == "/usr/local/bin/macmosh connect mbp website")
        #expect(!argv[2].contains("macmosh connect"))
    }

    @Test func aDeniedAutomationIsNamedForTheAppThatWasRefused() async throws {
        let byNumber = FakeRunner { _ in FakeRunner.failed(1, stderr: "x (-1743)") }
        await #expect(throws: LaunchError.automationDenied(.iterm2)) {
            try await ITermLauncher(runner: byNumber).openTab(try command(), title: "t")
        }
        let byWords = FakeRunner { _ in FakeRunner.failed(1, stderr: "Not authorized to send Apple events to Terminal.") }
        await #expect(throws: LaunchError.automationDenied(.appleTerminal)) {
            try await AppleTerminalLauncher(runner: byWords).openTab(try command(), title: "t")
        }
    }

    @Test func otherFailuresAreNotHidden() async throws {
        let runner = FakeRunner { _ in FakeRunner.failed(1, stderr: "execution error: iTerm2 got an error: oops (-1728)\n") }
        await #expect(throws: LaunchError.failed("execution error: iTerm2 got an error: oops (-1728)")) {
            try await ITermLauncher(runner: runner).openTab(try command(), title: "t")
        }
        let silent = FakeRunner { _ in FakeRunner.failed(7) }
        await #expect(throws: LaunchError.self) {
            try await AppleTerminalLauncher(runner: silent).openTab(try command(), title: "t")
        }
        let slow = FakeRunner { _ in CommandResult(exitCode: 15, stdout: "", stderr: "", timedOut: true) }
        await #expect(throws: LaunchError.self) {
            try await ITermLauncher(runner: slow).openTab(try command(), title: "t")
        }
    }

    // MARK: the command file

    @Test func theCommandFileIsPrivateAndExecsTheLine() async throws {
        let folder = try scratchFolder()
        let runner = FakeRunner { _ in FakeRunner.ok() }
        try await CommandFileLauncher(runner: runner, app: .iterm2, folder: folder)
            .openTab(try command(), title: "website")
        let call = runner.calls[0].argv
        #expect(call.prefix(3) == ["open", "-a", "iTerm"])
        let path = try #require(call.last)
        let file = URL(fileURLWithPath: path)
        #expect(file.deletingLastPathComponent().standardizedFileURL.path == folder.standardizedFileURL.path)
        #expect(file.lastPathComponent.range(of: #"^MacMosh-[0-9a-f]{8}\.command$"#, options: .regularExpression) != nil)
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
        #expect(try String(contentsOf: file, encoding: .utf8)
                == "#!/bin/sh\nexec /usr/local/bin/macmosh connect mbp website\n")
    }

    @Test func theFileLauncherUsesTheNameOfTheChosenApp() async throws {
        let folder = try scratchFolder()
        let runner = FakeRunner { _ in FakeRunner.ok() }
        try await CommandFileLauncher(runner: runner, app: .appleTerminal, folder: folder)
            .openTab(try command(), title: "website")
        #expect(runner.calls[0].argv.prefix(3) == ["open", "-a", "Terminal"])
    }

    @Test func eachOpeningGetsItsOwnFile() async throws {
        let folder = try scratchFolder()
        let runner = FakeRunner { _ in FakeRunner.ok() }
        let launcher = CommandFileLauncher(runner: runner, app: .iterm2, folder: folder)
        try await launcher.openTab(try command(), title: "a")
        try await launcher.openTab(try command(), title: "b")
        #expect(runner.calls[0].argv.last != runner.calls[1].argv.last)
    }

    @Test func oldCommandFilesAreCleared() async throws {
        let folder = try scratchFolder()
        let fm = FileManager.default
        let old = folder.appendingPathComponent("MacMosh-0123abcd.command")
        let recent = folder.appendingPathComponent("MacMosh-4567ef01.command")
        let foreign = folder.appendingPathComponent("notes.command")
        let foreignOld = folder.appendingPathComponent("MacMosh-notes.txt")
        for url in [old, recent, foreign, foreignOld] { try Data("x".utf8).write(to: url) }
        let twoDaysAgo = Date().addingTimeInterval(-2 * 86_400)
        for url in [old, foreign, foreignOld] { try fm.setAttributes([.modificationDate: twoDaysAgo], ofItemAtPath: url.path) }

        let runner = FakeRunner { _ in FakeRunner.ok() }
        try await CommandFileLauncher(runner: runner, app: .iterm2, folder: folder).openTab(try command(), title: "t")

        #expect(!fm.fileExists(atPath: old.path))
        #expect(fm.fileExists(atPath: recent.path))
        #expect(fm.fileExists(atPath: foreign.path))
        #expect(fm.fileExists(atPath: foreignOld.path))
    }

    @Test func aFailureToOpenTheFileIsReported() async throws {
        let folder = try scratchFolder()
        let runner = FakeRunner { _ in FakeRunner.failed(1, stderr: "The application cannot be found") }
        await #expect(throws: LaunchError.failed("The application cannot be found")) {
            try await CommandFileLauncher(runner: runner, app: .iterm2, folder: folder).openTab(try command(), title: "t")
        }
    }

    // MARK: choosing the terminal

    private func opener(_ settings: AppSettings = AppSettings(), installed: Set<String> = [],
                        runner: FakeRunner = FakeRunner { _ in FakeRunner.ok() },
                        folder: URL? = nil) throws -> TabOpener {
        TabOpener(runner: runner, settings: settings, temporaryFolder: try folder ?? scratchFolder(),
                  fileExists: { installed.contains($0) })
    }

    @Test func iTermIsPreferredWhenInstalled() throws {
        #expect(try opener(installed: ["/Applications/iTerm.app"]).terminal() == .iterm2)
        #expect(try opener(installed: []).terminal() == .appleTerminal)
    }

    @Test func theSettingOverridesDetection() throws {
        #expect(try opener(AppSettings(terminal: .appleTerminal), installed: ["/Applications/iTerm.app"]).terminal() == .appleTerminal)
        #expect(try opener(AppSettings(terminal: .iterm2), installed: []).terminal() == .iterm2)
    }

    /// The same rule as a function the menu's refresher asks, to know where a new tab opens.
    @Test func theTerminalRuleIsAFunctionOfTheSettingAndWhatIsInstalled() {
        let iTerm: @Sendable (String) -> Bool = { $0 == "/Applications/iTerm.app" }
        #expect(TabOpener.terminal(settings: AppSettings(), fileExists: iTerm) == .iterm2)
        #expect(TabOpener.terminal(settings: AppSettings(), fileExists: { _ in false }) == .appleTerminal)
        #expect(TabOpener.terminal(settings: AppSettings(terminal: .appleTerminal), fileExists: iTerm) == .appleTerminal)
    }

    @Test func openingUsesTheChosenTerminalsScript() async throws {
        let runner = FakeRunner { _ in FakeRunner.ok() }
        let said = try await opener(AppSettings(terminal: .appleTerminal), runner: runner).open(try command(), title: "website")
        #expect(said == nil)
        #expect(runner.calls.count == 1)
        #expect(runner.calls[0].argv[2].contains("Terminal"))
    }

    @Test func deniedAutomationFallsBackToACommandFile() async throws {
        let folder = try scratchFolder()
        let runner = FakeRunner { argv in
            argv[0] == "osascript" ? FakeRunner.failed(1, stderr: Self.denied) : FakeRunner.ok()
        }
        let said = try await opener(AppSettings(terminal: .appleTerminal), runner: runner, folder: folder)
            .open(try command(), title: "website")
        #expect(runner.calls.count == 2)
        #expect(runner.calls[0].argv[0] == "osascript")
        #expect(runner.calls[1].argv.prefix(3) == ["open", "-a", "Terminal"])
        let sentence = try #require(said)
        #expect(sentence == "macOS hasn't let MacMosh control Terminal, so the tab was opened another way. "
                + "To allow it: System Settings > Privacy & Security > Automation.")
    }

    @Test func theFallbackNamesITermWhenThatWasRefused() async throws {
        let runner = FakeRunner { argv in
            argv[0] == "osascript" ? FakeRunner.failed(1, stderr: "x (-1743)") : FakeRunner.ok()
        }
        let said = try await opener(AppSettings(terminal: .iterm2), runner: runner).open(try command(), title: "t")
        #expect(runner.calls[1].argv.prefix(3) == ["open", "-a", "iTerm"])
        #expect(said?.contains("control iTerm2,") == true)
    }

    @Test func otherFailuresDoNotFallBack() async throws {
        let runner = FakeRunner { _ in FakeRunner.failed(1, stderr: "syntax error") }
        await #expect(throws: LaunchError.failed("syntax error")) {
            try await opener(AppSettings(terminal: .iterm2), runner: runner).open(try command(), title: "t")
        }
        #expect(runner.calls.count == 1)
    }

    @Test func aFailingFallbackIsReportedNotHidden() async throws {
        let runner = FakeRunner { argv in
            argv[0] == "osascript" ? FakeRunner.failed(1, stderr: Self.denied) : FakeRunner.failed(1, stderr: "open failed")
        }
        await #expect(throws: LaunchError.failed("open failed")) {
            try await opener(AppSettings(terminal: .appleTerminal), runner: runner).open(try command(), title: "t")
        }
        #expect(runner.calls.count == 2)
    }

    @Test func onlyOurOwnFileNamesAreRecognised() {
        #expect(CommandFileLauncher.isOurs("MacMosh-0123abcd.command"))
        for other in ["MacMosh-0123abcd.command.backup", "MacMosh-0123abcG.command", "MacMosh-0123ABCD.command",
                      "MacMosh-0123abc.command", "MacMosh-0123abcde.command", "macmosh-0123abcd.command",
                      "MacMosh-\u{0661}\u{0662}\u{0663}\u{0664}\u{0665}\u{0666}\u{0667}\u{0668}.command"] {
            #expect(!CommandFileLauncher.isOurs(other), "\(other)")
        }
    }
}
