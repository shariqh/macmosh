import Foundation

/// What the MacMosh window shows: every workhorse on the saved list, in its order, and the symbol of
/// the most urgent state among them (main window design, section 7.2). `BoardModel.build` makes it from
/// the checks the menu already runs; nothing here runs a check or an action.
public struct Board: Sendable, Equatable {
    public var workhorses: [BoardWorkhorse]
    public var symbol: String

    public init(workhorses: [BoardWorkhorse], symbol: String) {
        self.workhorses = workhorses
        self.symbol = symbol
    }
}

/// One workhorse on the board: the menu's words for its state, its desks, and its buttons.
public struct BoardWorkhorse: Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    /// What its last check found; nil when it has never answered.
    public var state: WorkhorseState?
    /// The symbol the menu's icon uses for that state.
    public var symbol: String
    /// The menu's headline, for example "Attic · Ready".
    public var headline: String
    /// The menu's hint under the headline, if the state has one.
    public var hint: String?
    /// When the result shown was checked; nil when it has never answered.
    public var checkedAt: Date?
    /// A check is running now. The board keeps showing the last result meanwhile.
    public var isChecking: Bool
    /// Shown as "Waiting for the desk server" (issue #88), as the menu does.
    public var isWaitingForDeskServer: Bool
    /// The menu's summary line, for a Ready workhorse with a report.
    public var summary: String?
    /// Whether this Mac can reach its home address; for a Ready workhorse whose home address is known.
    public var homeReachable: Bool?
    /// The desks of a Ready workhorse, in name order, closed permanent desks among them. Empty otherwise.
    public var desks: [BoardDesk]
    /// The desks that ended (a later step fills them; empty for now).
    public var ended: [EndedDesk]
    /// For a workhorse that is not Ready: the desks of its last Ready check, greyed, with no buttons.
    /// nil when it is Ready, or when no check has found it Ready since MacMosh started.
    public var lastReadyDesks: [BoardDesk]?
    /// When that last Ready check was.
    public var lastReadyAt: Date?
    /// Every button but the desks' own, in the menu's order, with the window's own among them.
    public var buttons: [BoardButton]
    /// What the last action on it said, if any.
    public var result: String?
    /// The workhorse script's version in its last report; nil without one. The window hides a control that
    /// needs a newer script (main window design, section 7.2).
    public var scriptVersion: String?
    /// The state's word and tone beside the name in the window's header (look design 6.3): the headline's words after
    /// the name, never cut from it (`StatePill.of(_:state:)`).
    public var pill: StatePill
    /// Whether the last action worked, beside `result`; nil without a result.
    public var resultKind: ResultKind?

    public init(id: String, name: String, state: WorkhorseState?, symbol: String, headline: String, hint: String?,
                checkedAt: Date?, isChecking: Bool, isWaitingForDeskServer: Bool, summary: String?,
                homeReachable: Bool?, desks: [BoardDesk], ended: [EndedDesk], lastReadyDesks: [BoardDesk]?,
                lastReadyAt: Date?, buttons: [BoardButton], result: String?, scriptVersion: String? = nil,
                pill: StatePill, resultKind: ResultKind? = nil) {
        self.id = id
        self.name = name
        self.state = state
        self.symbol = symbol
        self.headline = headline
        self.hint = hint
        self.checkedAt = checkedAt
        self.isChecking = isChecking
        self.isWaitingForDeskServer = isWaitingForDeskServer
        self.summary = summary
        self.homeReachable = homeReachable
        self.desks = desks
        self.ended = ended
        self.lastReadyDesks = lastReadyDesks
        self.lastReadyAt = lastReadyAt
        self.buttons = buttons
        self.result = result
        self.scriptVersion = scriptVersion
        self.pill = pill
        self.resultKind = resultKind
    }
}

/// One tmux window of a desk: its name always, its id and the number of tabs showing it only when the
/// report has them (script 0.7.0 and newer). Nothing may depend on their being there.
public struct BoardWindow: Sendable, Equatable {
    public var index: Int
    public var name: String
    /// tmux's window id, `@` and digits.
    public var id: String?
    public var tabs: Int?
    /// How many tabs show this window, counted as the menu counts them (`DeskWindows.tabsByWindow`): set only for a
    /// desk past the menu's gate (`WindowLinesGate`); nil otherwise (an older script, the Tabs connection), when the
    /// desk tile falls back on the desk's tab count (`DeskCells`).
    public var inTabs: Int?
    /// The menu's line for this window, its words ("claude (in a tab)", "vim") and its action (go to its tab,
    /// or open one), when the desk is past the menu's gate and has more than one window (issue #134); nil
    /// otherwise, as the menu then has no such line.
    public var button: BoardButton?
    /// "Name…", which opens the window's sheet for naming this window (issue 144): for each window with an id of
    /// a desk with more than one window, past `WindowNameGate`; nil otherwise (a desk with one window has "Name its
    /// window…" in its strip instead).
    public var nameButton: BoardButton?

    public init(index: Int, name: String, id: String?, tabs: Int?, inTabs: Int? = nil, button: BoardButton? = nil,
                nameButton: BoardButton? = nil) {
        self.index = index
        self.name = name
        self.id = id
        self.tabs = tabs
        self.inTabs = inTabs
        self.button = button
        self.nameButton = nameButton
    }
}

/// One desk on the board. Folder, command and flags come from its saved definition; a desk with none
/// (made by hand with tmux) has them all nil and `madeByMacMosh` false.
public struct BoardDesk: Sendable, Equatable {
    public var name: String
    /// It has a session now. A closed desk is a permanent one whose last shell exited.
    public var isOpen: Bool
    public var windows: [BoardWindow]
    /// The report's count of its windows; 0 when closed.
    public var windowCount: Int
    /// How many terminal tabs show it; 0 when closed. Past the menu's gate, the tabs on its windows, counted
    /// as the menu counts them (`DeskWindows.tabs`); otherwise the tabs the report says are attached.
    public var tabsOpen: Int
    /// Shown the short way (`BoardModel.shortFolder`).
    public var folder: String?
    /// The startup command; nil for a plain shell or no definition.
    public var command: String?
    /// Comes back after a restart.
    public var reopen: Bool?
    /// Keeps its command running ("kept running").
    public var keep: Bool?
    /// Stays, closed, after its last shell exits.
    public var permanent: Bool?
    public var madeByMacMosh: Bool
    /// What the desk's Open button does: the menu's click on that desk, with its words (`Go to <desk>`, `Open the
    /// 1 window not in a tab`, `Open <desk>`, …). nil in the greyed list.
    public var open: BoardButton?
    /// New window (when open; in a tab of its own past the menu's gate, as the menu's), Rename…, Remove…; none in
    /// the greyed list.
    public var buttons: [BoardButton]

    /// The window names that are not empty, in window order.
    public var windowNames: [String] { windows.map(\.name).filter { !$0.isEmpty } }

    public init(name: String, isOpen: Bool, windows: [BoardWindow], windowCount: Int, tabsOpen: Int,
                folder: String?, command: String?, reopen: Bool?, keep: Bool?, permanent: Bool?,
                madeByMacMosh: Bool, open: BoardButton?, buttons: [BoardButton]) {
        self.name = name
        self.isOpen = isOpen
        self.windows = windows
        self.windowCount = windowCount
        self.tabsOpen = tabsOpen
        self.folder = folder
        self.command = command
        self.reopen = reopen
        self.keep = keep
        self.permanent = permanent
        self.madeByMacMosh = madeByMacMosh
        self.open = open
        self.buttons = buttons
    }
}

/// A desk whose last shell exited and that the workhorse removed (section 7.1 C). `EndedDeskTracker` makes
/// these; the board only shows them. It keeps every flag, so Start again can pass them back.
public struct EndedDesk: Sendable, Equatable {
    public var name: String
    /// In full, as the definition saved it.
    public var folder: String
    public var command: String?
    public var reopen: Bool
    public var keep: Bool
    /// When a check first found it gone.
    public var endedAt: Date
    /// When a check last found it open; nil when not known. Far from `endedAt` (the Mac asleep, the workhorse
    /// locked), the row says it ended between the two.
    public var lastSeenAt: Date?
    /// Why the last Start again on it didn't work, in one line; nil when none failed.
    public var problem: String?
    /// Set by `BoardModel.build`: the folder shown the short way.
    public var shownFolder: String
    /// Set by `BoardModel.build`: Start again, Start again and keep it, Forget.
    public var buttons: [BoardButton]
    /// Set by `BoardModel.build`: why Start again is off, when the name is taken again by the script's rule
    /// ("Attic already has a desk called recipes."); nil otherwise.
    public var taken: String?

    public init(name: String, folder: String, command: String?, reopen: Bool, keep: Bool, endedAt: Date,
                lastSeenAt: Date? = nil) {
        self.name = name
        self.folder = folder
        self.command = command
        self.reopen = reopen
        self.keep = keep
        self.endedAt = endedAt
        self.lastSeenAt = lastSeenAt
        self.problem = nil
        self.shownFolder = folder
        self.buttons = []
        self.taken = nil
    }
}

/// One button in the window: its title, a line under it if it needs one, and what it does.
public struct BoardButton: Sendable, Equatable {
    public var title: String
    public var note: String?
    public var action: BoardAction
    /// Off while an action on its desk runs, or while a New desk is being made (main window design, 7.2).
    public var isEnabled: Bool

    public init(title: String, note: String? = nil, action: BoardAction, isEnabled: Bool = true) {
        self.title = title
        self.note = note
        self.action = action
        self.isEnabled = isEnabled
    }

    /// A button of the menu's (`ButtonRules`), with its title and its action as the window takes it.
    init(_ button: ActionButton) {
        self.init(title: button.title, action: BoardAction(button.action))
    }
}

/// What a window button does: the menu's own action, run through `MenuRefresher.perform` as the menu's
/// line is, or one of the window's own actions.
public enum BoardAction: Sendable, Equatable {
    case menu(MenuAction)
    case window(WindowAction)

    /// The menu's action, except for the three the window does in place of a terminal tab (main
    /// window design, section 7.3): `desk new` is the window's New desk form, `desk rename` its Rename
    /// form, and `desk remove --ask` its Remove confirmation.
    public init(_ action: MenuAction) {
        switch action {
        case .tab(let args) where args.count == 3 && args[0] == "desk" && args[1] == "new":
            self = .window(.newDesk(workhorse: args[2]))
        case .tab(let args) where args.count == 4 && args[0] == "desk" && args[1] == "rename":
            self = .window(.rename(workhorse: args[2], desk: args[3]))
        case .tab(let args) where args.count == 5 && args[0] == "desk" && args[1] == "remove" && args[4] == "--ask":
            self = .window(.remove(workhorse: args[2], desk: args[3]))
        default:
            self = .menu(action)
        }
    }
}

/// The window's own actions (main window design, section 7.2). New desk, Rename and Remove open the window's
/// forms (step 4); the ended desks' come in step 5.
public enum WindowAction: Sendable, Equatable {
    /// The New desk form.
    case newDesk(workhorse: String)
    /// The Rename form.
    case rename(workhorse: String, desk: String)
    /// The Remove confirmation.
    case remove(workhorse: String, desk: String)
    /// Makes an ended desk again as it was; with `keepIt`, permanent from then on.
    case startAgain(workhorse: String, desk: String, keepIt: Bool)
    /// Takes an ended desk off the list.
    case forget(workhorse: String, desk: String)
    /// The sheet that names one window of a desk, by the window's id (issue 144).
    case nameWindow(workhorse: String, desk: String, window: String)
    /// Opens these tabs, one after another: a tab on each window no tab shows, on every running desk, and a
    /// plain tab on a desk with none that is not past the menu's gate (section 7.1 A, issue #134). Each is a
    /// list of `macmosh` arguments.
    case openAllWithoutTab(workhorse: String, tabs: [[String]])
}
