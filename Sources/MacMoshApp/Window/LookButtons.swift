import MacMoshKit
import SwiftUI

/// The look's four buttons (look design 6.4), by `ButtonKind`: primary (an ink fill), secondary (a surface tile),
/// set apart (a hairline outline, no fill) and destructive (a surface tile with red words). Titles stay the board's;
/// a glyph is decoration, hidden from VoiceOver. A small button (look step 2) is 24 points high with the second
/// line's type: every button inside a desk's opened details is one.
///
/// Apple, ButtonStyle (macOS 10.15, https://developer.apple.com/documentation/swiftui/buttonstyle): "A type that
/// applies standard interaction behavior and a custom appearance to all buttons within a view hierarchy." Apple,
/// ButtonStyleConfiguration.isPressed (macOS 10.15,
/// https://developer.apple.com/documentation/swiftui/buttonstyleconfiguration/ispressed): "A Boolean that indicates
/// whether the user is currently pressing the button."
struct LookButtonStyle: ButtonStyle {
    let kind: ButtonKind
    var glyph: String? = nil
    var small = false

    func makeBody(configuration: Configuration) -> some View {
        LookButtonBody(kind: kind, glyph: glyph, small: small, label: configuration.label, isPressed: configuration.isPressed)
    }

    /// The small leading glyph: New desk… and Restart… have one (look design 6.4 and 15).
    static func glyph(for action: BoardAction) -> String? {
        if case .window(.newDesk) = action { return "plus.square.on.square" }
        return ButtonKind.of(action) == .setApart ? "arrow.clockwise" : nil
    }
}

private struct LookButtonBody: View {
    let kind: ButtonKind
    let glyph: String?
    let small: Bool
    let label: ButtonStyleConfiguration.Label
    let isPressed: Bool
    /// Apple, EnvironmentValues.isEnabled (macOS 10.15, https://developer.apple.com/documentation/swiftui/environmentvalues/isenabled):
    /// "A Boolean value that indicates whether the view associated with this environment allows user interaction."
    @Environment(\.isEnabled) private var isEnabled

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: LookSize.buttonRadius, style: .continuous)
    }

    var body: some View {
        let words = kind.words
        HStack(spacing: 5) {
            if let glyph {
                Image(systemName: glyph).accessibilityHidden(true)
            }
            label.lineLimit(1)
        }
        .font(.system(size: small ? LookSize.secondFont : LookSize.bodyFont))
        .fixedSize()
        .foregroundStyle(LookColor.text(words.text, on: words.background))
        .padding(.horizontal, small ? 8 : 12)
        .frame(minHeight: small ? LookSize.smallButtonHeight : LookSize.buttonHeight)
        // Pressed: black at `LookSize.pressedOverlay` over the fill and under the words, so the words keep their pair's
        // contrast on the darkened fill (`LookTests.aPressedButtonKeepsItsContrast`).
        .background {
            ZStack {
                fill
                if isPressed { shape.fill(.black.opacity(LookSize.pressedOverlay)) }
            }
        }
        .opacity(isEnabled ? 1 : 0.45)
        .contentShape(shape)
    }

    @ViewBuilder private var fill: some View {
        switch kind {
        case .primary:
            shape.fill(LookColor.background(.primary))
        case .secondary, .destructive:
            Color.clear.lookTile(radius: LookSize.buttonRadius)
        case .setApart:
            shape.strokeBorder(LookColor.mark(.hairline), lineWidth: LookSize.ringWidth)
        }
    }
}
