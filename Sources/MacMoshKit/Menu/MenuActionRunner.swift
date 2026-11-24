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
    private let pause: @Sendable (Duration) async -> Void

    /// How long a background command may run before it is stopped.
    static let runLimit: Duration = .seconds(30)

    /// The wait between two tabs of one `.tabs` action, so the terminal is not flooded.
    static let tabsPause: Duration = .milliseconds(400)

    /// The sentence shown when the app's own path can't go into a terminal tab.
    static let moveIt = "MacMosh can't open terminal tabs from where it is now. "
        + "Move it to the Applications folder and open it again."

    /// `macmoshPath` is the command inside the app bundle, `Contents/Helpers/macmosh`. `pause` is how the
    /// wait between tabs is done; tests pass one that doesn't wait.
    public init(macmoshPath: String, tabs: TabOpening, runner: CommandRunner,
                pause: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }) {
        self.macmoshPath = macmoshPath
        self.tabs = tabs
        self.runner = runner
        self.pause = pause
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
        case .tabs(let list):
            return await openTabs(list)
        case .focus:
            return ActionOutcome(summary: "nothing to run", notice: nil)
        case .run(let arguments):
            return await runInBackground(arguments)
        }
    }

    /// The desk for `connect <id> <desk>`, otherwise the subcommand, so a tab is named for what it does.
    public static func tabTitle(for arguments: [String]) -> String {
        if arguments.first == "connect", arguments.count >= 3 { return arguments[2] }
        return arguments.first ?? "macmosh"
    }

    /// The sentence shown when macOS refuses to let MacMosh control the terminal app. Opening a tab and
    /// bringing one forward both say it.
    static func notAllowed(_ app: TerminalApp) -> String {
        "macOS hasn't let MacMosh control \(app.displayName). "
            + "To allow it: System Settings > Privacy & Security > Automation."
    }

    /// How one tab's opening went: opened (with the opener's sentence, when it had to open it another
    /// way), or not, with the summary and sentence that say why.
    private enum TabTry {
        case opened(notice: String?)
        case failed(ActionOutcome)
    }

    private func tryTab(_ arguments: [String]) async -> TabTry {
        let command: TabCommand
        do {
            command = try TabCommand(macmoshPath: macmoshPath, arguments: arguments)
        } catch {
            // The only thing it refuses is a path or word with a character a tab can't carry. The
            // menu's own words are plain, so in practice it is the path of the app.
            return .failed(ActionOutcome(summary: "the app's path can't go in a tab", notice: Self.moveIt))
        }
        do {
            return .opened(notice: try await tabs.open(command, title: Self.tabTitle(for: arguments)))
        } catch LaunchError.automationDenied(let app) {
            return .failed(ActionOutcome(summary: "not allowed to control the terminal app", notice: Self.notAllowed(app)))
        } catch LaunchError.failed(let reason) {
            return .failed(ActionOutcome(summary: MenuLog.tabFailure(reason), notice: "The tab didn't open. \(reason)"))
        } catch {
            return .failed(ActionOutcome(summary: MenuLog.tabFailure(""), notice: "The tab didn't open."))
        }
    }

    private func openTab(_ arguments: [String]) async -> ActionOutcome {
        switch await tryTab(arguments) {
        case .opened(let notice):
            return ActionOutcome(summary: notice == nil ? "tab opened" : "tab opened another way", notice: notice)
        case .failed(let outcome):
            return outcome
        }
    }

    /// Each tab in order, through the same path as one tab, with `tabsPause` between two. It stops at the
    /// first that doesn't open and says so as one tab would, after how many opened when any did. When
    /// tabs opened another way, the first such sentence is kept.
    private func openTabs(_ list: [[String]]) async -> ActionOutcome {
        var opened = 0, anotherWay = 0
        var notice: String?
        for (i, arguments) in list.enumerated() {
            if i > 0 { await pause(Self.tabsPause) }
            switch await tryTab(arguments) {
            case .opened(let said):
                opened += 1
                if let said {
                    anotherWay += 1
                    notice = notice ?? said
                }
            case .failed(let failure):
                let sentence = failure.notice ?? "The tab didn't open."
                return ActionOutcome(summary: MenuLog.tabsStopped(opened: opened, of: list.count, then: failure.summary),
                                     notice: opened == 0 ? sentence : "\(opened) of \(list.count) tabs opened. \(sentence)")
            }
        }
        return ActionOutcome(summary: MenuLog.tabsOpened(opened, anotherWay: anotherWay), notice: notice)
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
