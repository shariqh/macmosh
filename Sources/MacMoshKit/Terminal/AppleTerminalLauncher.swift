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

    /// Brings forward the tab whose terminal device is the script's one argument (menu design 8.4). The device
    /// is an argument, never part of the script's text. The answer is one line: `ok`; `gone` when no tab has
    /// that device; or `failed <step> <error number>` when a step stopped (`TabOpener.select`).
    ///
    /// Three steps, each a fresh search by the device, as iTerm2's script does: A un-minimizes the tab's window,
    /// B brings that window to the front, C selects the tab and activates Terminal. Terminal lists its windows
    /// front to back, so after a command that can move a window a step returns at once.
    ///
    /// Every term is in Terminal's installed dictionary (`sdef`, 2.15): a tab's `tty`, "The tab's TTY device.",
    /// and `selected`, "Whether the tab is selected."; a window's `miniaturized`, "Whether the window is
    /// currently minimized.", and `index`, "The index of the window, ordered front to back.". A tab also has a
    /// property `contents`, so the script never says `contents of`. CI's "Terminal scripts" job runs this text
    /// against a real Terminal (scripts/ci/try-select.sh).
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
        tell application "Terminal"
            repeat with w in windows
                repeat with t in tabs of w
                    if (tty of t) is wanted then
                        if step is "A" then
                            if miniaturized of w then set miniaturized of w to false
                        else if step is "B" then
                            set index of w to 1
                        else
                            set selected of t to true
                            activate
                        end if
                        return true
                    end if
                end repeat
            end repeat
        end tell
        return false
    end atStep
    """

    /// `title` isn't used: Terminal has no scripted title for the window.
    public func openTab(_ command: TabCommand, title: String) async throws {
        try await AppleScriptRunner.run(Self.script, command: command, app: .appleTerminal, runner: runner)
    }
}
