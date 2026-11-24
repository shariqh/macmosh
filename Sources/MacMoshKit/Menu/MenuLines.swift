import Foundation

/// One entry of the menu as a tree: a workhorse's headline with its lines, a desk with its actions,
/// or a line at the top level (Add a Mac…, Check now, a separator).
///
/// An entry says how its lines are drawn, by which list holds them; nothing is inferred:
/// - `submenu`: the lines of the submenu this entry's line opens (issue #107). An entry with a submenu
///   is drawn as a row that opens it, and its `action`, if any, is the row's primary action: what a
///   click on the row itself does. Empty when the line opens no submenu.
/// - `children`: the lines drawn under this one in the same menu, one level in, flat, as every state
///   that is not Ready is drawn.
/// The Ready headline has both: its own submenu, and its desks drawn under it at the top level.
/// An entry with no lines and no action is a line of text. Submenus go one level deep only.
///
/// `id` is the same every time the tree is built from the same input: `wh:<workhorse id>`,
/// `wh:<workhorse id>:hint`, `desk:<workhorse id>:<desk name>`, `desk:<workhorse id>:<desk name>:rename`,
/// `top:add`, and `<parent id>:sep<n>` for separators. The ids are SwiftUI's identity for the menu's
/// rows, so `MenuLines` makes them unique for any input: a saved list edited by hand can repeat a
/// workhorse id, and a report can name a desk twice. An id seen before gets `#2`, `#3`, … (the first
/// number not used yet), in the order the tree is read.
public struct MenuEntry: Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var action: MenuAction
    public var isSeparator: Bool
    /// The lines of the submenu this line opens; empty when it opens none.
    public var submenu: [MenuEntry]
    /// The lines drawn under this one in the same menu, one level in.
    public var children: [MenuEntry]

    public init(id: String, title: String, action: MenuAction = .none, isSeparator: Bool = false,
                submenu: [MenuEntry] = [], children: [MenuEntry] = []) {
        self.id = id
        self.title = title
        self.action = action
        self.isSeparator = isSeparator
        self.submenu = submenu
        self.children = children
    }

    /// True when this line is drawn as a row that opens a submenu.
    public var opensSubmenu: Bool { !submenu.isEmpty }

    /// A line for a button from `ButtonRules`, its id the parent's id and the button's key.
    static func button(_ button: ActionButton, under parent: String) -> MenuEntry {
        MenuEntry(id: "\(parent):\(button.key)", title: button.title, action: button.action)
    }

    static func separator(id: String) -> MenuEntry {
        MenuEntry(id: id, title: "", isSeparator: true)
    }

    /// The tree as lines, depth first: each entry's own line at its depth, then the lines of the
    /// submenu it opens one level deeper (marked `inSubmenu`), then the lines under it one level
    /// deeper. A top-level entry is at depth 0. The log's line count and the plain-words check read these.
    public static func flatten(_ entries: [MenuEntry], depth: Int = 0) -> [MenuItem] {
        flatten(entries, depth: depth, inSubmenu: false)
    }

    private static func flatten(_ entries: [MenuEntry], depth: Int, inSubmenu: Bool) -> [MenuItem] {
        entries.flatMap { entry in
            [MenuItem(title: entry.title, action: entry.action, indent: depth, isSeparator: entry.isSeparator,
                      opensSubmenu: entry.opensSubmenu, inSubmenu: inSubmenu)]
                + flatten(entry.submenu, depth: depth + 1, inSubmenu: true)
                + flatten(entry.children, depth: depth + 1, inSubmenu: inSubmenu)
        }
    }

    /// True when this entry, or any entry under it, opens a submenu.
    var holdsSubmenu: Bool {
        opensSubmenu || children.contains(where: \.holdsSubmenu)
    }
}

/// What the menu shows: its icon, its entries as a tree, and the same entries as lines, top to bottom.
/// Called `MenuLines`, not `Menu`, so a view can use it beside SwiftUI's own `Menu`. The view draws
/// the tree; the log's line count and the plain-words check read the lines.
public struct MenuLines: Sendable, Equatable {
    public let symbol: String
    public let entries: [MenuEntry]
    /// `entries` flattened, worked out once.
    public let items: [MenuItem]

    /// `entries` with every repeated id numbered, so no two are the same.
    public init(symbol: String, entries: [MenuEntry]) {
        var seen: Set<String> = []
        let unique = MenuEntry.numberingRepeats(entries, seen: &seen)
        self.symbol = symbol
        self.entries = unique
        self.items = MenuEntry.flatten(unique)
    }

    /// True when at least one line of the menu opens a submenu. While such a menu is open it holds
    /// still (`HoldStill`), because a change to the menu closes an open submenu.
    public var hasSubmenu: Bool { entries.contains(where: \.holdsSubmenu) }
}

extension MenuEntry {
    /// Depth first, each entry before its submenu and then its children: an id already in `seen`
    /// becomes `<id>#n` with the smallest n from 2 up that is not in `seen` either. The same input
    /// gives the same ids every time.
    static func numberingRepeats(_ entries: [MenuEntry], seen: inout Set<String>) -> [MenuEntry] {
        entries.map { entry in
            var entry = entry
            if seen.contains(entry.id) {
                var n = 2
                while seen.contains("\(entry.id)#\(n)") { n += 1 }
                entry.id = "\(entry.id)#\(n)"
            }
            seen.insert(entry.id)
            entry.submenu = numberingRepeats(entry.submenu, seen: &seen)
            entry.children = numberingRepeats(entry.children, seen: &seen)
            return entry
        }
    }
}
