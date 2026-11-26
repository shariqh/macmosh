import Foundation

/// Whether any tab shows a window, from the menu's facts (`DeskTabs.WindowTabs`): the window's details say it after
/// its name (look design 6.6), and the menu writes it in brackets after the name (menu design 6.2).
public enum WindowTabState: Sendable, Equatable {
    /// At least one tab this Mac can find; the count is every tab showing it, the ones it cannot find included.
    case inTabs(Int)
    /// Only tabs this Mac cannot find.
    case inAnotherTab
    case notInATab

    /// "in a tab", "in 2 tabs", "open in another tab", "not in a tab".
    public var words: String {
        switch self {
        case .inTabs(let n): return n == 1 ? "in a tab" : "in \(n) tabs"
        case .inAnotherTab: return "open in another tab"
        case .notInATab: return "not in a tab"
        }
    }

    /// Green for a window in a tab, the faintest grey for one in none.
    public var textRole: TextRole {
        switch self {
        case .inTabs, .inAnotherTab: return .good
        case .notInATab: return .tertiary
        }
    }

    /// The window's cell, lit for all but "not in a tab".
    public var cell: DeskCell {
        switch self {
        case .inTabs, .inAnotherTab: return .lit
        case .notInATab: return .unlit
        }
    }
}

/// One window of a desk: the name its line shows and whether a tab shows it. The menu's line is the two together.
public struct WindowNameAndState: Sendable, Equatable {
    public var windowId: String
    /// The window's name, "window <index>" when it has none, "<name> (window <index>)" when an earlier window has it.
    public var name: String
    public var state: WindowTabState

    public init(windowId: String, name: String, state: WindowTabState) {
        self.windowId = windowId
        self.name = name
        self.state = state
    }

    /// The menu's line: the name, then " (<words>)" except for a window in no tab. "zsh (in 2 tabs)", "vim".
    public var menuWords: String {
        state == .notInATab ? name : "\(name) (\(state.words))"
    }
}

extension DeskWindows {
    /// The name rule alone, in order: a window's own name, "window <index>" when it is empty, and
    /// "<name> (window <index>)" for a name an earlier window already has.
    public static func names(_ windows: [(index: Int, name: String)]) -> [String] {
        var named: Set<String> = []
        return windows.map { w in
            let base = w.name.isEmpty ? "window \(w.index)" : w.name
            defer { named.insert(base) }
            return named.contains(base) ? "\(base) (window \(w.index))" : base
        }
    }

    /// Each window of an open desk with its name and state, in the desk's order, from the same facts as the menu's lines.
    public static func namesAndStates(of session: HostStatus.Desk, tabs: [DeskTabs.WindowTabs]) -> [WindowNameAndState] {
        let given = tabs.map { w in
            (index: w.index, name: session.windows.first { $0.index == w.index && $0.id == w.windowId }?.name ?? "")
        }
        return zip(tabs, names(given)).map { w, name in
            let state: WindowTabState
            if w.newest != nil {
                state = .inTabs(w.labels.count + w.others)
            } else if w.others > 0 {
                state = .inAnotherTab
            } else {
                state = .notInATab
            }
            return WindowNameAndState(windowId: w.windowId, name: name, state: state)
        }
    }
}
