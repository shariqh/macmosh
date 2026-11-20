import Foundation

/// How often the app checks in the background (design 7.4): every 30 seconds while every workhorse
/// answers, and less often while one can't be reached.
public enum PollSchedule {
    /// How long to wait before the next background check.
    /// `missesInARow` counts the checks in a row in which some workhorse was Can't reach it.
    public static func delay(missesInARow: Int) -> Duration {
        switch missesInARow {
        case ...1: return .seconds(30)
        case 2: return .seconds(60)
        case 3: return .seconds(120)
        default: return .seconds(300)
        }
    }

    /// True when some workhorse that has answered (or failed to) is Can't reach it.
    /// A workhorse that is still being checked is not a miss yet.
    public static func isMiss(_ gathered: [Gathered]) -> Bool {
        gathered.contains { item in
            if case .checked(let result) = item, case .cantReach = result.state { return true }
            return false
        }
    }
}
