import AppKit
import MacMoshKit
import SwiftUI

/// The picture in the menu bar (look design, section 9; issue 183): the M mark of the state the model names by its
/// symbol (`MenuBarMark`), drawn as a template image so macOS colours it for a light or a dark bar and for the open
/// item. Apple, MenuBarExtra: "A scene that renders itself as a persistent control in the system menu bar."
/// (https://developer.apple.com/documentation/swiftui/menubarextra); the page says nothing of template images, so
/// CI's runners showed whether the flag carries through (pull request for issue 183, the trial's readings).
/// One `Image`, never an `if`, so the label keeps its identity, and with it the `.task` the app hangs on it.
struct MenuBarLabel: View {
    let symbol: String

    var body: some View {
        // "Creates a SwiftUI image from an AppKit image instance."
        // (https://developer.apple.com/documentation/swiftui/image/init(nsimage:))
        Image(nsImage: MenuBarMarkImage.image(for: symbol))
    }
}

/// Each name's mark, drawn once and then kept. Every number comes from `MenuBarMark`; this only draws.
@MainActor enum MenuBarMarkImage {
    private static var drawn: [String: NSImage] = [:]

    static func image(for symbol: String) -> NSImage {
        if let image = drawn[symbol] { return image }
        let mark = MenuBarMark.of(symbol: symbol)
        // "Use this method to generate an image that is correct at any resolution."
        // (https://developer.apple.com/documentation/appkit/nsimage/init(size:flipped:drawinghandler:)). Flipped, so y
        // runs down from the top, as MenuBarMark counts it.
        let image = NSImage(size: NSSize(width: MenuBarMark.box, height: MenuBarMark.box), flipped: true) { _ in
            draw(mark)
            return true
        }
        // "Images you mark as template images should consist of only black and clear colors."
        // (https://developer.apple.com/documentation/appkit/nsimage/istemplate)
        image.isTemplate = true
        // "This description is used automatically by interface elements that display images."
        // (https://developer.apple.com/documentation/appkit/nsimage/accessibilitydescription)
        image.accessibilityDescription = MenuBarMark.spokenName(for: symbol)
        drawn[symbol] = image
        return image
    }

    /// Black only, at each cell's opacity; the badge a system symbol drawn plainly, so it keeps its cut-outs.
    nonisolated private static func draw(_ mark: MenuBarMark) {
        for (cell, look) in mark.cells {
            NSColor.black.withAlphaComponent(MenuBarMark.alpha(look)).set()
            if look == .hollow {
                let path = NSBezierPath(roundedRect: MenuBarMark.hollowRect(cell), xRadius: MenuBarMark.hollowCornerRadius,
                                        yRadius: MenuBarMark.hollowCornerRadius)
                path.lineWidth = MenuBarMark.hollowLine
                path.stroke()
            } else {
                NSBezierPath(roundedRect: MenuBarMark.cellRect(cell), xRadius: MenuBarMark.cornerRadius,
                             yRadius: MenuBarMark.cornerRadius).fill()
            }
        }
        guard let badge = mark.badge,
              let symbol = NSImage(systemSymbolName: badge.symbolName, accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: MenuBarMark.badgePointSize,
                                                                    weight: MenuBarMark.badgeWeight == .bold ? .bold : .regular))
        else { return }
        // "Draws all or part of the image in the specified rectangle respecting the hints and the orientation of the
        // current coordinate system." (https://developer.apple.com/documentation/appkit/nsimage/draw(in:from:operation:fraction:respectflipped:hints:))
        symbol.draw(in: MenuBarMark.badgeFrame(natural: symbol.size), from: .zero, operation: .sourceOver, fraction: 1,
                    respectFlipped: true, hints: nil)
    }
}
