import Foundation

/// WCAG 2's contrast (https://www.w3.org/TR/WCAG22/#dfn-relative-luminance and #dfn-contrast-ratio, read on
/// 2026-11-25). The look's pairs must reach `minimum` in light and dark and `increased` with Increase Contrast on.
public enum Contrast {
    /// Every pair in light and dark (look design, 5.1).
    public static let minimum = 4.5
    /// Every pair with Increase Contrast on (look design, 5.1).
    public static let increased = 7.0
    /// A mark beside words (a tick, a warning triangle, a circle): this project's own floor, borrowing the threshold of
    /// WCAG 2.2's 1.4.11 Non-text Contrast, "a contrast ratio of at least 3:1 against adjacent color(s)"
    /// (https://www.w3.org/TR/WCAG22/#non-text-contrast). The words beside the mark say the same, so WCAG does not
    /// strictly ask it of these marks.
    public static let nonText = 3.0

    /// WCAG 2.2's relative luminance of an sRGB colour, 0 for black and 1 for white: L = 0.2126 R + 0.7152 G
    /// + 0.0722 B, where each channel c = value / 255 is c / 12.92 when c <= 0.04045, else ((c + 0.055) / 1.055) ^ 2.4.
    public static func luminance(_ c: LookRGB) -> Double {
        func linear(_ v: UInt8) -> Double {
            let c = Double(v) / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(c.red) + 0.7152 * linear(c.green) + 0.0722 * linear(c.blue)
    }

    /// (L1 + 0.05) / (L2 + 0.05), L1 the lighter's luminance and L2 the darker's: from 1 to 21, in either order.
    public static func ratio(_ a: LookRGB, _ b: LookRGB) -> Double {
        let (x, y) = (luminance(a), luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }
}
