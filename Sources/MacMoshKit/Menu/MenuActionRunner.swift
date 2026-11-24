import Foundation

/// Opens a terminal tab, or brings one forward. `TabOpener` is the real one; tests use a stand-in that
/// opens nothing.
public protocol TabOpening: Sendable {
    func open(_ command: TabCommand, title: String) async throws -> String?
    func select(tty: String, terminal: TabRecord.Terminal) async throws -> TabSelection
}

extension TabOpener: TabOpening {}

/// Does what a menu item asks: open a tab that runs the bundled `macmosh`, or several, or bring a tab
/// forward, all from this process; or run `macmosh` in the background.
public struct MenuActionRunner: Sendable {
    private let macmoshPath: String
    private let tabs: TabOpening
    private let runner: CommandRunner
    private let records: TabRecordStore
    private let pause: @Sendable (Duration) async -> Void
    private let now: @Sendable () -> Date

    /// How long a background command may run before it is stopped.
    static let runLimit: Duration = .seconds(30)

    /// The wait between two tabs of one `.tabs` action, so the terminal is not flooded.
    static let tabsPause: Duration = .milliseconds(400)

    /// The sentence shown when the app's own path can't go into a terminal tab.
    static let moveIt = "MacMosh can't open terminal tabs from where it is now. "
        + "Move it to the Applications folder and open it again."

    /// The sentence shown when a tab to bring forward had gone and a new one was opened instead.
    static let tabClosed = "That tab has closed, so MacMosh opened a new one."

    /// `macmoshPath` is the command inside the app bundle, `Contents/Helpers/macmosh`. `records` are this
    /// Mac's tab records, which a focus action reads. `pause` is how the wait between tabs is done; tests
    /// pass one that doesn't wait. `now` is the clock that says whether a record is fresh.
    public init(macmoshPath: String, tabs: TabOpening, runner: CommandRunner, records: TabRecordStore,
                pause: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) },
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.macmoshPath = macmoshPath
        self.tabs = tabs
        self.runner = runner
        self.records = records
        self.pause = pause
        self.now = now
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
        case .focus(let label, let orOpen):
            return await focus(label: label, orOpen: orOpen)
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
    /// way), a tab opened a moment ago for the same thing brought forward instead, or not, with the summary
    /// and sentence that say why.
    private enum TabTry {
        case opened(notice: String?)
        case alreadyOpen
        case failed(ActionOutcome)
    }

    /// The tab this Mac opened a moment ago for what `arguments` would open, when there is one (menu design
    /// 8.2): for `connect <id> <desk> --window @n`, a record of that workhorse and desk that asked for `@n`;
    /// for `connect <id> <desk> --view`, one made with `--view`. It must be younger than `DeskTabs.freshFor`
    /// (either way, in case the clock moved back), its process still the one that wrote it, and its device a
    /// terminal tab's; the newest such. The menu shows such a tab only once a check has seen it, and the tab
    /// writes its record only after its own check, so a second click in between would open a second tab.
    private func freshTab(for arguments: [String]) -> TabRecord? {
        guard arguments.count >= 4, arguments[0] == "connect" else { return nil }
        let (id, desk, option) = (arguments[1], arguments[2], Array(arguments.dropFirst(3)))
        let same: (TabRecord) -> Bool
        if option.count == 2, option[0] == "--window", HostStatus.isWindowId(option[1]) {
            same = { $0.askedWindow == option[1] }
        } else if option == ["--view"] {
            same = { $0.target == TabTarget.view.recordWord }
        } else {
            return nil
        }
        let time = now()
        return records.records().last { record in
            record.workhorse == id && record.desk == desk && same(record)
                && abs(time.timeIntervalSince(record.openedAt)) < DeskTabs.freshFor
                && records.isLive(record) && TabRecord.isTerminalDevice(record.tty)
        }
    }

    private func tryTab(_ arguments: [String]) async -> TabTry {
        if let record = freshTab(for: arguments) {
            do {
                if try await tabs.select(tty: record.tty, terminal: record.terminal) == .selected { return .alreadyOpen }
                records.remove(label: record.label)
            } catch {
                return .failed(Self.notSelected(error))
            }
        }
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
        case .alreadyOpen:
            return ActionOutcome(summary: MenuLog.tabAlreadyOpen, notice: nil)
        case .failed(let outcome):
            return outcome
        }
    }

    /// Each tab in order, through the same path as one tab, with `tabsPause` between two. It stops at the
    /// first that doesn't open and says so as one tab would, after how many opened when any did. When
    /// tabs opened another way, the first such sentence is kept. A tab opened a moment ago that is brought
    /// forward instead counts as opened.
    private func openTabs(_ list: [[String]]) async -> ActionOutcome {
        var opened = 0, anotherWay = 0, alreadyOpen = 0
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
            case .alreadyOpen:
                opened += 1
                alreadyOpen += 1
            case .failed(let failure):
                let sentence = failure.notice ?? "The tab didn't open."
                return ActionOutcome(summary: MenuLog.tabsStopped(opened: opened, of: list.count, then: failure.summary),
                                     notice: opened == 0 ? sentence : "\(opened) of \(list.count) tabs opened. \(sentence)")
            }
        }
        return ActionOutcome(summary: MenuLog.tabsOpened(opened, anotherWay: anotherWay, alreadyOpen: alreadyOpen), notice: notice)
    }

    /// Brings forward the tab labelled `label` (menu design 6.2). The record is read; one that is missing, whose
    /// process has ended, or whose terminal device isn't `/dev/ttys` and digits is removed, and `orOpen`
    /// opens as a new tab instead. Otherwise the record's terminal is asked to select the tab with that device,
    /// with the device as a separate argument; `gone` is handled as a missing record. A word that isn't a label
    /// counts as missing, and never names a file.
    private func focus(label: String, orOpen: [String]) async -> ActionOutcome {
        guard let record = records.record(label: label) else { return await reopen(orOpen, .noRecord) }
        guard records.isLive(record) else {
            records.remove(label: label)
            return await reopen(orOpen, .processEnded)
        }
        guard TabRecord.isTerminalDevice(record.tty) else {
            records.remove(label: label)
            return await reopen(orOpen, .noDevice)
        }
        do {
            switch try await tabs.select(tty: record.tty, terminal: record.terminal) {
            case .selected:
                return ActionOutcome(summary: MenuLog.tabSelected, notice: nil)
            case .gone:
                records.remove(label: label)
                return await reopen(orOpen, .notInTerminal)
            }
        } catch {
            return Self.notSelected(error)
        }
    }

    /// What a select that threw comes to, for a focus and for a tab opened a moment ago alike: a refusal says
    /// what opening a tab says; a step that stopped, which step and the error number (issue #129); anything
    /// else, the terminal's own text for the person and only its error number for the log.
    private static func notSelected(_ error: Error) -> ActionOutcome {
        let sorry = "Couldn't bring that tab forward."
        switch error {
        case LaunchError.automationDenied(let app):
            return ActionOutcome(summary: "not allowed to control the terminal app", notice: notAllowed(app))
        case LaunchError.selectStopped(let app, let step, let number):
            return ActionOutcome(summary: MenuLog.selectStopped(step, error: number),
                                 notice: "\(sorry) \(LaunchError.stoppedReason(app, step: step, error: number))")
        case LaunchError.failed(let reason):
            return ActionOutcome(summary: MenuLog.selectFailure(reason), notice: "\(sorry) \(reason)")
        default:
            return ActionOutcome(summary: MenuLog.selectFailure(""), notice: sorry)
        }
    }

    /// Opens `orOpen` as a new tab in place of one that has gone. When it opens, the notice says the tab had
    /// closed (followed by the opener's own sentence, when it opened another way); when it doesn't, the
    /// notice is the one a tab that didn't open gives.
    private func reopen(_ orOpen: [String], _ why: MenuLog.TabGone) async -> ActionOutcome {
        switch await tryTab(orOpen) {
        case .opened(nil):
            return ActionOutcome(summary: MenuLog.tabGone(why, then: "opened a new one"), notice: Self.tabClosed)
        case .opened(let said?):
            return ActionOutcome(summary: MenuLog.tabGone(why, then: "opened a new one another way"),
                                 notice: "\(Self.tabClosed) \(said)")
        case .alreadyOpen:
            return ActionOutcome(summary: MenuLog.tabGone(why, then: "selected another tab on its window"), notice: nil)
        case .failed(let failure):
            return ActionOutcome(summary: MenuLog.tabGone(why, then: "then \(failure.summary)"), notice: failure.notice)
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
