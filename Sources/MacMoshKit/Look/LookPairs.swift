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
    /// The text the views draw, each on what it sits on. The app's colour file draws text only from a pair
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
        // Step 2, on the details panel and the greyed panel: a window's name, a fact's value, "Keeps its command
        // running".
        LookPair(text: .primary, background: .surface2),
        // "in a tab", "in 2 tabs", "open in another tab".
        LookPair(text: .good, background: .surface2),
        // "not in a tab", a fact's label, the greyed list.
        LookPair(text: .tertiary, background: .surface2),
    ]

    /// Tested now and drawn later: warm words, which settle ember-text.
    public static let reservedPairs: [LookPair] = [
        LookPair(text: .warm, background: .ground),
        LookPair(text: .warm, background: .surface),
    ]
}

/// A mark drawn beside words that say the same (a tick, a warning triangle, a circle), on what it sits on. The desk
/// tile's cells, the window lines' cells and the pill's dot are decoration and stay out: the clay cell is about 1.5:1
/// on a tile by design.
public struct LookMark: Sendable, Hashable, CustomStringConvertible {
    public var token: LookToken
    public var background: BackgroundRole

    public init(token: LookToken, background: BackgroundRole) {
        self.token = token
        self.background = background
    }

    /// "green on ground".
    public var description: String { "\(token.rawValue) on \(background)" }
}

extension Look {
    /// The done tick and the In-N-tabs tick (green), the failed triangle (red), the unknown mark (ink-3), and the
    /// No tab and Closed circles (ink-2), each on the ground.
    public static let marks: [LookMark] = [
        LookMark(token: .green, background: .ground), LookMark(token: .red, background: .ground),
        LookMark(token: .ink3, background: .ground), LookMark(token: .ink2, background: .ground),
    ]

    /// Marks on a tile (look step 3): the sidebar tile's state symbol in its tone (on a surface tile, or a surface-2 tile
    /// on the chosen card), the plus and the gear (ink), and the result's marks in their tile (green, red, ink-3). Each
    /// token on surface, then on surface-2.
    public static let tileMarks: [LookMark] = [LookToken.green, .amber, .red, .ink3, .ink].flatMap { t in
        [LookMark(token: t, background: .surface), LookMark(token: t, background: .surface2)]
    }

    /// The mark's contrast against what it sits on, in that appearance.
    public static func ratio(_ mark: LookMark, in appearance: LookAppearance) -> Double {
        Contrast.ratio(value(mark.token, in: appearance), value(mark.background.token, in: appearance))
    }

    /// A fill under a pressed button's overlay: each channel times (1 - `LookSize.pressedOverlay`), rounded.
    public static func pressed(_ c: LookRGB) -> LookRGB {
        func dim(_ v: UInt8) -> UInt8 { UInt8((Double(v) * (1 - LookSize.pressedOverlay)).rounded()) }
        return LookRGB(red: dim(c.red), green: dim(c.green), blue: dim(c.blue))
    }
}
