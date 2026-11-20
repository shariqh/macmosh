import Foundation

/// Apple's Terminal through AppleScript. `do script` opens a new window, and Terminal has no
/// scripted way to open a tab, so a desk gets a window here (sitting 1, item 2).
public struct AppleTerminalLauncher: TerminalLauncher {
    private let runner: CommandRunner
    public init(runner: CommandRunner) { self.runner = runner }

    static let script = """
    on run argv
        tell application "Terminal"
            activate
            do script (item 1 of argv)
        end tell
    end run
    """

    /// `title` isn't used: Terminal has no scripted title for the window.
    public func openTab(_ command: TabCommand, title: String) async throws {
        try await AppleScriptRunner.run(Self.script, command: command, app: .appleTerminal, runner: runner)
    }
}
