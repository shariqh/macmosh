import Foundation

/// One entry of the menu as a tree: a workhorse's headline with its lines under it, a desk with its
/// actions under it, or a line at the top level (Add a Mac…, Check now, a separator).
///
/// An entry may have an action and children at once: the desk line opens the desk and has lines
/// under it. `id` is unique across the whole tree and the same every time the tree is built from the
/// same input: `wh:<workhorse id>`, `wh:<workhorse id>:hint`, `desk:<workhorse id>:<desk name>`,
/// `desk:<workhorse id>:<desk name>:rename`, `top:add`, and `<parent id>:sep<n>` for separators.
/// No two are the same when workhorse ids hold no `:` and are all different (as `Workhorse.makeID`
/// makes them) and a report names each desk once (as the host script writes it). Nothing checks this
/// when the saved list is loaded, so a hand-edited list can repeat ids; today nothing reads them.
public struct MenuEntry: Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var action: MenuAction
    public var isSeparator: Bool
    public var children: [MenuEntry]

    public init(id: String, title: String, action: MenuAction = .none, isSeparator: Bool = false,
                children: [MenuEntry] = []) {
        self.id = id
        self.title = title
        self.action = action
        self.isSeparator = isSeparator
        self.children = children
    }

    /// A line for a button from `ButtonRules`, its id the parent's id and the button's key.
    static func button(_ button: ActionButton, under parent: String) -> MenuEntry {
        MenuEntry(id: "\(parent):\(button.key)", title: button.title, action: button.action)
    }

    static func separator(id: String) -> MenuEntry {
        MenuEntry(id: id, title: "", isSeparator: true)
    }

    /// The tree as today's lines, depth first: each entry's own line at its depth, then its children
    /// one level deeper. A top-level entry is at depth 0.
    public static func flatten(_ entries: [MenuEntry], depth: Int = 0) -> [MenuItem] {
        entries.flatMap { entry in
            [MenuItem(title: entry.title, action: entry.action, indent: depth, isSeparator: entry.isSeparator)]
                + flatten(entry.children, depth: depth + 1)
        }
    }
}

/// What the menu shows: its icon, its entries as a tree, and the same entries as lines, top to bottom.
/// Called `MenuLines`, not `Menu`, so a view can use it beside SwiftUI's own `Menu`. The menu is
/// drawn from `items`; the log's line count and the plain-words check read them too.
public struct MenuLines: Sendable, Equatable {
    public let symbol: String
    public let entries: [MenuEntry]
    /// `entries` flattened, worked out once.
    public let items: [MenuItem]

    public init(symbol: String, entries: [MenuEntry]) {
        self.symbol = symbol
        self.entries = entries
        self.items = MenuEntry.flatten(entries)
    }
}
