import Foundation

/// Every word the MacMosh window shows that the menu does not already have (main window design,
/// section 7.1). The views take their words from here and from the board, never from their own text.
public enum WindowWords {
    /// The window's title. On screen it is only ever called "MacMosh" (design, section 2).
    public static let title = "MacMosh"
    /// The id of the window's scene, which `openWindow` names.
    public static let windowID = "main"
    /// The menu's line that opens it, just above Quit MacMosh.
    public static let openLine = "Open MacMosh"

    public static let checking = "Checking…"
    public static let desks = "Desks"
    public static let noDesks = "No desks yet."
    public static let open = "Open"
    public static let closed = "(closed)"
    public static let keptWhenItExits = "Kept when it exits"
    public static let doesntComeBack = "Doesn't come back after a restart"
    public static let notMadeWithMacMosh = "Not made with MacMosh: folder and restart not known"
    public static let keepsItsCommandRunning = "Keeps its command running"

    // The detail strip's labels and values.
    public static let folder = "Folder"
    public static let startsWith = "Starts with"
    public static let plainShell = "A plain shell"
    public static let afterARestart = "After a restart"
    public static let comesBack = "Comes back"
    public static let doesntComeBackShort = "Doesn't come back"
    public static let whenItsLastShellExits = "When its last shell exits"
    public static let removeTheDesk = "Remove the desk"
    public static let keepItClosed = "Keep it, closed"
    public static let newWindow = "New window"
    public static let rename = "Rename…"
    public static let remove = "Remove…"

    /// "Checked 14:02", with the menu's short time ("yesterday 14:02", "3 Jan").
    public static func checked(_ date: Date, now: Date, timeZone: TimeZone) -> String {
        "Checked " + StatusFormat.shortTime(date, now: now, timeZone: timeZone)
    }

    /// "No tab", "In 1 tab", "In 2 tabs".
    public static func tabs(_ count: Int) -> String {
        switch count {
        case ...0: return "No tab"
        case 1: return "In 1 tab"
        default: return "In \(count) tabs"
        }
    }

    /// "1 window", "2 windows": for an open desk whose windows have no names.
    public static func windows(_ count: Int) -> String {
        count == 1 ? "1 window" : "\(count) windows"
    }
}

/// What the window shows for one workhorse, laid out from its block on the board: every word and button
/// is decided here, and the view only draws them (main window design, sections 7.1 A and D).
///
/// The board's buttons are split by where they sit, keeping the board's order: the state's own under
/// the hint (Fix…, Unlock disk…, Log in…, Pair…, Finish setting up…), "Open the N not in a tab" and
/// New desk… by the Desks heading, and the rest at the foot (Share screen, the lid-closed switch,
/// Restart…, Run the checklist…), as the menu orders them.
public struct WorkhorsePage: Sendable, Equatable {
    public var id: String
    public var headline: String
    public var hint: String?
    public var summary: String?
    /// "Checked 14:02"; nil when it has never answered.
    public var checked: String?
    /// "Checking…" while a check runs; nil otherwise. Everything else stays as it was.
    public var checking: String?
    public var checkNow: BoardButton
    public var underHint: [BoardButton]
    /// "Desks", for a Ready workhorse.
    public var desksHeading: String?
    public var deskButtons: [BoardButton]
    public var desks: [DeskRow]
    /// "No desks yet." for a Ready workhorse with none.
    public var noDesks: String?
    /// The desks of the last Ready check, for a workhorse that is not Ready now.
    public var stale: StaleDesks?
    public var foot: [BoardButton]
    /// "Home address reachable from here: yes", the menu's line.
    public var home: String?
    /// What the last action on it said (set from step 4 on).
    public var result: String?

    public init(_ w: BoardWorkhorse, now: Date, timeZone: TimeZone) {
        id = w.id
        headline = w.headline
        hint = w.hint
        summary = w.summary
        checked = w.checkedAt.map { WindowWords.checked($0, now: now, timeZone: timeZone) }
        // A workhorse that has never answered says "Still checking…" in its headline already.
        checking = w.isChecking && w.state != nil ? WindowWords.checking : nil
        checkNow = BoardButton(ButtonRules.checkNow)
        let isDeskButton: (BoardButton) -> Bool = {
            switch $0.action {
            case .window(.newDesk), .window(.openAllWithoutTab): return true
            default: return false
            }
        }
        let buttons = w.buttons
        if let first = buttons.firstIndex(where: isDeskButton) {
            let last = buttons.lastIndex(where: isDeskButton) ?? first
            underHint = Array(buttons[..<first])
            deskButtons = Array(buttons[first...last])
            foot = Array(buttons[(last + 1)...])
        } else {
            // Not Ready: the checklist is always the last button (`WorkhorseBlock.buttons`).
            underHint = Array(buttons.dropLast())
            deskButtons = []
            foot = Array(buttons.suffix(1))
        }
        var isReady = false
        if case .ready? = w.state { isReady = true }
        desksHeading = isReady ? WindowWords.desks : nil
        desks = w.desks.map { DeskRow($0) }
        noDesks = isReady && w.desks.isEmpty ? WindowWords.noDesks : nil
        stale = StaleDesks(w, now: now, timeZone: timeZone)
        home = w.homeReachable.map(WorkhorseBlock.homeLine)
        result = w.result
    }
}

/// One line of a desk's detail strip: "Folder" and "~/Development/website".
public struct DetailLine: Sendable, Equatable {
    public var label: String
    public var value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

/// One desk's short row and its detail strip (main window design, section 7.1 A).
public struct DeskRow: Sendable, Equatable, Identifiable {
    public var id: String { name }
    public var name: String
    /// Its window names ("claude, zsh, vim"), or "(closed)".
    public var windows: String
    /// "In 2 tabs" or "No tab"; nil for a closed desk.
    public var tabs: String?
    /// Opens a tab on it (the menu's `connect`), titled "Open".
    public var open: BoardButton?
    /// The folder and the unusual facts: "~/notes · Kept when it exits".
    public var second: String
    /// Folder, Starts with, After a restart, When its last shell exits; none for a desk made by hand.
    public var detail: [DetailLine]
    /// "Keeps its command running", when the desk has that flag.
    public var facts: [String]
    /// New window (when open), Rename…, Remove…, with the strip's short titles.
    public var detailButtons: [BoardButton]

    public init(_ desk: BoardDesk) {
        name = desk.name
        if !desk.isOpen {
            windows = WindowWords.closed
        } else if desk.windowNames.isEmpty {
            windows = WindowWords.windows(desk.windowCount)
        } else {
            windows = desk.windowNames.joined(separator: ", ")
        }
        tabs = desk.isOpen ? WindowWords.tabs(desk.tabsOpen) : nil
        open = desk.open.map { BoardButton(title: WindowWords.open, note: $0.note, action: $0.action) }
        if desk.madeByMacMosh {
            var parts = [desk.folder ?? ""]
            if desk.permanent == true { parts.append(WindowWords.keptWhenItExits) }
            if desk.reopen == false { parts.append(WindowWords.doesntComeBack) }
            second = parts.filter { !$0.isEmpty }.joined(separator: " · ")
            detail = [
                DetailLine(label: WindowWords.folder, value: desk.folder ?? ""),
                DetailLine(label: WindowWords.startsWith, value: desk.command ?? WindowWords.plainShell),
                DetailLine(label: WindowWords.afterARestart,
                           value: desk.reopen == false ? WindowWords.doesntComeBackShort : WindowWords.comesBack),
                DetailLine(label: WindowWords.whenItsLastShellExits,
                           value: desk.permanent == true ? WindowWords.keepItClosed : WindowWords.removeTheDesk),
            ]
            facts = desk.keep == true ? [WindowWords.keepsItsCommandRunning] : []
        } else {
            second = WindowWords.notMadeWithMacMosh
            detail = []
            facts = []
        }
        detailButtons = desk.buttons.map(Self.short)
    }

    /// The strip sits under the desk's own row, so its buttons need not name it: "Rename…" for
    /// "Rename website…". Any other button keeps its title.
    private static func short(_ b: BoardButton) -> BoardButton {
        var b = b
        switch b.action {
        case .window(.rename): b.title = WindowWords.rename
        case .window(.remove): b.title = WindowWords.remove
        case .menu(.run(let args)) where args.count == 4 && args[0] == "desk" && args[1] == "window":
            b.title = WindowWords.newWindow
        default: break
        }
        return b
    }
}

/// The desks of a workhorse's last Ready check, greyed under any other state, with the heading that
/// fits the state (main window design, section 7.1 D).
public struct StaleDesks: Sendable, Equatable {
    public var heading: String
    public var lines: [String]

    public init(heading: String, lines: [String]) {
        self.heading = heading
        self.lines = lines
    }

    /// nil when the workhorse is Ready, or when no check has found it Ready since MacMosh started.
    init?(_ w: BoardWorkhorse, now: Date, timeZone: TimeZone) {
        guard let desks = w.lastReadyDesks, let at = w.lastReadyAt else { return nil }
        let time = StatusFormat.shortTime(at, now: now, timeZone: timeZone)
        let names = desks.map(\.name)
        let back = desks.filter { $0.reopen == true }.map(\.name)
        let notBack = desks.filter { $0.reopen != true }.map(\.name)
        switch w.state {
        case .locked?:
            heading = "Desks before the restart (checked \(time))"
            lines = Self.lines(comingBack: back, notComingBack: notBack,
                               after: "These come back once it is unlocked and logged in:")
        case .waitingForLogin?:
            heading = "Desks before the restart (checked \(time))"
            lines = Self.lines(comingBack: back, notComingBack: notBack, after: "These come back once someone logs in:")
        default:
            heading = "Desks at the last good check (\(time))"
            lines = names.isEmpty ? [] : [names.joined(separator: ", ") + "."]
        }
    }

    /// The promise and the names that come back, then the ones that don't, each part only when it has names.
    static func lines(comingBack: [String], notComingBack: [String], after promise: String) -> [String] {
        var lines: [String] = []
        if !comingBack.isEmpty { lines += [promise, comingBack.joined(separator: ", ") + "."] }
        if notComingBack.count == 1 {
            lines.append("This one doesn't come back: \(notComingBack[0]).")
        } else if notComingBack.count > 1 {
            lines.append("These don't come back: \(notComingBack.joined(separator: ", ")).")
        }
        return lines
    }
}

/// What the sidebar has selected: a workhorse by id, or the Add a Mac page; or, with no workhorse on
/// the board because the saved list can't be read, the store's sentence.
public enum WindowSelection: Sendable, Hashable {
    case workhorse(String)
    case addMac
    /// The saved list can't be read and no workhorse is on the board: the window shows the sentence the
    /// menu shows (`BoardOnScreen.listProblem`), not an invitation to add a Mac.
    case unreadableList

    /// The chosen page while it is still there; otherwise the first workhorse, or Add a Mac when there
    /// is none (main window design, section 7.1 A). When the list can't be read and none was read
    /// before, the store's sentence in place of either.
    public static func resolve(_ chosen: WindowSelection?, board: Board, listUnreadable: Bool = false) -> WindowSelection {
        if listUnreadable && board.workhorses.isEmpty { return .unreadableList }
        switch chosen {
        case .addMac?: return .addMac
        case .workhorse(let id)? where board.workhorses.contains { $0.id == id }: return .workhorse(id)
        default: return board.workhorses.first.map { .workhorse($0.id) } ?? .addMac
        }
    }
}

/// One line of the sidebar: each workhorse with its state's symbol (the menu icon's), then Add a Mac….
public struct SidebarItem: Sendable, Equatable, Identifiable {
    public var id: WindowSelection { selection }
    public var selection: WindowSelection
    public var title: String
    public var symbol: String

    public init(selection: WindowSelection, title: String, symbol: String) {
        self.selection = selection
        self.title = title
        self.symbol = symbol
    }

    public static func list(_ board: Board) -> [SidebarItem] {
        board.workhorses.map { SidebarItem(selection: .workhorse($0.id), title: $0.name, symbol: $0.symbol) }
            + [SidebarItem(selection: .addMac, title: ButtonRules.addAMac.title, symbol: "plus")]
    }
}

/// The Add a Mac page (main window design, section 7.1 E): what to switch on at the other Mac, and the
/// menu's own Add a Mac… button, which opens the terminal tab that pairs.
public struct AddMacPage: Sendable, Equatable {
    public var heading: String
    public var lines: [String]
    public var button: BoardButton

    public static let standard = AddMacPage(
        heading: "Add a Mac",
        lines: [
            "At the other Mac, turn on these two in System Settings > General > Sharing:",
            "Remote Login, so MacMosh can reach it.",
            "Screen Sharing, so you can log in to it after a restart.",
            "The button below opens a terminal tab, where the first connection asks for the other Mac's password. MacMosh never sees it.",
        ],
        button: BoardButton(ButtonRules.addAMac))
}
