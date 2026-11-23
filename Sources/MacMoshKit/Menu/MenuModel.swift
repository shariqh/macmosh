import Foundation

/// What clicking a menu line does. The arguments are for the `macmosh` command.
public enum MenuAction: Sendable, Equatable {
    case tab([String])               // macmosh arguments to run in a new terminal tab
    case run([String])               // macmosh arguments to run in the background, then check again
    case refresh
    case none
}

public struct MenuItem: Sendable, Equatable {
    public var title: String
    public var action: MenuAction
    public var indent: Int
    public var isSeparator: Bool

    public init(title: String, action: MenuAction, indent: Int, isSeparator: Bool) {
        self.title = title
        self.action = action
        self.indent = indent
        self.isSeparator = isSeparator
    }

    static func line(_ title: String, _ action: MenuAction = .none, indent: Int = 1) -> MenuItem {
        MenuItem(title: title, action: action, indent: indent, isSeparator: false)
    }

    static func line(_ button: ActionButton, indent: Int = 1) -> MenuItem {
        line(button.title, button.action, indent: indent)
    }

    static let separator = MenuItem(title: "", action: .none, indent: 0, isSeparator: true)
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

/// The menu as a list of lines, from what the checks found. Built for the native
/// menu-bar app. Wording that exists already comes from `StatusFormat`.
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
            return MenuLines(symbol: noWorkhorsesSymbol, items: [
                .line("No workhorses yet", indent: 0),
                .line(ButtonRules.addAMac, indent: 0),
            ])
        }

        var items: [MenuItem] = []
        var states: [WorkhorseState] = []
        for (i, entry) in gathered.enumerated() {
            if i > 0 { items.append(.separator) }
            switch entry {
            case .checked(let result):
                if waitingForDeskServer.contains(result.workhorse.id), result.state == .notSetUp(.deskServerDown) {
                    items += deskServerWaitBlock(result)
                } else {
                    states.append(result.state)
                    items += block(for: result, now: now, timeZone: timeZone)
                }
            case .stillChecking(let w):
                items.append(.line("\(w.name) · Still checking…", indent: 0))
                items.append(.line(ButtonRules.checklist(w.id)))
            }
        }
        items.append(.separator)
        items.append(.line(ButtonRules.addAMac, indent: 0))
        items.append(.line(ButtonRules.checkNow, indent: 0))
        let symbol = mostUrgent(states).map(symbol(for:)) ?? stillCheckingSymbol
        return MenuLines(symbol: symbol, items: items)
    }

    // MARK: One workhorse

    /// Under "Waiting for the desk server". Every clause is true when it is shown (issue #88).
    static let waitingForDeskServerHint = "Someone has logged in and the desk server isn't running yet. MacMosh's login agent starts it after a login; if it still isn't running in a minute, this menu says so."

    /// A headline, the hint, and the checklist. No "Finish setting up…": the login agent is about to do it.
    private static func deskServerWaitBlock(_ r: CheckResult) -> [MenuItem] {
        [.line("\(r.workhorse.name) · Waiting for the desk server", indent: 0),
         .line(waitingForDeskServerHint),
         .line(ButtonRules.checklist(r.workhorse.id))]
    }

    /// The headline, the hint (a Ready workhorse with sign-ins working has none), the state's own
    /// button, a Ready workhorse's desks and buttons, and the checklist.
    private static func block(for r: CheckResult, now: Date, timeZone: TimeZone) -> [MenuItem] {
        var items: [MenuItem] = [.line(StatusFormat.headline(r), indent: 0)]
        if let hint = StatusFormat.hint(r, now: now, timeZone: timeZone) { items.append(.line(hint)) }
        items += ButtonRules.forState(r).map { .line($0) }
        if case .ready = r.state { items += readyItems(r) }
        items.append(.line(ButtonRules.checklist(r.workhorse.id)))
        return items
    }

    /// Desks, the buttons (a laptop's lid-closed switch among them), the summary line and the home-address light.
    private static func readyItems(_ r: CheckResult) -> [MenuItem] {
        let id = r.workhorse.id
        var items: [MenuItem] = []
        let definitions = r.status?.definitions ?? []
        let desks = r.status?.desks ?? []
        let kept = Set(definitions.filter(\.keep).map(\.name.value))
        let permanent = Set(definitions.filter(\.permanent).map(\.name.value))
        for desk in desks {
            let name = desk.name.value
            items.append(.line(deskTitle(desk, kept: kept.contains(name), permanent: permanent.contains(name)),
                               ButtonRules.connect(workhorse: id, desk: name)))
            items += ButtonRules.forDesk(workhorse: id, desk: name, isOpen: true).map { .line($0, indent: 2) }
        }
        // A permanent desk whose last shell exited stays, closed; connect makes it again. Any other
        // definition with no desk is a leftover the workhorse clears up, so it gets no line.
        let open = Set(desks.map(\.name.value))
        for definition in definitions where definition.permanent && !open.contains(definition.name.value) {
            let name = definition.name.value
            items.append(.line("\(name) (closed)", ButtonRules.connect(workhorse: id, desk: name)))
            items += ButtonRules.forDesk(workhorse: id, desk: name, isOpen: false).map { .line($0, indent: 2) }
        }
        items += ButtonRules.forReady(r).map { .line($0) }
        if let status = r.status { items.append(.line(StatusFormat.summaryLine(status))) }
        if let reachable = r.homeReachable {
            items.append(.line("Home address reachable from here: \(reachable ? "yes" : "no")"))
        }
        return items
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
