import AppKit
import MacMoshKit
import SwiftUI

/// The look's colours (look design 5.1 and 5.3), each following light, dark and Increase Contrast without an asset
/// catalog. The values are `Look.value` in MacMoshKit, where they are tested; this only turns them into colours.
///
/// Apple, NSColor init(name:dynamicProvider:) (macOS 10.15,
/// https://developer.apple.com/documentation/appkit/nscolor/init(name:dynamicprovider:)): "Creates a dynamic catalog
/// color with a provider that's used to resolve the exact color value, calculated on first use." and "When methods on
/// a color need color component values, AppKit calls the provider with currentDrawingAppearance." Apple, NSAppearance
/// bestMatch(from:) (macOS 10.14, https://developer.apple.com/documentation/appkit/nsappearance/bestmatch(from:)):
/// "This method returns the name from the appearances array that comes closest to matching the current appearance
/// object's attributes." Apple, NSAppearance.Name.accessibilityHighContrastDarkAqua (macOS 10.14,
/// https://developer.apple.com/documentation/appkit/nsappearance/name-swift.struct/accessibilityhighcontrastdarkaqua):
/// "AppKit then returns this type when the user enables the Increase Contrast option in the Accessibility system
/// preferences." Apple, Color init(nsColor:) (macOS 12.0, https://developer.apple.com/documentation/swiftui/color/init(nscolor:)):
/// "The new color preserves the adaptability of the original."
enum LookColor {
    /// Text in `role` on `background`. Only a pair in `Look.pairs` may be drawn, so the contrast tests see every pair
    /// the views use; a debug build (the one CI drives) stops on any other.
    static func text(_ role: TextRole, on background: BackgroundRole) -> Color {
        assert(Look.pairs.contains(LookPair(text: role, background: background)),
               "\(LookPair(text: role, background: background)) is not in Look.pairs")
        return colors[role.token] ?? .primary
    }

    static func background(_ role: BackgroundRole) -> Color { colors[role.token] ?? .clear }

    /// A colour that is not text: ember and clay for cells, hairline for rings and lines, green, amber and red for marks.
    static func mark(_ token: LookToken) -> Color { colors[token] ?? .clear }

    /// The four appearances the tables cover, in the names `LookAppearance.of(appearanceName:)` reads.
    private static let names: [NSAppearance.Name] = [
        .aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua,
    ]

    private static let colors: [LookToken: Color] = Dictionary(uniqueKeysWithValues: LookToken.allCases.map { token in
        (token, Color(nsColor: NSColor(name: nil) { appearance in
            let name = appearance.bestMatch(from: names) ?? .aqua
            let rgb = Look.value(token, in: LookAppearance.of(appearanceName: name.rawValue))
            return NSColor(srgbRed: CGFloat(rgb.red) / 255, green: CGFloat(rgb.green) / 255,
                           blue: CGFloat(rgb.blue) / 255, alpha: 1)
        }))
    })
}

/// A tile (look design 5.1): a surface fill, and in light a soft shadow with a faint ring, in dark only a hairline ring.
struct LookTile: ViewModifier {
    let radius: CGFloat
    var fill: BackgroundRole = .surface
    /// Apple, EnvironmentValues.colorScheme (https://developer.apple.com/documentation/swiftui/environmentvalues/colorscheme):
    /// "The color scheme of this environment."
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content.background {
            if scheme == .dark {
                shape.fill(LookColor.background(fill))
                    .overlay(shape.strokeBorder(LookColor.mark(.hairline), lineWidth: LookSize.ringWidth))
            } else {
                shape.fill(LookColor.background(fill))
                    .shadow(color: .black.opacity(LookSize.shadowOpacity), radius: LookSize.shadowBlur, x: 0,
                            y: LookSize.shadowY)
                    .overlay(shape.strokeBorder(.black.opacity(LookSize.ringOpacity), lineWidth: LookSize.ringWidth))
            }
        }
    }
}

extension View {
    /// The look's tile behind this view, with corners of `radius` points.
    func lookTile(radius: CGFloat, fill: BackgroundRole = .surface) -> some View {
        modifier(LookTile(radius: radius, fill: fill))
    }
}
