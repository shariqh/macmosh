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

    /// One entry per window of `desk` that has a `windowinfo` line (an id that is `@` and digits), in the desk's order.
    ///
    /// - A window's findable tabs are `workhorse`'s records whose label is on a `view` line for that window.
    ///   The join is by label only, never by the desk's name, so a rename can't break it.
    /// - A record whose label is on no `view` line of the desk yet, whose `askedWindow` is that window and
    ///   which opened less than `freshFor` from `now` (either way, in case the clock moved back), counts too.
    /// - Records of another workhorse are ignored, and so is a record whose label breaks `TabLabel`'s rule.
    /// - A `view` line for a window with no `windowinfo` line is ignored, as if it were not there.
    /// - A label on `view` lines of two windows (the script doesn't check labels are unique) counts for the
    ///   window of the first such line only.
    public static func build(desk: HostStatus.Desk, workhorse: String, records: [TabRecord], now: Date) -> [WindowTabs] {
        let mine = records.filter { $0.workhorse == workhorse && TabLabel.isValid($0.label) }
            .sorted { ($0.openedAt, $0.label) < ($1.openedAt, $1.label) }
        let ids = Set(desk.windows.compactMap(\.id).filter(HostStatus.isWindowId))
        // Each label's window: the first view line carrying it, among those whose window has a windowinfo line.
        var windowOf: [String: String] = [:]
        for view in desk.views where ids.contains(view.windowId) {
            if let label = view.label, windowOf[label] == nil { windowOf[label] = view.windowId }
        }
        return desk.windows.compactMap { window -> WindowTabs? in
            guard let id = window.id, HostStatus.isWindowId(id) else { return nil }
            let found = mine.filter { record in
                if let shown = windowOf[record.label] { return shown == id }
                return record.askedWindow == id
                    && abs(now.timeIntervalSince(record.openedAt)) < freshFor // either way, if the clock moved back
            }
            return WindowTabs(windowId: id, index: window.index, labels: found.map(\.label),
                              newest: found.last?.label, others: max(0, (window.tabs ?? 0) - found.count))
        }
    }
}
