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
    public static let goTo = "Go to"
    public static let closed = "(closed)"
    public static let keptWhenItExits = "Kept when it exits"
    public static let doesntComeBack = "Doesn't come back after a restart"
    public static let notMadeWithMacMosh = "Not made with MacMosh: folder and restart not known"
    public static let keepsItsCommandRunning = "Keeps its command running"
    /// The tag on the second line of a desk with no saved definition (look design 6.5); today's sentence
    /// (`notMadeWithMacMosh`) is its help tag.
    public static let madeByHand = "Made by hand"
    /// A closed desk's state cell (look design 6.5). Today's windows column says `closed`, "(closed)".
    public static let closedState = "Closed"

    // The detail strip's labels and values.
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
    /// A window's button in a desk's details that opens the sheet naming it (issue 144). Not "Rename…", which is
    /// the desk's own button in the same strip.
    public static let nameWindow = "Name…"
    /// The strip's button for a desk with one window, which has no list of windows.
    public static let nameItsWindow = "Name its window…"

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

    /// The title of a desk's button, or of a window's in its strip: "Go to" when a click brings a tab
    /// forward (the menu's `.focus`), "Open" for anything else (issue #134). The menu's full words for it are
    /// the button's help tag.
    public static func openOrGoTo(_ action: BoardAction) -> String {
        if case .menu(.focus) = action { return goTo }
        return open
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
    /// The workhorse's name, the page's title (look design 6.3).
    public var name: String
    public var headline: String
    /// The state's word and tone beside the name; the headline stays the one element VoiceOver and CI read.
    public var pill: StatePill
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
    /// "Ended", for a Ready workhorse with at least one ended desk (step 5); nil otherwise.
    public var endedHeading: String?
    /// Its ended desks, newest first. None under a workhorse that is not Ready: nothing can be started there, and
    /// its page shows the greyed list of its last Ready check instead (section 7.1 D). They are kept, and come back
    /// with its next Ready check.
    public var ended: [EndedRow]
    /// The desks of the last Ready check, for a workhorse that is not Ready now.
    public var stale: StaleDesks?
    public var foot: [BoardButton]
    /// "Home address reachable from here: yes", the menu's line.
    public var home: String?
    /// What the last action on it said (set from step 4 on).
    public var result: String?
    /// Whether it worked, beside `result` (look design 6.3); nil without one.
    public var resultKind: ResultKind?
    /// "Keep it, closed" can be offered in its New desk form: script 0.5.0 or newer (section 7.2).
    public var canKeepClosed: Bool

    /// `activity` is what the window's actions are doing on it now (`WindowActionRunner.activity`).
    public init(_ w: BoardWorkhorse, now: Date, timeZone: TimeZone, activity: WindowActivity = WindowActivity()) {
        id = w.id
        name = w.name
        headline = w.headline
        pill = w.pill
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
        let buttons = w.buttons.map { b -> BoardButton in
            guard activity.making, case .window(.newDesk) = b.action else { return b }
            return BoardButton(title: WindowActionKind.newDesk.progress, note: b.note, action: b.action, isEnabled: false)
        }
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
        let version = w.scriptVersion ?? ""
        let canRename = HostInstaller.isAtLeast(version, Self.renameNeeds)
        canKeepClosed = HostInstaller.isAtLeast(version, Self.keepClosedNeeds)
        var rows = w.desks.map { DeskRow($0, activity: activity, canRename: canRename) }
        // A desk just made has a row of its own, "Updating…", until the check that brings it lands.
        let shown = Set(rows.map(\.name))
        rows += activity.arriving.subtracting(shown).map(DeskRow.arriving)
        desks = rows.sorted { BoardModel.inNameOrder($0.name, $1.name) }
        noDesks = isReady && w.desks.isEmpty ? WindowWords.noDesks : nil
        let canKeep = canKeepClosed
        ended = isReady ? w.ended.map { EndedRow($0, now: now, timeZone: timeZone, activity: activity, canKeep: canKeep) } : []
        endedHeading = ended.isEmpty ? nil : EndedRow.heading
        stale = StaleDesks(w, now: now, timeZone: timeZone)
        home = w.homeReachable.map(WorkhorseBlock.homeLine)
        result = w.result
        resultKind = w.resultKind
    }

    /// The foot's buttons at the left, in order: every foot button but Restart… (design 6.4).
    public var footLeft: [BoardButton] {
        guard let right = footRightIndex else { return foot }
        return foot.enumerated().filter { $0.offset != right }.map(\.element)
    }

    /// Restart…, alone at the right of the foot: the first foot button of kind `.setApart`; nil without one.
    public var footRight: BoardButton? { footRightIndex.map { foot[$0] } }

    private var footRightIndex: Int? { foot.firstIndex { ButtonKind.of($0.action) == .setApart } }

    /// The menu's notice as the page shows it under the header: left out when it is this workhorse's result
    /// line, which the header shows already (a window action sets both).
    public func notice(_ notice: String?) -> String? {
        notice == result ? nil : notice
    }

    /// Rename needs script 0.6.0 (`desk-rename`, section 5.2); "Keep it, closed" needs 0.5.0 (`--permanent`).
    static let renameNeeds = "0.6.0"
    static let keepClosedNeeds = "0.5.0"
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

/// One window of a desk in its opened details (issue #134, look design 6.6): its name, then its state in words
/// ("in a tab", "not in a tab"), and a small button, "Go to" or "Open", that runs the menu's action for that window;
/// and, when its windows can be named (issue 144), a small "Name…". A window the menu has no line for (iTerm2's Tabs
/// mode, an older script) is listed by its name with no state, with only its Name… button.
public struct WindowLine: Sendable, Equatable, Identifiable {
    /// tmux's window id, `@` and digits.
    public var id: String
    /// "claude", "zsh (window 3)", "window 1": the menu's name for the window.
    public var title: String
    /// Whether a tab shows it, from the menu's facts; nil without them (an older script, the Tabs connection).
    public var state: WindowTabState?
    /// The menu's whole line ("claude (in a tab)"), or the title: the help tag of the line's buttons.
    public var help: String
    public var button: BoardButton?
    public var name: BoardButton?
    /// The window's cell, lit for all but "not in a tab"; nil without the menu's facts.
    public var cell: DeskCell? { state?.cell }

    public init(id: String, title: String, state: WindowTabState?, help: String, button: BoardButton?,
                name: BoardButton? = nil) {
        self.id = id
        self.title = title
        self.state = state
        self.help = help
        self.button = button
        self.name = name
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
    /// The menu's click on the desk (issue #134), titled "Go to" when it goes to a tab and "Open" otherwise.
    public var open: BoardButton?
    /// The menu's words for that click, "Go to website" or "Open the 1 window not in a tab": the button's help tag.
    public var openWords: String?
    /// One line per window when the desk has the menu's line per window and more than one window, or when its
    /// windows can be named and it has more than one; none otherwise.
    public var windowLines: [WindowLine]
    /// The folder and the unusual facts: "~/notes · Kept when it exits".
    public var second: String
    /// Starts with, After a restart, When its last shell exits; none for a desk made by hand.
    public var detail: [DetailLine]
    /// "Keeps its command running", when the desk has that flag.
    public var facts: [String]
    /// New window (when open), Name its window… (one window, issue 144), Rename…, Remove…, with the strip's short
    /// titles.
    public var detailButtons: [BoardButton]
    /// "Renaming…", "Removing…" or "Naming…" while one of the window's actions runs on it, "Updating…" until the
    /// check after it lands; nil otherwise. Shown in place of the tab count.
    public var status: String?
    /// The cells on the desk's tile (look design 6.5); none for a desk just made, before its check.
    public var cells: DeskCells
    /// Its window names ("claude, zsh, vim"), or "1 window" when they have none; "" for a closed desk and for a desk
    /// just made (look design 6.5).
    public var windowWords: String
    /// The state cell: the running action's words first ("Renaming…", "Updating…"); else "In 2 tabs", "No tab" or
    /// "Closed".
    public var state: DeskStateCell
    /// The folder and the unusual facts, or the tag "Made by hand".
    public var secondLine: SecondLine
    /// What VoiceOver says for the row, and what CI reads: the name, the window words, the second line, then the
    /// state's word, the empty ones left out, joined with ", ".
    public var spokenLabel: String
    /// A click on the row opens a detail strip with something in it; a new desk's row before its check has none.
    public var hasStrip: Bool { !(detail.isEmpty && facts.isEmpty && windowLines.isEmpty && detailButtons.isEmpty) }

    /// `activity` turns the desk's buttons off while an action runs on it, and names that action; without
    /// `canRename` (a script older than 0.6.0) it has no Rename….
    public init(_ desk: BoardDesk, activity: WindowActivity = WindowActivity(), canRename: Bool = true) {
        name = desk.name
        if !desk.isOpen {
            windows = WindowWords.closed
        } else if desk.windowNames.isEmpty {
            windows = WindowWords.windows(desk.windowCount)
        } else {
            windows = desk.windowNames.joined(separator: ", ")
        }
        tabs = desk.isOpen ? WindowWords.tabs(desk.tabsOpen) : nil
        open = desk.open.map { BoardButton(title: WindowWords.openOrGoTo($0.action), note: $0.note, action: $0.action) }
        openWords = desk.open?.title
        let names = DeskWindows.names(desk.windows.map { (index: $0.index, name: $0.name) })
        windowLines = zip(desk.windows, names).compactMap { w, named in
            guard let id = w.id, w.button != nil || w.nameButton != nil else { return nil }
            let title = w.nameAndState?.name ?? named
            return WindowLine(id: id, title: title, state: w.nameAndState?.state, help: w.button?.title ?? title,
                              button: w.button.map { BoardButton(title: WindowWords.openOrGoTo($0.action), action: $0.action) },
                              name: w.nameButton)
        }
        if desk.madeByMacMosh {
            var parts = [desk.folder ?? ""]
            if desk.permanent == true { parts.append(WindowWords.keptWhenItExits) }
            if desk.reopen == false { parts.append(WindowWords.doesntComeBack) }
            second = parts.filter { !$0.isEmpty }.joined(separator: " · ")
            // No Folder line: the row's second line shows the folder whenever it is known (look design 6.6).
            detail = [
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
        detailButtons = desk.buttons.map(Self.short).filter { b in
            if case .window(.rename) = b.action { return canRename }
            return true
        }
        let running = activity.busy[desk.name]
        let marked = activity.updating.contains(desk.name) || activity.arriving.contains(desk.name)
        status = running?.progress ?? (marked ? WindowActivity.updatingWords : nil)
        cells = DeskCells(desk)
        if !desk.isOpen {
            windowWords = ""
        } else if desk.windowNames.isEmpty {
            windowWords = WindowWords.windows(desk.windowCount)
        } else {
            windowWords = desk.windowNames.joined(separator: ", ")
        }
        if let status {
            state = DeskStateCell(word: status, kind: .busy)
        } else if !desk.isOpen {
            state = DeskStateCell(word: WindowWords.closedState, kind: .closed)
        } else {
            state = DeskStateCell(word: WindowWords.tabs(desk.tabsOpen), kind: desk.tabsOpen > 0 ? .inTabs : .noTab)
        }
        if desk.madeByMacMosh {
            var facts: [String] = []
            if desk.permanent == true { facts.append(WindowWords.keptWhenItExits) }
            if desk.reopen == false { facts.append(WindowWords.doesntComeBack) }
            secondLine = SecondLine(folder: desk.folder.flatMap { $0.isEmpty ? nil : $0 }, facts: facts, tag: nil)
        } else {
            secondLine = SecondLine(folder: nil, facts: [], tag: WindowWords.madeByHand)
        }
        spokenLabel = Self.spoken(name: name, windowWords: windowWords, second: secondLine, state: state)
        if let running {
            func off(_ b: BoardButton) -> BoardButton {
                var b = b
                b.isEnabled = false
                switch (running, b.action) {
                case (.rename, .window(.rename)), (.remove, .window(.remove)): b.title = running.progress
                default: break
                }
                return b
            }
            open = open.map(off)
            detailButtons = detailButtons.map(off)
            windowLines = windowLines.map {
                WindowLine(id: $0.id, title: $0.title, state: $0.state, help: $0.help, button: $0.button.map(off),
                           name: $0.name.map(off))
            }
        }
    }

    /// A desk the window has just made, before the check that brings it lands: its name and "Updating…".
    static func arriving(_ name: String) -> DeskRow {
        DeskRow(name: name)
    }

    private init(name: String) {
        self.name = name
        windows = ""
        tabs = nil
        open = nil
        openWords = nil
        windowLines = []
        second = ""
        detail = []
        facts = []
        detailButtons = []
        status = WindowActivity.updatingWords
        cells = DeskCells(cells: [], more: false)
        windowWords = ""
        state = DeskStateCell(word: WindowActivity.updatingWords, kind: .busy)
        secondLine = SecondLine(folder: nil, facts: [], tag: nil)
        spokenLabel = Self.spoken(name: name, windowWords: windowWords, second: secondLine, state: state)
    }

    private static func spoken(name: String, windowWords: String, second: SecondLine, state: DeskStateCell) -> String {
        [name, windowWords, second.whole, state.word].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// The foot of the opened details: New window, Name its window… and Rename… at the left, Remove… alone at the
    /// right (look design 6.6).
    public var detailSplit: ButtonSplit { ButtonSplit(detailButtons, apart: .destructive) }

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

/// What the sidebar has selected: a workhorse by id, the Add a Mac page or the Settings page; or, with no workhorse
/// on the board because the saved list can't be read, the store's sentence.
public enum WindowSelection: Sendable, Hashable {
    case workhorse(String)
    case addMac
    /// The saved list can't be read and no workhorse is on the board: the window shows the sentence the
    /// menu shows (`BoardOnScreen.listProblem`), not an invitation to add a Mac.
    case unreadableList
    /// The Settings page (issue 157): This Mac's terminal and each saved workhorse's settings.
    case settings

    /// The chosen page while it is still there; otherwise the first workhorse, or Add a Mac when there
    /// is none (main window design, section 7.1 A). When the list can't be read and none was read
    /// before, the store's sentence in place of either. Settings, once chosen, stays chosen in every case: with no
    /// workhorse it shows This Mac's terminal and "No workhorses yet…", and with a list that can't be read, the
    /// terminal and the store's sentence (`SettingsPage.none`).
    public static func resolve(_ chosen: WindowSelection?, board: Board, listUnreadable: Bool = false) -> WindowSelection {
        if chosen == .settings { return .settings }
        if listUnreadable && board.workhorses.isEmpty { return .unreadableList }
        switch chosen {
        case .addMac?: return .addMac
        case .workhorse(let id)? where board.workhorses.contains { $0.id == id }: return .workhorse(id)
        default: return board.workhorses.first.map { .workhorse($0.id) } ?? .addMac
        }
    }
}

/// One line of the sidebar: each workhorse with its state's symbol (the menu icon's), then Add a Mac…, then Settings.
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
            + [SidebarItem(selection: .addMac, title: ButtonRules.addAMac.title, symbol: "plus"),
               SidebarItem(selection: .settings, title: SettingsWords.heading, symbol: "gearshape")]
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
