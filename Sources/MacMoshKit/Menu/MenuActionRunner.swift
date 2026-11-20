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
        await outcome(of: action, title: title).notice
    }

    /// Does what a menu item asks, and says what it came to: the sentence for the menu, and a few
    /// fixed words for the log.
    public func outcome(of action: MenuAction, title: String) async -> ActionOutcome {
        switch action {
        case .none, .refresh:
            // The refresh that follows every action does the checking.
            return ActionOutcome(summary: "nothing to run", notice: nil)
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

    private func openTab(_ arguments: [String]) async -> ActionOutcome {
        let command: TabCommand
        do {
            command = try TabCommand(macmoshPath: macmoshPath, arguments: arguments)
        } catch {
            // The only thing it refuses is a path or word with a character a tab can't carry. The
            // menu's own words are plain, so in practice it is the path of the app.
            return ActionOutcome(summary: "the app's path can't go in a tab", notice: Self.moveIt)
        }
        do {
            let notice = try await tabs.open(command, title: Self.tabTitle(for: arguments))
            return ActionOutcome(summary: notice == nil ? "tab opened" : "tab opened another way", notice: notice)
        } catch LaunchError.automationDenied(let app) {
            return ActionOutcome(
                summary: "not allowed to control the terminal app",
                notice: "macOS hasn't let MacMosh control \(app.displayName). "
                    + "To allow it: System Settings > Privacy & Security > Automation.")
        } catch LaunchError.failed(let reason) {
            return ActionOutcome(summary: MenuLog.tabFailure(reason), notice: "The tab didn't open. \(reason)")
        } catch {
            return ActionOutcome(summary: MenuLog.tabFailure(""), notice: "The tab didn't open.")
        }
    }

    private func runInBackground(_ arguments: [String]) async -> ActionOutcome {
        let result = await runner.run(macmoshPath, arguments, environment: [:], stdin: nil, timeout: Self.runLimit)
        if result.exitCode == 0 { return ActionOutcome(summary: "ran", notice: nil) }
        let lastLine = result.stderr
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { !$0.isEmpty }
        return ActionOutcome(summary: "run failed (exit code \(result.exitCode))",
                             notice: lastLine ?? "That didn't work (exit code \(result.exitCode)).")
    }
}

/// What a menu action came to.
public struct ActionOutcome: Sendable, Equatable {
    /// A few fixed words for the log (`MenuLog`), with no name or address in them.
    public var summary: String
    /// The sentence the menu shows as its first line, when there is one.
    public var notice: String?

    public init(summary: String, notice: String?) {
        self.summary = summary
        self.notice = notice
    }
}
