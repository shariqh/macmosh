import Foundation

/// One dot of the dotted mountain (look design 6.10): its centre and radius in the drawing's points, and its group.
public struct MountainDot: Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var radius: Double
    /// 0, 1 or 2: the drawing's groups in order, each drawn at `MountainArt.strengths[strength]`.
    public var strength: Int

    public init(x: Double, y: Double, radius: Double, strength: Int) {
        self.x = x
        self.y = y
        self.radius = radius
        self.strength = strength
    }
}

/// The dotted mountain at the lower right of the Add a Mac page (look design 6.10): decoration, drawn from a table of
/// dots, never from an image file. `width`, `height`, `strengths` and `table` are generated from
/// `docs/superpowers/specs/look-2026-11-25/dotted-mountain.svg` by `scripts/embed-dot-art.sh`
/// (`MountainArtTable.swift`), whose `--check` `scripts/check.sh` runs.
public enum MountainArt {
    /// The table read four numbers at a time. Each is divided, never multiplied by 0.1 or 0.01: a product can differ
    /// from the literal the drawing writes, and the tests compare exactly.
    public static let dots: [MountainDot] = readTable()

    /// A plain loop with every type written out: the compiler on CI's macOS 26 runner could not type-check a
    /// `stride(...).map` closure over the table in reasonable time (pull request 179's first run).
    private static func readTable() -> [MountainDot] {
        var dots: [MountainDot] = []
        dots.reserveCapacity(table.count / 4)
        var i = 0
        while i + 3 < table.count {
            let x: Double = Double(table[i]) / 10
            let y: Double = Double(table[i + 1]) / 10
            let radius: Double = Double(table[i + 2]) / 100
            let strength: Int = Int(table[i + 3])
            dots.append(MountainDot(x: x, y: y, radius: radius, strength: strength))
            i += 4
        }
        return dots
    }
}
