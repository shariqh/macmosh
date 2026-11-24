import Foundation

/// What a terminal said when asked to bring a tab forward.
public enum TabSelection: Sendable, Equatable {
    /// The tab is in front.
    case selected
    /// No tab of that terminal has the device.
    case gone
}

/// Opens a tab in the user's terminal app, falling back to a `.command` file when macOS has not
/// let MacMosh control the app.
public struct TabOpener: Sendable {
    private let runner: CommandRunner
    private let settings: AppSettings
    private let temporaryFolder: URL
    private let fileExists: @Sendable (String) -> Bool

    static let iTermPath = "/Applications/iTerm.app"

    public init(runner: CommandRunner, settings: AppSettings, temporaryFolder: URL,
                fileExists: @escaping @Sendable (String) -> Bool) {
        self.runner = runner
        self.settings = settings
        self.temporaryFolder = temporaryFolder
        self.fileExists = fileExists
    }

    /// The setting if there is one; otherwise iTerm2 when it is installed; otherwise Terminal.
    public func terminal() -> TerminalApp {
        Self.terminal(settings: settings, fileExists: fileExists)
    }

    /// The same rule, for a caller with no opener: where a new tab opens.
    public static func terminal(settings: AppSettings, fileExists: (String) -> Bool) -> TerminalApp {
        if let chosen = settings.terminal { return chosen }
        return fileExists(iTermPath) ? .iterm2 : .appleTerminal
    }

    /// Opens the tab. Returns a sentence for the user when it had to fall back, and nil otherwise.
    public func open(_ command: TabCommand, title: String) async throws -> String? {
        let app = terminal()
        let scripted: TerminalLauncher = app == .iterm2 ? ITermLauncher(runner: runner)
                                                        : AppleTerminalLauncher(runner: runner)
        do {
            try await scripted.openTab(command, title: title)
            return nil
        } catch LaunchError.automationDenied(let refused) {
            try await CommandFileLauncher(runner: runner, app: app, folder: temporaryFolder)
                .openTab(command, title: title)
            return "macOS hasn't let MacMosh control \(refused.displayName), so the tab was opened another way. "
                + "To allow it: System Settings > Privacy & Security > Automation."
        }
    }

    /// Brings forward the tab whose terminal device is `tty`, in the terminal the tab's record names; for
    /// `unknown`, the one `terminal()` picks for a new tab (menu design 8.4). It runs from this process, as
    /// opening a tab does, because the app is what holds the Automation permission. A device that isn't
    /// `/dev/ttys` and digits is `gone` without asking. A refusal throws `automationDenied`, with no other
    /// way to try: a command file can open a tab but can't bring one forward.
    public func select(tty: String, terminal recorded: TabRecord.Terminal) async throws -> TabSelection {
        guard TabRecord.isTerminalDevice(tty) else { return .gone }
        let app: TerminalApp
        switch recorded {
        case .iterm2: app = .iterm2
        case .terminal: app = .appleTerminal
        case .unknown: app = terminal()
        }
        let script = app == .iterm2 ? ITermLauncher.selectScript : AppleTerminalLauncher.selectScript
        let answer = try await AppleScriptRunner.run(script, argument: tty, app: app, runner: runner)
        switch answer.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "ok": return .selected
        case "gone": return .gone
        default: throw LaunchError.failed("\(app.displayName) gave an answer MacMosh doesn't know.")
        }
    }
}
