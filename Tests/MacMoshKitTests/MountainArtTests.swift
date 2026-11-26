import Foundation
import Testing
@testable import MacMoshKit

/// The dotted mountain on the Add a Mac page (look design 6.10), as the table `scripts/embed-dot-art.sh` generates from
/// `docs/superpowers/specs/look-2026-11-25/dotted-mountain.svg`. `scripts/check.sh` runs the script's `--check`, so the
/// table is the drawing; these tests pin what the drawing holds.
@Suite struct MountainArtTests {
    /// Design 6.10: dotted-mountain.svg, 560 by 420 points, 1,506 dots in three strengths of clay.
    @Test func theTableIsTheDrawing() {
        #expect(MountainArt.width == 560 && MountainArt.height == 420 && MountainArt.strengths == [0.42, 0.55, 0.95])
        #expect(MountainArt.table.count == 4 * 1506 && MountainArt.dots.count == 1506)
        #expect([0, 1, 2].map { s in MountainArt.dots.filter { $0.strength == s }.count } == [382, 74, 1050])
        #expect(MountainArt.dots.first == MountainDot(x: 112.5, y: 202.5, radius: 1.35, strength: 0))
        #expect(MountainArt.dots.last == MountainDot(x: 542.5, y: 402.5, radius: 1.59, strength: 2))
    }

    /// 1,479 dots sit on the 5-point grid (2.5 + 5k); the 27 of the faint lines in the sky do not, and the table keeps
    /// each where it is drawn. Every dot is inside the drawing, and no two share a place.
    @Test func everyDotIsInsideTheDrawingInItsOwnPlace() {
        let onGrid = MountainArt.dots.filter {
            ($0.x - 2.5).truncatingRemainder(dividingBy: 5) == 0 && ($0.y - 2.5).truncatingRemainder(dividingBy: 5) == 0
        }
        #expect(onGrid.count == 1479)
        #expect(MountainArt.dots.filter { !onGrid.contains($0) }.allSatisfy { $0.radius == 1.2 && $0.strength == 1 })
        #expect(MountainArt.dots.allSatisfy {
            $0.x - $0.radius >= 0 && $0.x + $0.radius <= 560 && $0.y - $0.radius >= 0 && $0.y + $0.radius <= 420
        })
        #expect(Set(MountainArt.dots.map { "\($0.x) \($0.y)" }).count == 1506)
    }
}
