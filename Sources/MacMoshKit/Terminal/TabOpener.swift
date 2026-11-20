import Foundation

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
        if let chosen = settings.terminal { return chosen }
        return fileExists(Self.iTermPath) ? .iterm2 : .appleTerminal
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
}
