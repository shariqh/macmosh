// The app icon's art: the M's thirteen cells on a 5 by 5 grid, where each tile sits, and the
// icon's colours, light and dark (design section 8.1). The sizes are the plan's, measured from the
// picture the owner chose (docs/superpowers/specs/look-2026-11-25/icon-m-light-and-dark.png).
//
// scripts/draw-icon/main.swift compiles this file alone, together with itself, to draw the icon's
// layer pictures. So this file imports nothing and uses no other MacMoshKit type: the standard
// library only (IconArtTests checks that it has no import line). `MenuBarMark` and the Add a Mac page's tile read
// `mCells`; there is no other table of the M.

/// One cell of the 5 by 5 grid, counted from 0 at the top left.
public struct IconCell: Hashable, Sendable {
    public let row: Int
    public let column: Int

    public init(row: Int, column: Int) {
        self.row = row
        self.column = column
    }
}

public enum IconAppearance: Sendable, CaseIterable {
    case light, dark
}

/// A gradient stop: a location from 0 (top) to 1 (bottom), and a colour as 0xRRGGBB in sRGB.
public struct IconStop: Equatable, Sendable {
    public let location: Double
    public let rgb: UInt32

    public init(_ location: Double, _ rgb: UInt32) {
        self.location = location
        self.rgb = rgb
    }
}

public enum IconArt {
    public static let gridSize = 5

    /// The M: column 0 and column 4 in full, plus row 1 column 1, row 1 column 3 and row 2 column 2.
    /// Row by row, left to right.
    public static let mCells: [IconCell] = {
        var cells: [IconCell] = []
        for row in 0..<gridSize {
            for column in 0..<gridSize where litInRow(row, column) {
                cells.append(IconCell(row: row, column: column))
            }
        }
        return cells
    }()

    private static func litInRow(_ row: Int, _ column: Int) -> Bool {
        if column == 0 || column == gridSize - 1 { return true }
        return (row == 1 && (column == 1 || column == 3)) || (row == 2 && column == 2)
    }

    public static func isLit(_ cell: IconCell) -> Bool {
        mCells.contains(cell)
    }

    // The layer pictures, 1024 pixels square. The tiles inset by a tenth of the side: 2 * 102 +
    // 5 * 140 + 4 * 30 = 1024.
    public static let canvas = 1024
    public static let inset = 102
    public static let tile = 140
    public static let gap = 30
    public static let tileRadius = 32

    /// The tile's top-left corner, with y counted downward from the top.
    public static func tileOrigin(_ cell: IconCell) -> (x: Int, y: Int) {
        (inset + cell.column * (tile + gap), inset + cell.row * (tile + gap))
    }

    /// The ground, from the top of the canvas to its bottom.
    public static func ground(_ appearance: IconAppearance) -> [IconStop] {
        switch appearance {
        case .light: [IconStop(0, 0xFCFAF7), IconStop(1, 0xECE5DD)]
        case .dark: [IconStop(0, 0x2A2928), IconStop(1, 0x1D1C1A)]
        }
    }

    /// The M's colour, from `litTop` to `litBottom`, seen through the M's tiles: one gradient over the
    /// whole grid, so each row of the M is a slice of it. Design 8.1 gives the dark colours in order but
    /// no positions. They sit where the picture the owner chose has them: the first at the top of the
    /// grid, the others at the centres of rows 0, 2 and 4, so rows 1 and 3 fall half way between.
    public static func lit(_ appearance: IconAppearance) -> [IconStop] {
        switch appearance {
        case .light: [IconStop(0, 0xF29A55), IconStop(1, 0xD2481F)]
        case .dark: [IconStop(0, 0xFAD566), IconStop(rowCentre(0), 0xF7C948), IconStop(rowCentre(2), 0xF29343),
                     IconStop(rowCentre(4), 0xE4572E), IconStop(1, 0xE4572E)]
        }
    }

    /// Where the centre of a row of tiles falls between `litTop` (0) and `litBottom` (1).
    public static func rowCentre(_ row: Int) -> Double {
        Double(row * (tile + gap) + tile / 2) / Double(litBottom - litTop)
    }

    public static let litTop = 102
    public static let litBottom = 922

    /// Each of the twelve other tiles, from its top to its bottom.
    public static func unlit(_ appearance: IconAppearance) -> [IconStop] {
        switch appearance {
        case .light: [IconStop(0, 0xFFFFFF), IconStop(1, 0xF4EEE7)]
        case .dark: [IconStop(0, 0x3B3835), IconStop(1, 0x2F2D2A)]
        }
    }

    // At 16 pixels, tiles would blur, so the M is solid: a rounded body 14 pixels square at (1, 1),
    // and the M's cells as 2 by 2 squares that fill 10 by 10 pixels at (3, 3), with no gaps.
    public static let small = 16
    public static let smallBodyOrigin = 1
    public static let smallBodySize = 14
    public static let smallBodyRadius = 3
    public static let smallMOrigin = 3
    public static let smallCell = 2

    /// The top-left pixel of a cell's 2 by 2 square, with y counted downward from the top.
    public static func smallCellOrigin(_ cell: IconCell) -> (x: Int, y: Int) {
        (smallMOrigin + cell.column * smallCell, smallMOrigin + cell.row * smallCell)
    }

    public static func smallGround(_ appearance: IconAppearance) -> UInt32 {
        switch appearance {
        case .light: 0xF3EEE8
        case .dark: 0x24221F
        }
    }

    /// The small M's colour, top to bottom: one ember in light, the lit cells' colours in dark.
    public static func smallM(_ appearance: IconAppearance) -> [IconStop] {
        switch appearance {
        case .light: [IconStop(0, 0xE2552C), IconStop(1, 0xE2552C)]
        case .dark: lit(.dark)
        }
    }
}
