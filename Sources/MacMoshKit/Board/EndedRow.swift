import Foundation

/// One ended desk under a workhorse's desks (main window design, section 7.1 C), laid out from the board: its
/// name, when it ended, its folder and startup command, and its three buttons, with why they are off.
///
///     recipes    ended about 15:10
///                ~/Development/recipes · started with claude
///                [Start again]  [Start again and keep it]  [Forget]
public struct EndedRow: Sendable, Equatable, Identifiable {
    public var id: String { name }
    public var name: String
    /// "ended about 15:10", with the day when it was not today, or "ended between 23:02 and 07:13" after a long gap.
    public var when: String
    /// The folder the short way, then " · started with <command>" when it had one. One line: a long command is cut
    /// on screen by the view, never in what Start again sends.
    public var second: String
    /// Start again, Start again and keep it (script 0.5.0 or newer), Forget.
    public var buttons: [BoardButton]
    /// Why Start again is off (the name is taken again), or why the last Start again didn't work; one line.
    public var note: String?

    /// Its tile: one hollow cell, as a closed desk's (look design 6.7).
    public static let cells = DeskCells(cells: [.hollow], more: false)
    /// Start again and Start again and keep it at the left, Forget alone at the right (look design 6.7).
    public var split: ButtonSplit { ButtonSplit(buttons, apart: .destructive) }

    /// The group's heading.
    public static let heading = "Ended"
    public static let startAgain = "Start again"
    public static let startAgainAndKeepIt = "Start again and keep it"
    public static let forget = "Forget"
    /// Start again's title while it runs.
    public static let starting = "Starting…"
    /// Never on screen: Forget takes the line away at once.
    public static let forgetting = "Forgetting…"
    /// Beside Start again and keep it, or under the buttons when the row has no room (issue 156 item 2, look design 7).
    public static let keptMeans = "Kept: the desk stays, closed, when its last shell exits."

    /// What keep it means, while the row has Start again and keep it (script 0.5.0 or newer); nil otherwise.
    public var keepHelp: String? {
        let hasKeepIt = buttons.contains { b in
            if case .window(.startAgain(_, _, let keepIt)) = b.action { return keepIt }
            return false
        }
        return hasKeepIt ? Self.keptMeans : nil
    }

    /// `activity` turns the three buttons off while an action for that name runs (one per desk name at a time);
    /// without `canKeep` (a script older than 0.5.0) there is no Start again and keep it.
    public init(_ desk: EndedDesk, now: Date, timeZone: TimeZone, activity: WindowActivity = WindowActivity(),
                canKeep: Bool = true) {
        name = desk.name
        when = Self.when(desk.endedAt, lastSeen: desk.lastSeenAt, now: now, timeZone: timeZone)
        second = Self.second(folder: desk.shownFolder, command: desk.command)
        note = desk.taken ?? desk.problem
        let running = activity.busy[desk.name]
        buttons = desk.buttons.compactMap { b in
            var b = b
            guard case .window(let action) = b.action else { return b }
            switch action {
            case .startAgain(_, _, let keepIt):
                if keepIt && !canKeep { return nil }
                if desk.taken != nil { b.isEnabled = false }
                if running == .startAgain && !keepIt { b.title = Self.starting }
            default:
                break
            }
            if running != nil { b.isEnabled = false }
            return b
        }
    }

    /// Longer than the slowest poll (5 minutes) and a little: the desk ended somewhere between the last check that
    /// found it open and the one that missed it, and the row says so.
    public static let longGap: TimeInterval = 6 * 60

    /// "ended about 15:10" today, "ended yesterday about 15:10", "ended on 3 Jan about 15:10", and with the year
    /// when it is not this one. When `lastSeen` (the last check that found it open) is more than `longGap` before
    /// `date` (the check that missed it): "ended between 23:02 and 07:13", each time with its day when it was not
    /// today ("ended between yesterday 23:02 and 07:13"). Times in `timeZone`.
    public static func when(_ date: Date, lastSeen: Date? = nil, now: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        func format(_ d: Date, _ pattern: String) -> String {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = timeZone
            f.dateFormat = pattern
            return f.string(from: d)
        }
        /// nil today, "yesterday", or "3 Jan" (with the year when it is not this one).
        func day(_ d: Date) -> String? {
            if calendar.isDate(d, inSameDayAs: now) || d > now { return nil }
            if let before = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(d, inSameDayAs: before) {
                return "yesterday"
            }
            return calendar.component(.year, from: d) == calendar.component(.year, from: now)
                ? format(d, "d MMM") : format(d, "d MMM yyyy")
        }
        if let lastSeen, date.timeIntervalSince(lastSeen) > longGap {
            let both = [lastSeen, date].map { d in [day(d), format(d, "HH:mm")].compactMap { $0 }.joined(separator: " ") }
            return "ended between \(both[0]) and \(both[1])"
        }
        let time = "about " + format(date, "HH:mm")
        switch day(date) {
        case nil: return "ended " + time
        case "yesterday": return "ended yesterday " + time
        case let d?: return "ended on \(d) \(time)"
        }
    }

    /// "~/Development/recipes · started with claude", or the folder alone.
    static func second(folder: String, command: String?) -> String {
        guard let command, !command.isEmpty else { return folder }
        return folder + " · started with " + command
    }
}
