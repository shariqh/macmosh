import CoreGraphics
import Foundation

// The picture in the menu bar (look design, section 9; issue 183): the icon's M as a 16 by 16 point mark of 5 by 5
// cells, one mark per state, so states differ in shape even in one colour. Black and clear only: the app draws it as a
// template image, which macOS recolours for the bar (Apple: "Images you mark as template images should consist of only
// black and clear colors. You can use the alpha channel in the image to adjust the opacity of black content, however.",
// https://developer.apple.com/documentation/appkit/nsimage/istemplate).
//
// The M's cells are `IconArt.mCells`, the one table of the M; nothing here writes them again. The model, the board and
// the log keep naming each state by today's system symbol name (`MenuModel.symbol(for:)`); this table maps the name to
// its mark. The badge's square follows the picture the owner chose
// (docs/superpowers/specs/look-2026-11-25/menu-bar-mark-m.png, 20 pixels per point with the grid's first cell at pixel
// 80): its dotted ring spans 9.95 to 16.05 points across and down, so x 10, y 10, 6 by 6. That reaches the box's edge,
// a departure from the text's "1 point clear on every side", and stays 1 point clear of every cell a badged mark draws.

/// How a cell of the mark is drawn; a cell the mark does not list is clear.
public enum MarkCell: Sendable, Hashable {
    /// Black.
    case solid
    /// Black at `MenuBarMark.faintOpacity`.
    case faint
    /// A black outline `MenuBarMark.hollowLine` wide, inside the cell.
    case hollow
}

public enum MarkWeight: Sendable, Equatable {
    case regular, bold
}

/// A badge at the lower right: a system symbol drawn black into the mark.
public enum MarkBadge: String, Sendable, CaseIterable, Hashable {
    case exclamation = "exclamationmark.circle.fill"
    case person = "person.fill"
    case padlock = "lock.fill"
    case warning = "exclamationmark.triangle.fill"
    /// The design's "no-entry" badge, drawn as the chosen picture draws it: a circle with a slash.
    case noEntry = "nosign"
    case wrench = "wrench.fill"
    case plus = "plus"

    /// The system symbol's name.
    public var symbolName: String { rawValue }
}

public struct MenuBarMark: Sendable, Hashable {
    public let cells: [IconCell: MarkCell]
    public let badge: MarkBadge?

    public init(cells: [IconCell: MarkCell], badge: MarkBadge?) {
        self.cells = cells
        self.badge = badge
    }

    /// Every cell the mark draws, faint and hollow ones included.
    public var drawn: Set<IconCell> { Set(cells.keys) }

    /// The nine names the model gives, in the order of design 9's table.
    public static let symbols = [
        "checkmark.circle", "exclamationmark.circle", "person.crop.circle.badge.questionmark", "lock.circle",
        "exclamationmark.triangle", "wifi.slash", "wrench.and.screwdriver", "ellipsis.circle", "plus.circle",
    ]

    /// The mark for a name; a name not in `symbols` gets the still-checking mark, which claims nothing.
    public static func of(symbol: String) -> MenuBarMark {
        let m = Set(IconArt.mCells)
        let legs = m.subtracting(badgeHole)
        func all(_ look: MarkCell, _ cells: Set<IconCell>) -> [IconCell: MarkCell] {
            Dictionary(uniqueKeysWithValues: cells.map { ($0, look) })
        }
        switch symbol {
        case "checkmark.circle": return MenuBarMark(cells: all(.solid, m), badge: nil)
        case "exclamationmark.circle": return MenuBarMark(cells: all(.solid, legs), badge: .exclamation)
        case "person.crop.circle.badge.questionmark": return MenuBarMark(cells: all(.solid, legs), badge: .person)
        case "lock.circle": return MenuBarMark(cells: all(.solid, legs), badge: .padlock)
        case "exclamationmark.triangle": return MenuBarMark(cells: all(.solid, legs), badge: .warning)
        case "wifi.slash": return MenuBarMark(cells: all(.hollow, legs), badge: .noEntry)
        case "wrench.and.screwdriver": return MenuBarMark(cells: all(.solid, legs), badge: .wrench)
        case "plus.circle": return MenuBarMark(cells: all(.faint, legs), badge: .plus)
        default:
            // Still checking: the M faint, with the middle row's five cells solid.
            let row2 = Set((0..<IconArt.gridSize).map { IconCell(row: 2, column: $0) })
            return MenuBarMark(cells: all(.faint, m.subtracting(row2)).merging(all(.solid, row2)) { $1 }, badge: nil)
        }
    }

    /// What the menu-bar item says to VoiceOver for a name: the words it has today, with the system symbol as its
    /// picture (decision 4: they stay). CI's runners read them as the item's AXTitle, the same on macOS 15 and 26 in
    /// light and dark (Menu pictures run 45883300450); its AXDescription was empty for every state. Two are the
    /// symbol's own name, because the system symbol carries no words for them. A name not in `symbols` gets the
    /// still-checking mark's words, as it gets its mark.
    public static func spokenName(for symbol: String) -> String? {
        switch symbol {
        case "checkmark.circle": return "Selected"
        case "exclamationmark.circle": return "Error"
        case "person.crop.circle.badge.questionmark": return "person.crop.circle.badge.questionmark"
        case "lock.circle": return "Lock"
        case "exclamationmark.triangle": return "Warning"
        case "wifi.slash": return "Wi-Fi Off"
        case "wrench.and.screwdriver": return "wrench.and.screwdriver"
        case "plus.circle": return "Add"
        default: return "More"
        }
    }

    // Design 9, in points, y counted down from the top of the box.
    public static let box = 16.0
    public static let inset = 1.0
    public static let cell = 2.0
    public static let gap = 1.0
    public static let cornerRadius = 0.5
    /// About a third (design 9, the agent's call).
    public static let faintOpacity = 1.0 / 3
    public static let hollowLine = 0.5
    public static let badgePointSize = 6.0
    public static let badgeWeight = MarkWeight.bold
    /// The M's right leg's lower two cells, which a badge takes the place of.
    public static let badgeHole: Set<IconCell> = [IconCell(row: 3, column: 4), IconCell(row: 4, column: 4)]
    /// Where a badge goes: the chosen picture's dotted ring (see the header).
    public static let badgeRect = CGRect(x: 10, y: 10, width: 6, height: 6)

    public static func cellRect(_ c: IconCell) -> CGRect {
        let step = cell + gap
        return CGRect(x: inset + Double(c.column) * step, y: inset + Double(c.row) * step, width: cell, height: cell)
    }

    /// Where a hollow cell's line runs: `cellRect` inset by half the line, so the line stays inside the cell.
    public static func hollowRect(_ c: IconCell) -> CGRect {
        cellRect(c).insetBy(dx: hollowLine / 2, dy: hollowLine / 2)
    }

    public static let hollowCornerRadius = cornerRadius - hollowLine / 2

    /// The black's opacity for a cell: solid and hollow 1, faint `faintOpacity`.
    public static func alpha(_ look: MarkCell) -> Double {
        look == .faint ? faintOpacity : 1
    }

    /// A badge symbol of that natural size, scaled to fit `badgeRect`, centred across, standing on its foot.
    public static func badgeFrame(natural: CGSize) -> CGRect {
        guard natural.width > 0, natural.height > 0 else { return badgeRect }
        let scale = min(badgeRect.width / natural.width, badgeRect.height / natural.height)
        let width = natural.width * scale, height = natural.height * scale
        return CGRect(x: badgeRect.midX - width / 2, y: badgeRect.maxY - height, width: width, height: height)
    }
}
