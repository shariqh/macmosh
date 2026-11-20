import Foundation

/// iTerm2 through AppleScript: a tab in the current window, or a window when there is none.
/// This is the script that worked in sitting 1.
public struct ITermLauncher: TerminalLauncher {
    private let runner: CommandRunner
    public init(runner: CommandRunner) { self.runner = runner }

    static let script = """
    on run argv
        tell application "iTerm2"
            activate
            if (count of windows) is 0 then
                create window with default profile command (item 1 of argv)
            else
                tell current window
                    create tab with default profile command (item 1 of argv)
                end tell
            end if
        end tell
    end run
    """

    /// `title` isn't used: the command sets the tab's name itself.
    public func openTab(_ command: TabCommand, title: String) async throws {
        try await AppleScriptRunner.run(Self.script, command: command, app: .iterm2, runner: runner)
    }
}
