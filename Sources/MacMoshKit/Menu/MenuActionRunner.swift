import Foundation

/// Opens a terminal tab. `TabOpener` is the real one; tests use a stand-in that opens nothing.
public protocol TabOpening: Sendable {
    func open(_ command: TabCommand, title: String) async throws -> String?
}

extension TabOpener: TabOpening {}

/// Does what a menu item asks: open a tab that runs the bundled `macmosh`, or run it in the background.
public struct MenuActionRunner: Sendable {
    private let macmoshPath: String
    private let tabs: TabOpening
    private let runner: CommandRunner

    /// How long a background command may run before it is stopped.
    static let runLimit: Duration = .seconds(30)

    /// The sentence shown when the app's own path can't go into a terminal tab.
    static let moveIt = "MacMosh can't open terminal tabs from where it is now. "
        + "Move it to the Applications folder and open it again."

    /// `macmoshPath` is the command inside the app bundle, `Contents/Helpers/macmosh`.
    public init(macmoshPath: String, tabs: TabOpening, runner: CommandRunner) {
        self.macmoshPath = macmoshPath
        self.tabs = tabs
        self.runner = runner
    }

    /// Does what a menu item asks. Returns a sentence to show the user when there is one
    /// (a fallback notice from the tab opener, or why the action could not run).
    public func perform(_ action: MenuAction, title: String) async -> String? {
        switch action {
        case .none, .refresh:
            // The refresh that follows every action does the checking.
            return nil
        case .tab(let arguments):
            return await openTab(arguments)
        case .run(let arguments):
            return await runInBackground(arguments)
        }
    }

    /// The desk for `connect <id> <desk>`, otherwise the subcommand, so a tab is named for what it does.
    public static func tabTitle(for arguments: [String]) -> String {
        if arguments.first == "connect", arguments.count >= 3 { return arguments[2] }
        return arguments.first ?? "macmosh"
    }

    private func openTab(_ arguments: [String]) async -> String? {
        let command: TabCommand
        do {
            command = try TabCommand(macmoshPath: macmoshPath, arguments: arguments)
        } catch {
            // The only thing it refuses is a path or word with a character a tab can't carry. The
            // menu's own words are plain, so in practice it is the path of the app.
            return Self.moveIt
        }
        do {
            return try await tabs.open(command, title: Self.tabTitle(for: arguments))
        } catch LaunchError.automationDenied(let app) {
            return "macOS hasn't let MacMosh control \(app.displayName). "
                + "To allow it: System Settings > Privacy & Security > Automation."
        } catch LaunchError.failed(let reason) {
            return "The tab didn't open. \(reason)"
        } catch {
            return "The tab didn't open."
        }
    }

    private func runInBackground(_ arguments: [String]) async -> String? {
        let result = await runner.run(macmoshPath, arguments, environment: [:], stdin: nil, timeout: Self.runLimit)
        if result.exitCode == 0 { return nil }
        let lastLine = result.stderr
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { !$0.isEmpty }
        return lastLine ?? "That didn't work (exit code \(result.exitCode))."
    }
}
