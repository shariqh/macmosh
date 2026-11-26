import Foundation

/// What a piece of text is, for its colour.
public enum TextRole: Sendable, CaseIterable {
    case primary, secondary, tertiary, good, needsYou, cannot, onPrimary, warm

    public var token: LookToken {
        switch self {
        case .primary: return .ink
        case .secondary: return .ink2
        case .tertiary: return .ink3
        case .good: return .green
        case .needsYou: return .amber
        case .cannot: return .red
        case .onPrimary: return .onPrimary
        case .warm: return .emberText
        }
    }
}

/// What the text sits on. `primary` is the primary button's fill, ink.
public enum BackgroundRole: Sendable, CaseIterable {
    case ground, surface, surface2, primary

    public var token: LookToken {
        switch self {
        case .ground: return .ground
        case .surface: return .surface
        case .surface2: return .surface2
        case .primary: return .ink
        }
    }
}

/// A text role on a background role: one pair the views draw, whose contrast `LookTests` checks.
public struct LookPair: Sendable, Hashable, CustomStringConvertible {
    public var text: TextRole
    public var background: BackgroundRole

    public init(text: TextRole, background: BackgroundRole) {
        self.text = text
        self.background = background
    }

    /// "secondary on ground".
    public var description: String { "\(text) on \(background)" }
}

extension Look {
    /// The text the views draw in step 1, each on what it sits on. The app's colour file draws text only from a pair
    /// in this list, so the tests see every pair the views use.
    public static let pairs: [LookPair] = [
        // The page name, the Desks heading, a desk's name, the hint, a set-apart button's words.
        LookPair(text: .primary, background: .ground),
        // A secondary button's words.
        LookPair(text: .primary, background: .surface),
        // Window names, the summary, "No tab", "Closed", "Updating…", a done result, the notice.
        LookPair(text: .secondary, background: .ground),
        // The "Made by hand" tag.
        LookPair(text: .secondary, background: .surface),
        // The time, "Checking…", a desk's second line, the home line.
        LookPair(text: .tertiary, background: .ground),
        // The "Still checking…" pill.
        LookPair(text: .tertiary, background: .surface),
        // "In 2 tabs".
        LookPair(text: .good, background: .ground),
        // The Ready pill.
        LookPair(text: .good, background: .surface),
        // The pill of a state that needs the person.
        LookPair(text: .needsYou, background: .surface),
        // The pill of Can't reach it and Can't verify it; a destructive button's words on its tile.
        LookPair(text: .cannot, background: .surface),
        // A failed result.
        LookPair(text: .cannot, background: .ground),
        // The primary button's words.
        LookPair(text: .onPrimary, background: .primary),
    ]

    /// Tested now and drawn later: warm words, which settle ember-text.
    public static let reservedPairs: [LookPair] = [
        LookPair(text: .warm, background: .ground),
        LookPair(text: .warm, background: .surface),
    ]
}
