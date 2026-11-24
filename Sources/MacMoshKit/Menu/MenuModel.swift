import Foundation

/// What clicking a menu line does. The arguments are for the `macmosh` command.
public enum MenuAction: Sendable, Equatable {
    case tab([String])               // macmosh arguments to run in a new terminal tab
    case run([String])               // macmosh arguments to run in the background, then check again
    case refresh
    case none
}

/// One line of the menu flattened (`MenuEntry.flatten`).
public struct MenuItem: Sendable, Equatable {
    public var title: String
    public var action: MenuAction
    public var indent: Int
    public var isSeparator: Bool
    /// This line is drawn as a row that opens a submenu; its action, if any, is the row's primary action.
    public var opensSubmenu: Bool
    /// This line is inside a submenu, not at the menu's top level.
    public var inSubmenu: Bool

    public init(title: String, action: MenuAction, indent: Int, isSeparator: Bool,
                opensSubmenu: Bool = false, inSubmenu: Bool = false) {
        self.title = title
        self.action = action
        self.indent = indent
        self.isSeparator = isSeparator
        self.opensSubmenu = opensSubmenu
        self.inSubmenu = inSubmenu
    }

    static func line(_ title: String, _ action: MenuAction = .none, indent: Int = 1) -> MenuItem {
        MenuItem(title: title, action: action, indent: indent, isSeparator: false)
    }

}

/// One workhorse's answer, or the news that it hadn't answered when the time ran out.
public enum Gathered: Sendable, Equatable {
    case checked(CheckResult)
    case stillChecking(Workhorse)
}

/// Words that are safe as arguments of a menu action: letters, digits and `@%+=:,./_-`. A later
/// task's `macmosh open` refuses anything else, and the menu passes them on without quoting.
public enum PlainWords {
    private static let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789@%+=:,./_-")

    public static func isPlain(_ word: String) -> Bool {
        !word.isEmpty && word.allSatisfy { allowed.contains($0) }
    }
}

/// The menu as a tree of entries, and the lines it flattens to, from what the checks found. Built
/// for the native menu-bar app. Wording that exists already comes from `StatusFormat`.
public enum MenuModel {
    /// The icon for one state. A different shape for each (design 5.1), so it reads in a monochrome menu bar.
    public static func symbol(for state: WorkhorseState) -> String {
        switch state {
        case .cantVerify: return "exclamationmark.triangle"
        case .locked: return "lock.circle"
        case .waitingForLogin: return "person.crop.circle.badge.questionmark"
        case .cantReach: return "wifi.slash"
        case .notSetUp: return "wrench.and.screwdriver"
        case .ready(let signIns): return signIns ? "checkmark.circle" : "exclamationmark.circle"
        }
    }

    /// No workhorses at all.
    static let noWorkhorsesSymbol = "plus.circle"
    /// Workhorses are listed but none has answered yet.
    static let stillCheckingSymbol = "ellipsis.circle"

    /// The state that most needs the person, in this order: Can't verify it, Locked, Waiting for
    /// login, Can't reach it, Not set up, Ready with sign-ins off, Ready. nil for no states.
    /// When two are equally urgent, the earlier one in the list wins.
    public static func mostUrgent(_ states: [WorkhorseState]) -> WorkhorseState? {
        var best: (rank: Int, state: WorkhorseState)?
        for state in states {
            let r = rank(state)
            if best == nil || r < best!.rank { best = (r, state) }
        }
        return best?.state
    }

    private static func rank(_ state: WorkhorseState) -> Int {
        switch state {
        case .cantVerify: return 0
        case .locked: return 1
        case .waitingForLogin: return 2
        case .cantReach: return 3
        case .notSetUp: return 4
        case .ready(let signIns): return signIns ? 6 : 5
        }
    }

    /// `waitingForDeskServer` names the workhorses that have just been logged in to: one of them
    /// whose desk server is down shows the wait instead of the fix, and adds nothing to the icon,
    /// as "Still checking…" adds nothing. `now` and `timeZone` shape the time in "Last seen 14:02"; a test fixes them.
    public static func build(_ gathered: [Gathered], waitingForDeskServer: Set<String> = [],
                             now: Date = Date(), timeZone: TimeZone = .current) -> MenuLines {
        if gathered.isEmpty {
            return MenuLines(symbol: noWorkhorsesSymbol, entries: [
                MenuEntry(id: "top:none", title: "No workhorses yet"),
                .button(ButtonRules.addAMac, under: "top"),
            ])
        }

        var entries: [MenuEntry] = []
        var states: [WorkhorseState] = []
        var separators = 0
        func separator() {
            separators += 1
            entries.append(.separator(id: "top:sep\(separators)"))
        }
        for (i, entry) in gathered.enumerated() {
            if i > 0 { separator() }
            switch entry {
            case .checked(let result):
                let block = WorkhorseBlock.of(result, waitingForDeskServer: waitingForDeskServer, now: now,
                                              timeZone: timeZone)
                if block.kind != .waitingForDeskServer { states.append(result.state) }
                entries.append(self.entry(for: block, workhorse: result.workhorse.id))
            case .stillChecking(let w):
                entries.append(self.entry(for: .stillChecking(w), workhorse: w.id))
            }
        }
        separator()
        entries.append(.button(ButtonRules.addAMac, under: "top"))
        entries.append(.button(ButtonRules.checkNow, under: "top"))
        return MenuLines(symbol: symbol(forAll: states), entries: entries)
    }

    /// The menu's icon for the states of the workhorses that answered (a workhorse still being checked,
    /// or waiting for its desk server, adds nothing): the most urgent one's, or "Still checking" for none.
    public static func symbol(forAll states: [WorkhorseState]) -> String {
        mostUrgent(states).map(symbol(for:)) ?? stillCheckingSymbol
    }

    // MARK: One workhorse

    /// Under "Waiting for the desk server". Every clause is true when it is shown (issue #88).
    static let waitingForDeskServerHint = WorkhorseBlock.waitingForDeskServerHint

    /// One workhorse's block (`WorkhorseBlock` decides what is in it): the headline, and under it the
    /// hint (a Ready workhorse with sign-ins working has none) and the state's own button. Every block
    /// but a Ready one then has the checklist under it, flat.
    ///
    /// A Ready headline opens a submenu of the lines used rarely (issue #107), and has its desks and
    /// New desk… under it at the top level, after the hint and Fix…: a problem is never in a submenu.
    private static func entry(for block: WorkhorseBlock, workhorse: String) -> MenuEntry {
        let id = "wh:\(workhorse)"
        var children: [MenuEntry] = []
        if let hint = block.hint {
            children.append(MenuEntry(id: "\(id):hint", title: hint))
        }
        children += block.stateButtons.map { .button($0, under: id) }
        guard block.kind == .ready else {
            children.append(.button(block.checklist, under: id))
            return MenuEntry(id: id, title: block.headline, children: children)
        }
        children += block.desks.map { deskEntry(workhorse: workhorse, $0) }
        children += block.newDesk.map { [.button($0, under: id)] } ?? []
        return MenuEntry(id: id, title: block.headline, submenu: headlineSubmenu(block, under: id),
                         children: children)
    }

    /// Share screen, a laptop's lid-closed switch, Restart…; then the summary line and the home-address
    /// light, as text; then the checklist. A separator between each group that has lines.
    private static func headlineSubmenu(_ block: WorkhorseBlock, under id: String) -> [MenuEntry] {
        var texts: [MenuEntry] = []
        if let summary = block.summary {
            texts.append(MenuEntry(id: "\(id):summary", title: summary))
        }
        if let reachable = block.homeReachable {
            texts.append(MenuEntry(id: "\(id):home", title: WorkhorseBlock.homeLine(reachable)))
        }
        let groups = [block.rareButtons.map { MenuEntry.button($0, under: id) }, texts,
                      [.button(block.checklist, under: id)]]
        return joined(groups.filter { !$0.isEmpty }, under: id)
    }

    /// The groups with a separator between each two, numbered `<id>:sep1`, `<id>:sep2`, ….
    private static func joined(_ groups: [[MenuEntry]], under id: String) -> [MenuEntry] {
        var lines: [MenuEntry] = []
        for (i, group) in groups.enumerated() {
            if i > 0 { lines.append(.separator(id: "\(id):sep\(i)")) }
            lines += group
        }
        return lines
    }

    /// A desk's row (`ButtonRules.desks` says which desks have one) opens it when clicked (its primary
    /// action), and opens its submenu when the pointer rests on it: Open <desk>, New window, then
    /// Rename… and Remove….
    private static func deskEntry(workhorse id: String, _ desk: DeskLine) -> MenuEntry {
        let deskID = "desk:\(id):\(desk.name)"
        let title = desk.session.map { deskTitle($0, kept: desk.isKept, permanent: desk.isPermanent) }
            ?? "\(desk.name) (closed)"
        let asksFirst: Set = ["rename", "remove"]
        let groups = [desk.buttons.filter { !asksFirst.contains($0.key) }, desk.buttons.filter { asksFirst.contains($0.key) }]
        return MenuEntry(id: deskID, title: title, action: ButtonRules.connect(workhorse: id, desk: desk.name),
                         submenu: joined(groups.map { $0.map { .button($0, under: deskID) } }, under: deskID))
    }

    /// `website (2 windows: zsh, vim, kept running, permanent, open in 1 tab)`
    private static func deskTitle(_ desk: HostStatus.Desk, kept: Bool, permanent: Bool) -> String {
        var inside = desk.windowCount == 1 ? "1 window" : "\(desk.windowCount) windows"
        let names = desk.windows.map(\.name).filter { !$0.isEmpty }
        if !names.isEmpty { inside += ": " + names.joined(separator: ", ") }
        if kept { inside += ", kept running" }
        if permanent { inside += ", permanent" }
        if desk.attached > 0 {
            inside += ", open in " + (desk.attached == 1 ? "1 tab" : "\(desk.attached) tabs")
        }
        return "\(desk.name.value) (\(inside))"
    }
}
