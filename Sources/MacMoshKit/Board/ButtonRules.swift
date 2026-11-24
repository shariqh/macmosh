import Foundation

/// One button the menu shows as a line, and the window (later) as a button: what it says and what
/// clicking it does. `key` is a short fixed word, different for each button of one workhorse or of
/// one desk; the menu builds its lines' ids from it.
public struct ActionButton: Sendable, Equatable {
    public var key: String
    public var title: String
    public var action: MenuAction

    public init(key: String, title: String, action: MenuAction) {
        self.key = key
        self.title = title
        self.action = action
    }
}

/// Which buttons go with which state, and which desks a Ready workhorse shows. The menu (`MenuModel`)
/// and the window's board (`BoardModel`) both read these rules, through `WorkhorseBlock`, so the two
/// can't drift apart (main window design, section 7.2). Every argument is a workhorse id or a desk
/// name, both plain words.
public enum ButtonRules {
    /// The button right under a workhorse's hint, if its state has one: Fix… when sign-ins are off,
    /// Log in…, Unlock disk… (only on a Mac that can be unlocked over ssh), Pair… or Finish setting up….
    public static func forState(_ r: CheckResult) -> [ActionButton] {
        let id = r.workhorse.id
        switch r.state {
        case .ready(let signIns):
            return signIns ? [] : [ActionButton(key: "fix", title: "Fix…",
                                                action: .tab(["prepare", id, "--restart-desk-server", "--pause"]))]
        case .waitingForLogin:
            return [ActionButton(key: "login", title: "Log in…  (opens Screen Sharing)", action: .run(["screen", id]))]
        case .locked:
            guard r.workhorse.canUnlockOverSSH else { return [] }
            return [ActionButton(key: "unlock", title: "Unlock disk…  (you type the Mac's password)",
                                 action: .tab(["unlock", id]))]
        case .cantVerify, .cantReach:
            return []
        case .notSetUp(let problem):
            if problem == .notPaired {
                return [ActionButton(key: "pair", title: "Pair…", action: .tab(["pair", id]))]
            }
            return [ActionButton(key: "finish", title: "Finish setting up…", action: .tab(["prepare", id, "--fix", "--pause"]))]
        }
    }

    /// Every button a Ready workhorse has besides its desks', in the menu's order (issue #107): New desk…,
    /// then the headline's submenu (Share screen, a laptop's lid-closed switch, Restart…). None in any
    /// other state. The order both faces use is `WorkhorseBlock.buttons`; a test holds this list to it.
    public static func forReady(_ r: CheckResult) -> [ActionButton] {
        guard case .ready = r.state else { return [] }
        return [newDesk(r.workhorse.id)] + forHeadline(r)
    }

    /// The buttons in a Ready workhorse's own submenu (issue #107): Share screen, on a laptop the
    /// lid-closed switch, and Restart…. None in any other state.
    public static func forHeadline(_ r: CheckResult) -> [ActionButton] {
        guard case .ready = r.state else { return [] }
        let id = r.workhorse.id
        return [share(id)] + (lid(r).map { [$0] } ?? []) + [restart(id)]
    }

    public static func newDesk(_ id: String) -> ActionButton {
        ActionButton(key: "newDesk", title: "New desk…", action: .tab(["desk", "new", id]))
    }

    private static func share(_ id: String) -> ActionButton {
        ActionButton(key: "share", title: "Share screen", action: .run(["screen", id]))
    }

    private static func restart(_ id: String) -> ActionButton {
        ActionButton(key: "restart", title: "Restart…", action: .tab(["restart", id]))
    }

    /// A laptop's lid-closed switch, offering the opposite of how the setting is now; nil on a Mac with no battery.
    private static func lid(_ r: CheckResult) -> ActionButton? {
        guard let status = r.status, status.isLaptop else { return nil }
        let id = r.workhorse.id
        if status.power.disableSleep == 1 {
            return ActionButton(key: "lid", title: "Turn off lid-closed mode…", action: .tab(["power", id, "lid", "off"]))
        }
        return ActionButton(key: "lid", title: "Turn on lid-closed mode…", action: .tab(["power", id, "lid", "on"]))
    }

    /// What clicking a desk does: open a tab attached to it. A closed permanent desk is made again.
    public static func connect(workhorse id: String, desk name: String) -> MenuAction {
        .tab(["connect", id, name])
    }

    /// The buttons of one desk: Open (what a click on the desk's row does too), New window for an open
    /// desk (a closed one has none to add to), Rename… and Remove…, which open a tab that asks first.
    public static func forDesk(workhorse id: String, desk name: String, isOpen: Bool) -> [ActionButton] {
        var buttons = [ActionButton(key: "open", title: "Open \(name)", action: connect(workhorse: id, desk: name))]
        if isOpen {
            buttons.append(ActionButton(key: "window", title: "New window", action: .run(["desk", "window", id, name])))
        }
        buttons.append(ActionButton(key: "rename", title: "Rename \(name)…", action: .tab(["desk", "rename", id, name])))
        buttons.append(ActionButton(key: "remove", title: "Remove \(name)…", action: .tab(["desk", "remove", id, name, "--ask"])))
        return buttons
    }

    /// Which desks a Ready workhorse shows, in the menu's order: every open desk as the report lists it,
    /// then each permanent desk whose session is gone, closed (connect makes it again). Any other
    /// definition with no session is a leftover the workhorse clears up, so it gets nothing. A session
    /// with no definition (a desk made by hand with tmux) is there, with no definition. The menu's
    /// lines and the window's rows both come from this list (main window design, section 7.2).
    ///
    /// With `tabs` (the menu gives them; the window's board doesn't), each desk past `WindowLinesGate` also gets
    /// its line per window (`DeskLine.windows`), joined with this Mac's records at `now`. Its `buttons` stay
    /// the same either way.
    public static func desks(_ r: CheckResult, tabs: TabsOnThisMac? = nil, now: Date = Date()) -> [DeskLine] {
        let id = r.workhorse.id
        let definitions = r.status?.definitions ?? []
        let sessions = r.status?.desks ?? []
        let kept = Set(definitions.filter(\.keep).map(\.name.value))
        let permanent = Set(definitions.filter(\.permanent).map(\.name.value))
        func definition(_ name: String) -> HostStatus.Definition? { definitions.first { $0.name.value == name } }
        var lines = sessions.map { session in
            let name = session.name.value
            return DeskLine(name: name, session: session, definition: definition(name), isKept: kept.contains(name),
                            isPermanent: permanent.contains(name),
                            buttons: forDesk(workhorse: id, desk: name, isOpen: true))
        }
        let open = Set(sessions.map(\.name.value))
        for closed in definitions where closed.permanent && !open.contains(closed.name.value) {
            let name = closed.name.value
            lines.append(DeskLine(name: name, session: nil, definition: closed, isKept: kept.contains(name),
                                  isPermanent: true, buttons: forDesk(workhorse: id, desk: name, isOpen: false)))
        }
        guard let tabs else { return lines }
        return lines.map { line in
            var line = line
            if WindowLinesGate.passes(r, desk: line.session, terminal: tabs.terminal) {
                line.windows = DeskWindows.of(line, workhorse: id, records: tabs.records, now: now)
            }
            return line
        }
    }

    /// Every workhorse's last button, in every state.
    public static func checklist(_ id: String) -> ActionButton {
        ActionButton(key: "checklist", title: "Run the checklist…", action: .tab(["prepare", id, "--pause"]))
    }

    public static let addAMac = ActionButton(key: "add", title: "Add a Mac…", action: .tab(["pair"]))
    public static let checkNow = ActionButton(key: "check", title: "Check now", action: .refresh)
}

/// One desk of a Ready workhorse, as `ButtonRules.desks` gives it: its session from the report (nil
/// when it is closed), its saved definition (nil for a desk made by hand), and its buttons.
public struct DeskLine: Sendable, Equatable {
    public var name: String
    public var session: HostStatus.Desk?
    public var definition: HostStatus.Definition?
    /// A definition with this name has the keep-running flag.
    public var isKept: Bool
    /// A definition with this name is permanent.
    public var isPermanent: Bool
    /// `ButtonRules.forDesk`: Open, New window when open, Rename…, Remove…. The window's board shows these.
    public var buttons: [ActionButton]
    /// The menu's line per window (issue #124): set only when the menu's tabs were given and the desk is past
    /// `WindowLinesGate`. The menu then draws its row, first line, window lines, New window and flags from
    /// this, and Rename… and Remove… from `buttons`.
    public var windows: DeskWindows?

    public var isOpen: Bool { session != nil }

    public init(name: String, session: HostStatus.Desk?, definition: HostStatus.Definition?, isKept: Bool,
                isPermanent: Bool, buttons: [ActionButton], windows: DeskWindows? = nil) {
        self.name = name
        self.session = session
        self.definition = definition
        self.isKept = isKept
        self.isPermanent = isPermanent
        self.buttons = buttons
        self.windows = windows
    }
}
