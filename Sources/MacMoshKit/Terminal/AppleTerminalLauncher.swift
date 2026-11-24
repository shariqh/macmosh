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

    /// Brings forward the tab whose terminal device is the script's one argument, un-minimizing its window
    /// first, and answers `ok`, or `gone` when no tab has it (menu design 8.4). The device is an argument,
    /// never part of the script's text.
    ///
    /// This script has never run on a real Mac: it is tried on the daily Mac before the rollout, with several
    /// windows, a minimized window, a window on another Space, and no new permission prompt (design 11.1).
    /// Every term in it is in Terminal's dictionary, as the design quotes it (section 4.3): a tab's `tty`,
    /// "The tab's TTY device.", and `selected`, "Whether the tab is selected."; a window's `index`, "The
    /// index of the window, ordered front to back.", and `miniaturized`, "Whether the window is currently
    /// minimized." What setting them does with several windows or a window on another Space is not documented.
    static let selectScript = """
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

    /// `title` isn't used: Terminal has no scripted title for the window.
    public func openTab(_ command: TabCommand, title: String) async throws {
        try await AppleScriptRunner.run(Self.script, command: command, app: .appleTerminal, runner: runner)
    }
}
