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

    static let separator = MenuItem(title: "", action: .none, indent: 0, isSeparator: true)
}

public struct Menu: Sendable, Equatable {
    public var symbol: String
    public var items: [MenuItem]

    public init(symbol: String, items: [MenuItem]) {
        self.symbol = symbol
        self.items = items
    }
}

/// One workhorse's answer, or the news that it hadn't answered when the time ran out.
public enum Gathered: Sendable, Equatable {
    case checked(CheckResult)
    case stillChecking(Workhorse)
}

/// Words that are safe as arguments of a menu action: letters, digits and `@%+=:,./_-`. A later
/// task's `macmosh open` refuses anything else, and a plugin line can't quote them.
public enum PlainWords {
    private static let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789@%+=:,./_-")

    public static func isPlain(_ word: String) -> Bool {
        !word.isEmpty && word.allSatisfy { allowed.contains($0) }
    }
}

/// The menu as a list of lines, from what the checks found. Shared by the SwiftBar prototype and
/// the native app. Wording that exists already comes from `StatusFormat`.
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

    /// `now` and `timeZone` shape the time in "Last seen 14:02"; a test fixes them.
    public static func build(_ gathered: [Gathered], now: Date = Date(), timeZone: TimeZone = .current) -> Menu {
        if gathered.isEmpty {
            return Menu(symbol: noWorkhorsesSymbol, items: [
                .line("No workhorses yet", indent: 0),
                .line("Add a Mac…", .tab(["pair"]), indent: 0),
            ])
        }

        var items: [MenuItem] = []
        var states: [WorkhorseState] = []
        for (i, entry) in gathered.enumerated() {
            if i > 0 { items.append(.separator) }
            switch entry {
            case .checked(let result):
                states.append(result.state)
                items += block(for: result, now: now, timeZone: timeZone)
            case .stillChecking(let w):
                items.append(.line("\(w.name) · Still checking…", indent: 0))
                items.append(checklist(w))
            }
        }
        items.append(.separator)
        items.append(.line("Add a Mac…", .tab(["pair"]), indent: 0))
        items.append(.line("Check now", .refresh, indent: 0))
        let symbol = mostUrgent(states).map(symbol(for:)) ?? stillCheckingSymbol
        return Menu(symbol: symbol, items: items)
    }

    // MARK: One workhorse

    private static func checklist(_ w: Workhorse) -> MenuItem {
        .line("Run the checklist…", .tab(["prepare", w.id, "--pause"]))
    }

    private static func block(for r: CheckResult, now: Date, timeZone: TimeZone) -> [MenuItem] {
        let id = r.workhorse.id
        var items: [MenuItem] = [.line(StatusFormat.headline(r), indent: 0)]
        let hint = StatusFormat.hint(r, now: now, timeZone: timeZone)

        switch r.state {
        case .ready(let signIns):
            if !signIns {
                if let hint { items.append(.line(hint)) }
                items.append(.line("Fix…", .tab(["prepare", id, "--restart-desk-server", "--pause"])))
            }
            items += readyItems(r)
        case .waitingForLogin:
            if let hint { items.append(.line(hint)) }
            items.append(.line("Log in…  (opens Screen Sharing)", .run(["screen", id])))
        case .locked:
            if let hint { items.append(.line(hint)) }
            if r.workhorse.canUnlockOverSSH {
                items.append(.line("Unlock disk…  (you type the Mac's password)", .tab(["unlock", id])))
            }
        case .cantVerify, .cantReach:
            if let hint { items.append(.line(hint)) }
        case .notSetUp(let problem):
            if let hint { items.append(.line(hint)) }
            if problem == .notPaired {
                items.append(.line("Pair…", .tab(["pair", id])))
            } else {
                items.append(.line("Finish setting up…", .tab(["prepare", id, "--fix", "--pause"])))
            }
        }
        items.append(checklist(r.workhorse))
        return items
    }

    /// Desks, the three buttons, the summary line and the home-address light.
    private static func readyItems(_ r: CheckResult) -> [MenuItem] {
        let id = r.workhorse.id
        var items: [MenuItem] = []
        for desk in r.status?.desks ?? [] {
            let name = desk.name.value
            items.append(.line(deskTitle(desk), .tab(["connect", id, name])))
            items.append(.line("New window in \(name)", .run(["desk", "window", id, name]), indent: 2))
        }
        items.append(.line("New desk…", .tab(["desk", "new", id])))
        items.append(.line("Share screen", .run(["screen", id])))
        items.append(.line("Restart…", .tab(["restart", id])))
        if let status = r.status { items.append(.line(StatusFormat.summaryLine(status))) }
        if let reachable = r.homeReachable {
            items.append(.line("Home address reachable from here: \(reachable ? "yes" : "no")"))
        }
        return items
    }

    /// `website (2 windows: zsh, vim, open in 1 tab)`
    private static func deskTitle(_ desk: HostStatus.Desk) -> String {
        var inside = desk.windowCount == 1 ? "1 window" : "\(desk.windowCount) windows"
        let names = desk.windows.map(\.name).filter { !$0.isEmpty }
        if !names.isEmpty { inside += ": " + names.joined(separator: ", ") }
        if desk.attached > 0 {
            inside += ", open in " + (desk.attached == 1 ? "1 tab" : "\(desk.attached) tabs")
        }
        return "\(desk.name.value) (\(inside))"
    }
}
