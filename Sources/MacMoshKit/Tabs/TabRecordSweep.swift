import Foundation

/// Which tab records to clear after a check (menu design 8.2, issue #120). Pure: the records, the reports,
/// the liveness check and the time are given; `MenuRefresher` reads the records and removes the files.
///
/// Only a workhorse whose check came back with a report (a good report) clears anything, and only its own
/// records. Of those it clears each one whose process is not live, and each one whose label has been on no
/// view line of its good reports for more than `unseenFor` since the record was opened or last seen on one.
/// A workhorse with no good report this time clears nothing, however long its records have gone unseen.
///
/// "Last seen" is kept in memory only, so after the app starts again a record counts from its opening.
public struct TabRecordSweep: Sendable, Equatable {
    /// How long a live record may go unseen on its workhorse's good reports. The same two minutes a record not
    /// yet on a view line still counts for its window (`DeskTabs.freshFor`).
    public static let unseenFor: TimeInterval = DeskTabs.freshFor

    /// When each label was last on a view line of its workhorse's good report.
    private var lastSeen: [String: Date] = [:]

    public init() {}

    /// The labels on the view lines of each good report, by workhorse id: the `.checked` results that carry a
    /// status. A workhorse listed twice gets the labels of both.
    public static func reports(_ gathered: [Gathered]) -> [String: Set<String>] {
        var reports: [String: Set<String>] = [:]
        for case .checked(let result) in gathered {
            guard let status = result.status else { continue }
            let labels = status.desks.flatMap(\.views).compactMap(\.label)
            reports[result.workhorse.id, default: []].formUnion(labels)
        }
        return reports
    }

    /// The labels of `records` to clear, in the order given, after these good reports. The distance from the
    /// opening or last sighting counts either way, in case the clock moved back, as `DeskTabs` does.
    public mutating func clear(_ records: [TabRecord], reports: [String: Set<String>],
                               isLive: (TabRecord) -> Bool, now: Date) -> [String] {
        var cleared: [String] = []
        for record in records {
            guard let seen = reports[record.workhorse] else { continue }
            if !isLive(record) {
                cleared.append(record.label)
            } else if seen.contains(record.label) {
                lastSeen[record.label] = now
            } else {
                let since = max(record.openedAt, lastSeen[record.label] ?? record.openedAt)
                if abs(now.timeIntervalSince(since)) > Self.unseenFor { cleared.append(record.label) }
            }
        }
        let kept = Set(records.map(\.label)).subtracting(cleared)
        lastSeen = lastSeen.filter { kept.contains($0.key) }
        return cleared
    }
}
