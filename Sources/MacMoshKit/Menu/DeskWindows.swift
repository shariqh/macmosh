import Foundation

/// What this Mac knows about its own terminal tabs when the menu is built (menu design 8): the live tab
/// records, and the terminal a new tab opens in (`TabOpener.terminal`). `MenuRefresher` reads both and
/// hands them to `MenuModel.build` as this value, so the model reads no file.
public struct TabsOnThisMac: Sendable, Equatable {
    /// The records whose process is still the one that wrote them (`TabRecordStore.isLive`).
    public var records: [TabRecord]
    /// Where a tab the menu opens will open.
    public var terminal: TerminalApp

    public init(records: [TabRecord] = [], terminal: TerminalApp = .iterm2) {
        self.records = records
        self.terminal = terminal
    }
}

/// What the menu's last build knew about this Mac's tabs, and the time it built with: the same records, the
/// same terminal and the same time, so the window's board makes exactly the menu's choices (issue #134).
/// `MenuRefresher` publishes it after each build; `BoardModel.build` takes it as a value.
public struct TabsSeen: Sendable, Equatable {
    public var tabs: TabsOnThisMac
    /// The `now` the menu's build was given, which dates the records.
    public var at: Date

    public init(tabs: TabsOnThisMac, at: Date) {
        self.tabs = tabs
        self.at = at
    }
}

/// Whether a desk gets a line per window (menu design 6.1 (a) and 8.3). All three must hold:
/// 1. the workhorse's script is 0.8.0 or newer (`HostInstaller.isAtLeast`, the installer's comparison), so
///    `attach` takes `--label`, `--window` and `--new-window`;
/// 2. the connection a tab will really use is mosh or plain ssh: the workhorse's mode as `connect` turns
///    it for the terminal the tab opens in (`ConnectionMode.used`), since in iTerm2's Tabs mode every window
///    is a tab already and `connect` refuses the options;
/// 3. for an open desk, the report gives its windows' details (`windowinfo` lines). A closed permanent desk
///    has no windows, so 1 and 2 are enough.
/// When it fails, the desk's row and submenu are what they were before (shape (b)).
public enum WindowLinesGate {
    public static let firstScriptVersion = "0.8.0"

    /// `desk` is the desk's session in the report, nil for a closed permanent desk.
    public static func passes(_ r: CheckResult, desk: HostStatus.Desk?, terminal: TerminalApp) -> Bool {
        guard let status = r.status, HostInstaller.isAtLeast(status.scriptVersion, firstScriptVersion) else { return false }
        guard r.workhorse.mode.used(inITerm2: terminal == .iterm2) != .tabs else { return false }
        return desk?.hasWindowInfo ?? true
    }
}

/// A desk's row and submenu with a line per window (menu design 6.1 (a), 6.2 and 6.3), for a desk past
/// `WindowLinesGate`. Which tab shows which window comes from `DeskTabs.build`. A window is in a tab when any
/// tab shows it, whether this Mac can find that tab (a findable tab) or not (another tab).
public struct DeskWindows: Sendable, Equatable {
    /// The row: `<desk> · 1 window` or `<desk> · N windows`, then nothing, `, in a tab` (one window),
    /// `, all in tabs`, `, 1 in a tab` or `, K in tabs`; `<desk> (closed)` for a closed permanent desk.
    public var title: String
    /// The submenu's first line, which a click on the row does too.
    public var first: ActionButton
    /// One line per window when the desk has more than one, in the desk's order.
    public var windows: [ActionButton]
    /// New window, in a tab of its own; nil for a closed desk.
    public var newWindow: ActionButton?
    /// The desk's flags that are set, as one grey line: `kept running`, `permanent`, or both; nil for none.
    public var flags: String?
    /// How many tabs show its windows, findable or not, a tab opened a moment ago that the report doesn't list
    /// yet included; 0 for a closed desk. The window's board says "In 2 tabs" from it (issue #134).
    public var tabs: Int
    /// The `connect` arguments of a tab on each window that no tab shows, in the desk's order; none for a closed
    /// desk. The window's "Open the N not in a tab" opens these (issue #134).
    public var notInATab: [[String]]
    /// By window id, how many tabs show that window, findable or not, counted as `tabs` counts them; empty for a
    /// closed desk. The window's desk tile lights a cell for each window above 0 (look design 6.5).
    public var tabsByWindow: [String: Int]
    /// Each window's name and state, in the desk's order, for every open desk, one window included; empty for a
    /// closed desk. The menu's window lines are built from it; the window's details show it (look design 6.6).
    public var namesAndStates: [WindowNameAndState]

    public init(title: String, first: ActionButton, windows: [ActionButton], newWindow: ActionButton?, flags: String?,
                tabs: Int = 0, notInATab: [[String]] = [], tabsByWindow: [String: Int] = [:],
                namesAndStates: [WindowNameAndState] = []) {
        self.title = title
        self.first = first
        self.windows = windows
        self.newWindow = newWindow
        self.flags = flags
        self.tabs = tabs
        self.notInATab = notInATab
        self.tabsByWindow = tabsByWindow
        self.namesAndStates = namesAndStates
    }

    /// The shape for one desk of workhorse `id`, with this Mac's live records and the time. nil for an open
    /// desk with no window whose id is `@` and digits, which then keeps today's shape.
    ///
    /// The first line, by the windows that have no tab (N), only tabs this Mac can't find (U), or a findable
    /// tab (F):
    /// - one window, no tab: `Open <desk>`, a tab on it;
    /// - several windows, none in a tab: `Open <desk> in K tabs`, a tab on each, in order;
    /// - some with no tab and some in one: `Open the 1 window not in a tab` or `Open the K windows not in a
    ///   tab`, a tab on each window with none;
    /// - every window in a tab, one findable: `Go to <desk>`, the newest findable tab of the lowest-numbered
    ///   such window, or a tab on that window if it has gone;
    /// - every window in a tab, none findable: `Open <desk> in a new tab`, on a window of the tab's own;
    /// - a closed permanent desk: `Open <desk>`, which makes the desk and then a tab of its own on it.
    /// No action opens a tab on a window with a findable tab, except `.focus`'s fallback once that tab has gone.
    public static func of(_ desk: DeskLine, workhorse id: String, records: [TabRecord], now: Date) -> DeskWindows? {
        let name = desk.name
        func connect(_ rest: [String]) -> [String] { ["connect", id, name] + rest }
        func onWindow(_ w: DeskTabs.WindowTabs) -> [String] { connect(["--window", w.windowId]) }
        let flags = [desk.isKept ? "kept running" : nil, desk.isPermanent ? "permanent" : nil].compactMap { $0 }
        let flagsLine = flags.isEmpty ? nil : flags.joined(separator: ", ")

        guard let session = desk.session else {
            return DeskWindows(title: "\(name) (closed)",
                               first: ActionButton(key: "open", title: "Open \(name)", action: .tab(connect(["--view"]))),
                               windows: [], newWindow: nil, flags: flagsLine)
        }
        let tabs = DeskTabs.build(desk: session, workhorse: id, records: records, now: now)
        guard !tabs.isEmpty else { return nil }

        let noTab = tabs.filter { $0.labels.isEmpty && $0.others == 0 }
        let inTabs = tabs.count - noTab.count
        let count = tabs.count

        var title = "\(name) · " + (count == 1 ? "1 window" : "\(count) windows")
        if count == 1 {
            if inTabs == 1 { title += ", in a tab" }
        } else if inTabs == count {
            title += ", all in tabs"
        } else if inTabs == 1 {
            title += ", 1 in a tab"
        } else if inTabs > 1 {
            title += ", \(inTabs) in tabs"
        }

        let first: ActionButton
        if noTab.count == count {
            first = count == 1
                ? ActionButton(key: "open", title: "Open \(name)", action: .tab(onWindow(tabs[0])))
                : ActionButton(key: "open", title: "Open \(name) in \(count) tabs", action: .tabs(tabs.map(onWindow)))
        } else if !noTab.isEmpty {
            let what = noTab.count == 1 ? "the 1 window" : "the \(noTab.count) windows"
            first = ActionButton(key: "open", title: "Open \(what) not in a tab", action: .tabs(noTab.map(onWindow)))
        } else if let found = tabs.filter({ $0.newest != nil }).min(by: { $0.index < $1.index }), let label = found.newest {
            first = ActionButton(key: "open", title: "Go to \(name)", action: .focus(label: label, orOpen: onWindow(found)))
        } else {
            first = ActionButton(key: "open", title: "Open \(name) in a new tab", action: .tab(connect(["--view"])))
        }

        let pairs = namesAndStates(of: session, tabs: tabs)
        var lines: [ActionButton] = []
        if count > 1 {
            for (w, pair) in zip(tabs, pairs) {
                let action: MenuAction = w.newest.map { .focus(label: $0, orOpen: onWindow(w)) } ?? .tab(onWindow(w))
                lines.append(ActionButton(key: "win:\(w.windowId)", title: pair.menuWords, action: action))
            }
        }
        return DeskWindows(title: title, first: first, windows: lines,
                           newWindow: ActionButton(key: "window", title: "New window", action: .tab(connect(["--new-window"]))),
                           flags: flagsLine, tabs: tabs.reduce(0) { $0 + $1.labels.count + $1.others },
                           notInATab: noTab.map(onWindow),
                           tabsByWindow: Dictionary(tabs.map { ($0.windowId, $0.labels.count + $0.others) },
                                                    uniquingKeysWith: { a, b in a + b }),
                           namesAndStates: pairs)
    }
}
