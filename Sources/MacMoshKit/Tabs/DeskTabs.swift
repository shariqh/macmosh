import Foundation

/// Which terminal tabs show which windows of a desk (menu design 8.2): the report's `windowinfo` and `view`
/// lines joined with this Mac's live tab records. Pure: the records are already checked for liveness, and
/// "now" is given.
public enum DeskTabs {
    /// How long a record not yet on any `view` line still counts for the window it asked for. Without it, a
    /// second click before the next check would open a duplicate tab.
    public static let freshFor: TimeInterval = 120

    public struct WindowTabs: Sendable, Equatable {
        public var windowId: String
        public var index: Int
        /// The labels of the tabs this Mac can find on this window, oldest opened first.
        public var labels: [String]
        /// The most recently opened of them.
        public var newest: String?
        /// Tabs showing the window that this Mac can't find: the window's tab count minus `labels`, never below 0.
        public var others: Int

        public init(windowId: String, index: Int, labels: [String], newest: String?, others: Int) {
            self.windowId = windowId
            self.index = index
            self.labels = labels
            self.newest = newest
            self.others = others
        }
    }

    /// One entry per window of `desk` that has a `windowinfo` line, in the desk's order.
    ///
    /// - A window's findable tabs are `workhorse`'s records whose label is on a `view` line for that window.
    ///   The join is by label only, never by the desk's name, so a rename can't break it.
    /// - A record whose label is on no `view` line of the desk yet, whose `askedWindow` is that window and
    ///   which opened less than `freshFor` ago, counts too.
    /// - Records of another workhorse are ignored.
    public static func build(desk: HostStatus.Desk, workhorse: String, records: [TabRecord], now: Date) -> [WindowTabs] {
        let mine = records.filter { $0.workhorse == workhorse }
            .sorted { ($0.openedAt, $0.label) < ($1.openedAt, $1.label) }
        let labelsInReport = Set(desk.views.compactMap(\.label))
        return desk.windows.compactMap { window -> WindowTabs? in
            guard let id = window.id else { return nil }
            let onWindow = Set(desk.views.filter { $0.windowId == id }.compactMap(\.label))
            let found = mine.filter { record in
                if onWindow.contains(record.label) { return true }
                return !labelsInReport.contains(record.label) && record.askedWindow == id
                    && now.timeIntervalSince(record.openedAt) < freshFor
            }
            return WindowTabs(windowId: id, index: window.index, labels: found.map(\.label),
                              newest: found.last?.label, others: max(0, (window.tabs ?? 0) - found.count))
        }
    }
}
