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
    /// "ended about 15:10", with the day when it was not today.
    public var when: String
    /// The folder the short way, then " · started with <command>" when it had one. One line: a long command is cut
    /// on screen by the view, never in what Start again sends.
    public var second: String
    /// Start again, Start again and keep it (script 0.5.0 or newer), Forget.
    public var buttons: [BoardButton]
    /// Why Start again is off (the name is taken again), or why the last Start again didn't work; one line.
    public var note: String?

    /// The group's heading.
    public static let heading = "Ended"
    public static let startAgain = "Start again"
    public static let startAgainAndKeepIt = "Start again and keep it"
    public static let forget = "Forget"
    /// Start again's title while it runs.
    public static let starting = "Starting…"
    /// Never on screen: Forget takes the line away at once.
    public static let forgetting = "Forgetting…"

    /// `activity` turns the three buttons off while an action for that name runs (one per desk name at a time);
    /// without `canKeep` (a script older than 0.5.0) there is no Start again and keep it.
    public init(_ desk: EndedDesk, now: Date, timeZone: TimeZone, activity: WindowActivity = WindowActivity(),
                canKeep: Bool = true) {
        name = desk.name
        when = Self.when(desk.endedAt, now: now, timeZone: timeZone)
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

    /// "ended about 15:10" today, "ended yesterday about 15:10", "ended on 3 Jan about 15:10", and with the year
    /// when it is not this one. Times in `timeZone`.
    public static func when(_ date: Date, now: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        func format(_ pattern: String) -> String {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = timeZone
            f.dateFormat = pattern
            return f.string(from: date)
        }
        let time = "about " + format("HH:mm")
        if calendar.isDate(date, inSameDayAs: now) || date > now { return "ended " + time }
        if let before = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: before) {
            return "ended yesterday " + time
        }
        let day = calendar.component(.year, from: date) == calendar.component(.year, from: now)
            ? format("d MMM") : format("d MMM yyyy")
        return "ended on \(day) \(time)"
    }

    /// "~/Development/recipes · started with claude", or the folder alone.
    static func second(folder: String, command: String?) -> String {
        guard let command, !command.isEmpty else { return folder }
        return folder + " · started with " + command
    }
}
