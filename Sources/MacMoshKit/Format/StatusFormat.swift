import Foundation

/// The words and the JSON `macmosh status`, `list` and `desks` print. The wording is the design's
/// (5.1, 5.2, 7.4). "Now" and the time zone are parameters, so a test fixes them.
public enum StatusFormat {
    public static let noWorkhorses = "No workhorses yet. Run: macmosh pair <user@address>"

    // MARK: States

    /// A name for programs: stable, lower case, one per state.
    public static func stateName(_ s: WorkhorseState) -> String {
        switch s {
        case .ready(let signIns): return signIns ? "ready" : "ready-signins-off"
        case .waitingForLogin: return "waiting-for-login"
        case .locked: return "locked"
        case .cantVerify: return "cant-verify"
        case .cantReach: return "cant-reach"
        case .notSetUp: return "not-set-up"
        }
    }

    /// The finer reason, for programs: the unreachable reason or the setup problem. nil for the rest.
    static func reasonName(_ s: WorkhorseState) -> String? {
        switch s {
        case .cantReach(let reason): return reason.rawValue
        case .notSetUp(let problem): return problem.rawValue
        default: return nil
        }
    }

    /// What the state is called to a person.
    private static func title(_ s: WorkhorseState) -> String {
        switch s {
        case .ready(let signIns): return signIns ? "Ready" : "Ready, sign-ins off"
        case .waitingForLogin: return "Waiting for login"
        case .locked: return "Locked after a restart"
        case .cantVerify: return "Can't verify it"
        case .cantReach: return "Can't reach it"
        case .notSetUp(let problem):
            switch problem {
            case .notPaired: return "Not paired"
            case .identityUnusable: return "Your ssh key is locked"
            case .hostScriptMissing, .hostScriptOutdated: return "Needs setting up"
            case .unreadableReport: return "Couldn't read its status"
            case .deskServerDown: return "Desk server is off"
            }
        }
    }

    /// "MacBook Pro · Ready"
    public static func headline(_ r: CheckResult) -> String {
        "\(r.workhorse.name) · \(title(r.state))"
    }

    /// The plain-words line under a state that needs one. `now` and `timeZone` shape the time in
    /// "Last seen 14:02": a short time today, "yesterday 14:02", or the date when older. A workhorse
    /// that was never seen leaves that sentence out.
    public static func hint(_ r: CheckResult, now: Date = Date(), timeZone: TimeZone = .current) -> String? {
        let w = r.workhorse
        let fix = "macmosh prepare \(w.id) --fix"
        switch r.state {
        case .ready(let signIns):
            return signIns ? nil : "Tools that keep logins in the keychain look signed out here."
        case .waitingForLogin:
            return "It is on and unlocked, but nobody has logged in."
        case .locked:
            let base = "The disk is locked until someone types the Mac's password."
            return w.canUnlockOverSSH ? base : base + " Unlock it at the Mac."
        case .cantVerify:
            return "Something answers at its address with a different key. Stop. Don't type a password. Check or unlock at the Mac."
        case .cantReach(let reason):
            let seen = w.lastSeen.map { "Last seen \(shortTime($0, now: now, timeZone: timeZone)). " } ?? ""
            switch reason {
            case .tailscaleOff: return seen + "Tailscale is off on this Mac."
            case .noNetwork: return seen + "This Mac has no network."
            case .otherVPN: return seen + "Another VPN is running on this Mac."
            case .awayAndOffline:
                return seen + "Tailscale says it is offline and you are away from home. It may have restarted: its home address is out of reach from here."
            case .nothingAnswers:
                return seen + "Nothing answers at either address: it is off, asleep or disconnected. If it just restarted, its home address may have changed."
            }
        case .notSetUp(let problem):
            switch problem {
            case .notPaired: return "Run: macmosh pair \(w.id)"
            case .identityUnusable: return "MacMosh can't use \(identityPath(w))."
            case .hostScriptMissing, .hostScriptOutdated, .deskServerDown: return "Run: \(fix)"
            case .unreadableReport:
                return "It answered, but its status report was incomplete. MacMosh will try again. If this stays, run: \(fix)"
            }
        }
    }

    /// The key file, as a person would write it: `~` for the home folder.
    private static func identityPath(_ w: Workhorse) -> String {
        if let file = w.identityFile, !file.isEmpty { return file }
        return "~/.ssh/macmosh_ed25519"
    }

    /// 14:02 today, "yesterday 14:02", or the date ("3 Jan", with the year when it isn't this one).
    static func shortTime(_ date: Date, now: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        func format(_ pattern: String) -> String {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = timeZone
            f.dateFormat = pattern
            return f.string(from: date)
        }
        if calendar.isDate(date, inSameDayAs: now) || date > now { return format("HH:mm") }
        if let before = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: before) {
            return "yesterday " + format("HH:mm")
        }
        return calendar.component(.year, from: date) == calendar.component(.year, from: now)
            ? format("d MMM") : format("d MMM yyyy")
    }

    // MARK: The summary line

    /// "Sign-ins working · Awake on power · Lid-closed mode off · On power, 82%". The lid-closed part is
    /// there for a laptop only: on when the report's value is 1, off when it is 0 or not listed (the
    /// workhorse lists the setting only once it was first turned on).
    public static func summaryLine(_ s: HostStatus) -> String {
        var parts: [String] = [s.signIns == .yes ? "Sign-ins working" : "Sign-ins off"]
        parts.append(s.power.sleepOnPower == 0 ? "Awake on power" : "Sleeps on power")
        if s.isLaptop { parts.append(s.power.disableSleep == 1 ? "Lid-closed mode on" : "Lid-closed mode off") }
        if s.battery.present {
            let source = s.battery.onAC == false ? "On battery" : "On power"
            parts.append(s.battery.percent.map { "\(source), \($0)%" } ?? source)
        } else {
            parts.append("On power")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Desks

    /// One line per desk, names lined up: "website  2 windows  1 tab attached".
    public static func deskLines(_ s: HostStatus) -> [String] {
        let width = s.desks.map(\.name.value.count).max() ?? 0
        return s.desks.map { desk in
            let name = desk.name.value.padding(toLength: width, withPad: " ", startingAt: 0)
            let windows = desk.windowCount == 1 ? "1 window" : "\(desk.windowCount) windows"
            let tabs = desk.attached == 1 ? "1 tab attached" : "\(desk.attached) tabs attached"
            return "\(name)  \(windows)  \(tabs)"
        }
    }

    /// For `macmosh desks --json`: `[{"attached":1,"name":"website","windows":2}]`.
    public static func desksJSON(_ s: HostStatus) throws -> String {
        try encode(s.desks.map(DeskRow.init))
    }

    // MARK: Text

    /// For a person: a headline per workhorse, the hint under it, and for a workhorse that is Ready
    /// its desks and the summary line. A blank line between workhorses.
    public static func text(_ results: [CheckResult], now: Date = Date(), timeZone: TimeZone = .current) -> String {
        if results.isEmpty { return noWorkhorses + "\n" }
        let blocks = results.map { r -> String in
            var lines = [headline(r)]
            if let hint = hint(r, now: now, timeZone: timeZone) { lines.append("  " + hint) }
            if case .ready = r.state, let status = r.status {
                let desks = deskLines(status)
                lines += desks.isEmpty ? ["  No desks yet."] : desks.map { "  " + $0 }
                lines.append("  " + summaryLine(status))
            }
            return lines.joined(separator: "\n") + "\n"
        }
        return blocks.joined(separator: "\n")
    }

    /// For `macmosh list`: what is saved, without a check.
    public static func listText(_ list: [Workhorse]) -> String {
        if list.isEmpty { return noWorkhorses + "\n" }
        return list.map { w in
            "\(w.name) (\(w.id)) · \(w.user)@\(w.mainAddress) · \(w.paired ? "paired" : "not paired")\n"
        }.joined()
    }

    // MARK: JSON

    private struct DeskRow: Encodable {
        var name: String
        var windows: Int
        var attached: Int
        init(_ desk: HostStatus.Desk) {
            name = desk.name.value
            windows = desk.windowCount
            attached = desk.attached
        }
    }

    /// Every key is always there; a value that doesn't apply is `null`, not missing.
    private struct StatusRow: Encodable {
        var id: String
        var name: String
        var state: String
        var reason: String?
        var hint: String?
        var desks: [DeskRow]
        var homeReachable: Bool?
        var checkedAt: Date

        enum CodingKeys: String, CodingKey { case id, name, state, reason, hint, desks, homeReachable, checkedAt }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id)
            try c.encode(name, forKey: .name)
            try c.encode(state, forKey: .state)
            try c.encode(reason, forKey: .reason)
            try c.encode(hint, forKey: .hint)
            try c.encode(desks, forKey: .desks)
            try c.encode(homeReachable, forKey: .homeReachable)
            try c.encode(checkedAt, forKey: .checkedAt)
        }
    }

    private struct ListRow: Encodable {
        var id: String
        var name: String
        var user: String
        var mainAddress: String
        var homeAddress: String?
        var localName: String?
        var paired: Bool
        var mode: String
        var lastSeen: Date?

        enum CodingKeys: String, CodingKey {
            case id, name, user, mainAddress, homeAddress, localName, paired, mode, lastSeen
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id)
            try c.encode(name, forKey: .name)
            try c.encode(user, forKey: .user)
            try c.encode(mainAddress, forKey: .mainAddress)
            try c.encode(homeAddress, forKey: .homeAddress)
            try c.encode(localName, forKey: .localName)
            try c.encode(paired, forKey: .paired)
            try c.encode(mode, forKey: .mode)
            try c.encode(lastSeen, forKey: .lastSeen)
        }
    }

    /// For programs: an array with one object per workhorse, keys `id`, `name`, `state`, `reason`,
    /// `hint`, `desks` (each with `name`, `windows`, `attached`), `homeReachable` and `checkedAt`
    /// (ISO 8601, UTC). Keys are sorted, nothing is pretty-printed.
    public static func json(_ results: [CheckResult], now: Date = Date(), timeZone: TimeZone = .current) throws -> String {
        let rows = results.map { r in
            StatusRow(id: r.workhorse.id, name: r.workhorse.name, state: stateName(r.state),
                      reason: reasonName(r.state), hint: hint(r, now: now, timeZone: timeZone),
                      desks: (r.status?.desks ?? []).map(DeskRow.init), homeReachable: r.homeReachable,
                      checkedAt: r.checkedAt)
        }
        return try encode(rows)
    }

    /// For `macmosh list --json`.
    public static func listJSON(_ list: [Workhorse]) throws -> String {
        try encode(list.map { w in
            ListRow(id: w.id, name: w.name, user: w.user, mainAddress: w.mainAddress, homeAddress: w.homeAddress,
                    localName: w.localName, paired: w.paired, mode: w.mode.rawValue, lastSeen: w.lastSeen)
        })
    }

    private static func encode<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    // MARK: Messages

    /// What to tell a person when the saved list can't be read or changed.
    public static func storeMessage(_ error: Error) -> String {
        switch error {
        case StoreError.unreadable(let why): return "Can't read MacMosh's saved settings: \(why)"
        case StoreError.newerVersion(let v): return "MacMosh's saved settings are from a newer version (\(v)). Update MacMosh."
        case StoreError.ambiguous(let x): return "More than one workhorse is called \"\(x)\". Use its id: macmosh list"
        case StoreError.notFound(let x): return "No workhorse called \"\(x)\". Run: macmosh list"
        default: return "\(error)"
        }
    }
}
