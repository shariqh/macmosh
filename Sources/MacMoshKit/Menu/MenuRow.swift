import Foundation

/// One row as the menu's view draws it (issue #107). The view only switches on `kind`; every choice is
/// made here, where it is tested.
public struct MenuRow: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable {
        /// A line that can't be clicked.
        case text
        case separator
        /// A line that does `MenuAction` when clicked.
        case button(MenuAction)
        /// A row that opens a submenu of these rows when the pointer rests on it, and does the action,
        /// if any, when it is clicked (its primary action).
        case submenu([MenuRow], primaryAction: MenuAction?)
    }

    /// The entry's id, unique across the menu: SwiftUI's identity for the row.
    public var id: String
    /// What the row says: the title, after three spaces a level at the menu's top level.
    public var label: String
    /// The title alone, as the action is told it.
    public var title: String
    public var kind: Kind
}

extension MenuLines {
    /// The menu's top level as rows: each entry, then the lines drawn under it one level in. A row
    /// that opens a submenu carries the submenu's rows, which are not indented.
    public var rows: [MenuRow] { MenuRow.rows(entries, depth: 0) }
}

extension MenuRow {
    static func rows(_ entries: [MenuEntry], depth: Int) -> [MenuRow] {
        entries.flatMap { [row($0, depth: depth)] + rows($0.children, depth: depth + 1) }
    }

    private static func row(_ entry: MenuEntry, depth: Int) -> MenuRow {
        let kind: Kind
        if entry.isSeparator {
            kind = .separator
        } else if entry.opensSubmenu {
            kind = .submenu(rows(entry.submenu, depth: 0), primaryAction: entry.action == .none ? nil : entry.action)
        } else if entry.action == .none {
            kind = .text
        } else {
            kind = .button(entry.action)
        }
        return MenuRow(id: entry.id, label: String(repeating: "   ", count: depth) + entry.title,
                       title: entry.title, kind: kind)
    }
}
