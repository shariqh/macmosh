import Foundation

/// A colour as plain numbers, 0 to 255 for red, green and blue, in sRGB: written as the design writes it,
/// `LookRGB(0xF0EFED)`.
public struct LookRGB: Sendable, Equatable, CustomStringConvertible {
    public let red, green, blue: UInt8

    public init(_ hex: UInt32) {
        red = UInt8((hex >> 16) & 0xFF)
        green = UInt8((hex >> 8) & 0xFF)
        blue = UInt8(hex & 0xFF)
    }

    /// "#F0EFED".
    public var description: String { String(format: "#%02X%02X%02X", red, green, blue) }
}

/// The four tables of the look (design 5.1): light, dark, and each with Increase Contrast on.
public enum LookAppearance: Sendable, CaseIterable {
    case light, dark, lightIncreased, darkIncreased

    public var isDark: Bool { self == .dark || self == .darkIncreased }
    public var isIncreased: Bool { self == .lightIncreased || self == .darkIncreased }

    /// The table for an AppKit appearance's name, as `NSAppearance.Name.rawValue` gives it: a name containing
    /// "HighContrast" is increased, one containing "Dark" is dark ("NSAppearanceNameAccessibilityHighContrastDarkAqua"
    /// is both). Kept here, on a plain string, so a test can check it; the app passes the name `bestMatch(from:)` picks.
    public static func of(appearanceName: String) -> LookAppearance {
        let dark = appearanceName.contains("Dark")
        if appearanceName.contains("HighContrast") { return dark ? .darkIncreased : .lightIncreased }
        return dark ? .dark : .light
    }
}

/// A named colour of the look (design 5.1). The views use these, never a raw value, so each appearance is one table.
/// The art's colour (`clayArt`) comes with the art in step 3.
public enum LookToken: String, Sendable, CaseIterable {
    /// Names, headings, body text; the primary button's fill.
    case ink
    /// Window names, the summary line, second-rank words.
    case ink2
    /// "Checked 19:49", second lines, chevrons.
    case ink3
    /// The page and the sidebar.
    case ground
    /// Tiles, secondary buttons.
    case surface
    /// Opened details, small sidebar tiles.
    case surface2
    /// Row lines, borders of tiles in dark, the set-apart outline.
    case hairline
    /// Lit cells and art; never small text.
    case ember
    /// Warm words, if any.
    case emberText
    /// The top of the dark icon's lit tiles; never text.
    case glow
    /// Unlit cells.
    case clayCell
    /// The outline of a closed desk's hollow cell.
    case clayOutline
    /// Ready, "In 1 tab".
    case green
    /// States that need the person.
    case amber
    /// Remove…, Forget, refusals, a failed result.
    case red
    /// The primary button's words.
    case onPrimary
}

public enum Look {
    /// The token's value in that appearance.
    public static func value(_ token: LookToken, in appearance: LookAppearance) -> LookRGB {
        let (light, dark, lightIncreased, darkIncreased) = table(token)
        switch appearance {
        case .light: return LookRGB(light)
        case .dark: return LookRGB(dark)
        case .lightIncreased: return LookRGB(lightIncreased)
        case .darkIncreased: return LookRGB(darkIncreased)
        }
    }

    /// Light, dark, light increased, dark increased. The light and dark columns are the design's (5.1). Increased:
    /// ink-2 takes ink's value, ink-3 ink-2's, the hairline ink-3's, and every other token keeps its own, except
    /// where `LookTests` moved a value until its pairs reach 7:1 (toward black in light, toward white in dark, in
    /// 1 per cent steps): ink-3 in light; and the tokens the design leaves to the builder, ember-text, green, amber
    /// and red.
    private static func table(_ token: LookToken) -> (UInt32, UInt32, UInt32, UInt32) {
        switch token {
        case .ink: return (0x1D1C1A, 0xF3F1EE, 0x1D1C1A, 0xF3F1EE)
        case .ink2: return (0x55524E, 0xB9B5AE, 0x1D1C1A, 0xF3F1EE)
        // Light increased: ink-2 (#55524E) is 6.76:1 on the ground; moved 3 per cent toward black.
        case .ink3: return (0x6B6762, 0x9D9992, 0x52504C, 0xB9B5AE)
        case .ground: return (0xF0EFED, 0x1B1A19, 0xF0EFED, 0x1B1A19)
        case .surface: return (0xFFFFFF, 0x2A2928, 0xFFFFFF, 0x2A2928)
        case .surface2: return (0xF7F6F4, 0x222120, 0xF7F6F4, 0x222120)
        case .hairline: return (0xE0DEDA, 0x3A3836, 0x6B6762, 0x9D9992)
        case .ember: return (0xE4572E, 0xFF7A4D, 0xE4572E, 0xFF7A4D)
        case .emberText: return (0xB93F12, 0xFF7A4D, 0x8E310E, 0xFF9A78)
        case .glow: return (0xF7C948, 0xF7C948, 0xF7C948, 0xF7C948)
        case .clayCell: return (0xD5D2CD, 0x4A4744, 0xD5D2CD, 0x4A4744)
        case .clayOutline: return (0xA9A49D, 0x8A867F, 0xA9A49D, 0x8A867F)
        case .green: return (0x2A7230, 0x7BC67E, 0x225B26, 0x7BC67E)
        case .amber: return (0x8A5300, 0xF0B44C, 0x804D00, 0xF0B44C)
        case .red: return (0xB3261E, 0xFF8A7A, 0x9A211A, 0xFF998B)
        case .onPrimary: return (0xFFFFFF, 0x1B1A19, 0xFFFFFF, 0x1B1A19)
        }
    }

    /// The pair's contrast in that appearance.
    public static func ratio(_ pair: LookPair, in appearance: LookAppearance) -> Double {
        Contrast.ratio(value(pair.text.token, in: appearance), value(pair.background.token, in: appearance))
    }
}
