import Foundation

/// One cell on a desk's tile (look design 6.5): a window in a tab (lit, ember), one not in a tab (unlit, clay), or the
/// one hollow cell of a closed desk.
public enum DeskCell: Sendable, Equatable {
    case lit, unlit, hollow
}

/// The cells on a desk's tile (look design 6.5): one per window, up to six in two rows of three; with more windows,
/// the first five and a small plus. Decoration: the row's state words are what counts, and the tile is hidden from
/// VoiceOver.
public struct DeskCells: Sendable, Equatable {
    public var cells: [DeskCell]
    /// More windows than cells: the tile draws a small plus after them.
    public var more: Bool

    /// The most cells a tile shows.
    public static let most = 6
    /// The cells a tile shows before the plus, for a desk with more windows than `most`.
    public static let shownWithMore = 5

    public init(cells: [DeskCell], more: Bool) {
        self.cells = cells
        self.more = more
    }

    /// A closed desk has one hollow cell. An open desk has a cell per window (the report's count, or the windows it
    /// lists when it lists more); when every window carries how many tabs show it (`BoardWindow.inTabs`, past the
    /// menu's gate), a window's cell is lit when that is above 0. Otherwise (an older workhorse script, or the Tabs
    /// connection) as many cells are lit as the desk has tabs open, at most one per window, from the first: the cells
    /// then say how many windows are in a tab, not which. An open desk with no window has no cells.
    public init(_ desk: BoardDesk) {
        guard desk.isOpen else {
            self.init(cells: [.hollow], more: false)
            return
        }
        let n = max(desk.windowCount, desk.windows.count)
        let counts = desk.windows.compactMap(\.inTabs)
        var all: [DeskCell]
        if n > 0, counts.count == n {
            all = counts.map { $0 > 0 ? .lit : .unlit }
        } else {
            let lit = min(max(desk.tabsOpen, 0), n)
            all = Array(repeating: .lit, count: lit) + Array(repeating: .unlit, count: n - lit)
        }
        let more = all.count > Self.most
        if more { all = Array(all.prefix(Self.shownWithMore)) }
        self.init(cells: all, more: more)
    }
}
