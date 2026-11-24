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

    /// Brings forward the tab whose session's terminal device is the script's one argument, and answers
    /// `ok`, or `gone` when no session has it (menu design 8.4). The device is an argument, never part of
    /// the script's text.
    ///
    /// This script has never run on a real Mac: it is tried on the daily Mac before the rollout, with several
    /// windows, a minimized window, a window on another Space, and no new permission prompt (design 11.1).
    /// Every term in it is in iTerm2's dictionary, as the design quotes it (section 4.3): a window's `select`,
    /// "Gives the window keyboard focus and brings it to the front."; a tab's `select`, "Selects the tab,
    /// making it the current tab for the window."; the `select` command, "Make receiver visible and
    /// selected."; and a session's `tty`, "The name of the session's tty (e.g., /dev/ttys01). Returns a
    /// string." What selecting does with a minimized window or one on another Space is not documented.
    static let selectScript = """
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

    /// `title` isn't used: the command sets the tab's name itself.
    public func openTab(_ command: TabCommand, title: String) async throws {
        try await AppleScriptRunner.run(Self.script, command: command, app: .iterm2, runner: runner)
    }
}
