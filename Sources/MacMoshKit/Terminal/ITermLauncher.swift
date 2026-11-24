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

    /// Brings forward the tab whose session's terminal device is the script's one argument (menu design 8.4).
    /// The device is an argument, never part of the script's text. The answer is one line: `ok`; `gone` when no
    /// session has that device; or `failed <step> <error number>` when a step stopped (`TabOpener.select`).
    ///
    /// Three steps, each a fresh search by the device: A un-minimizes the session's window, B brings that
    /// window to the front, C selects the tab and the session and activates iTerm2. A loop variable is a
    /// reference by position (`item 2 of windows`), and iTerm2 lists its windows front to back, so after a
    /// command that can move a window, a step returns at once and never uses its references again. Step C
    /// uses `s` after `select t`: step B has already put that window in front, so it stays `item 1 of windows`.
    ///
    /// Inside `tell application "iTerm2"` no word may be read as AppleScript's own: `contents` is iTerm2's
    /// session property, "The currently visible contents of the session.", and the script that used `contents
    /// of w` stopped with error -1728 on a real iTerm2 (issue #129). Every term here is in iTerm2's installed
    /// dictionary (`sdef`, 3.7.7): `tty` of a session; `miniaturized` of a window, "Whether the window is
    /// currently minimized."; `select`, "Make receiver visible and selected.", for a window, a tab and a session.
    /// CI's "Terminal scripts" job runs this text against a real iTerm2 (scripts/ci/try-select.sh).
    static let selectScript = """
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

    /// `title` isn't used: the command sets the tab's name itself.
    public func openTab(_ command: TabCommand, title: String) async throws {
        try await AppleScriptRunner.run(Self.script, command: command, app: .iterm2, runner: runner)
    }
}
