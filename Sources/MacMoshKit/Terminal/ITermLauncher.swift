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
    /// windows and the wanted one not in front, a minimized window, a window on another Space, and no new
    /// permission prompt (design 11.1).
    ///
    /// It differs from design 8.4 after review. A loop variable is a reference by position: the AppleScript
    /// Language Guide ("repeat with loopVariable (in list)") says it "takes on the value of item 1 of list,
    /// item 2 of list, item 3 of list, and so on", and "To access the actual value of an item in the list,
    /// rather than a reference to the item, use the contents of property". iTerm2 lists its windows front
    /// to back (`<element type="window">` with `<cocoa key="orderedScriptingWindows"/>`), so once a window
    /// is raised, `item 2 of windows` is another window. The script therefore takes `contents of` each
    /// match before any select, selects the tab and session before the window, and un-minimizes the window
    /// (`miniaturized`, "Whether the window is currently minimized.", which is writable).
    ///
    /// Its terms are in iTerm2's installed dictionary (`sdef`, 3.7.7): window, tab and session respond to
    /// `select`, the command "Make receiver visible and selected."; a session has `tty`; a window has
    /// `miniaturized`. The dictionary describes no further what each `select` does. iTerm2's page "Scripting
    /// with AppleScript" (design source [10]) says a window's `select` "Gives the window keyboard focus and
    /// brings it to the front.", a tab's "Selects the tab, making it the current tab for the window.", and a
    /// session's `tty` is "The name of the session's tty (e.g., /dev/ttys01). Returns a string." What
    /// selecting does with a window on another Space is not documented.
    static let selectScript = """
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

    /// `title` isn't used: the command sets the tab's name itself.
    public func openTab(_ command: TabCommand, title: String) async throws {
        try await AppleScriptRunner.run(Self.script, command: command, app: .iterm2, runner: runner)
    }
}
