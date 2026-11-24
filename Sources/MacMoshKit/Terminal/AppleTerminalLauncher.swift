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

    /// Brings forward the tab whose terminal device is the script's one argument, un-minimizing its window,
    /// and answers `ok`, or `gone` when no tab has it (menu design 8.4). The device is an argument,
    /// never part of the script's text.
    ///
    /// This script has never run on a real Mac: it is tried on the daily Mac before the rollout, with several
    /// windows and the wanted one not in front, a minimized window, a window on another Space, and no new
    /// permission prompt (design 11.1). Every term in it is in Terminal's dictionary, as the design quotes it (section 4.3): a tab's `tty`,
    /// "The tab's TTY device.", and `selected`, "Whether the tab is selected."; a window's `index`, "The
    /// index of the window, ordered front to back.", and `miniaturized`, "Whether the window is currently
    /// minimized." What setting them does with several windows or a window on another Space is not documented.
    ///
    /// It differs from design 8.4 after review. A loop variable is a reference by position (the AppleScript
    /// Language Guide, "repeat with loopVariable (in list)": it "takes on the value of item 1 of list, item 2
    /// of list, item 3 of list, and so on"), and Terminal lists its windows front to back (`<element
    /// type="window">` with `<cocoa key="orderedWindows"/>`). Un-minimizing a window can move it, and then
    /// `w` and `t` name another window. So the script selects the tab first, before anything moves, and then
    /// names the window by its `id`, "The unique identifier of the window." (installed dictionary, 2.15).
    static let selectScript = """
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

    /// `title` isn't used: Terminal has no scripted title for the window.
    public func openTab(_ command: TabCommand, title: String) async throws {
        try await AppleScriptRunner.run(Self.script, command: command, app: .appleTerminal, runner: runner)
    }
}
