import Foundation

/// The four button styles of the look (design 6.4), decided by what the button does, so its title never changes.
public enum ButtonKind: Sendable, Equatable {
    /// Ink fill: New desk… on a workhorse page, Add a Mac… on its page. One per page.
    case primary
    /// A surface tile: everything else.
    case secondary
    /// An outline, no fill: Restart…, alone at the right of the foot.
    case setApart
    /// Red words: Remove…, Forget, Remove MacMosh from this workhorse….
    case destructive

    public static func of(_ action: BoardAction) -> ButtonKind {
        switch action {
        case .window(.newDesk): return .primary
        case .menu(.tab(let args)) where args == ["pair"]: return .primary
        // Restart… is `restart <id>` in a tab (`ButtonRules`).
        case .menu(.tab(let args)) where args.count == 2 && args[0] == "restart": return .setApart
        case .window(.remove), .window(.forget): return .destructive
        // Remove MacMosh from this workhorse… is `remove <id>` in a tab (`ButtonRules.removeMacMosh`).
        case .menu(.tab(let args)) where args.count == 2 && args[0] == "remove": return .destructive
        default: return .secondary
        }
    }

    /// The pair its words are drawn in: on the ink fill, on a surface tile, on the ground behind an outline, and red
    /// on a surface tile.
    public var words: LookPair {
        switch self {
        case .primary: return LookPair(text: .onPrimary, background: .primary)
        case .secondary: return LookPair(text: .primary, background: .surface)
        case .setApart: return LookPair(text: .primary, background: .ground)
        case .destructive: return LookPair(text: .cannot, background: .surface)
        }
    }
}
