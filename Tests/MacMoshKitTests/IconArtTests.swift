import Foundation
import Testing
@testable import MacMoshKit

@Suite struct IconArtTests {
    /// Design 8.1: column 0 and column 4 in full, plus row 1 column 1, row 1 column 3 and row 2 column 2.
    @Test func theMIsThirteenCells() {
        var m = Set((0..<5).flatMap { [IconCell(row: $0, column: 0), IconCell(row: $0, column: 4)] })
        m.formUnion([IconCell(row: 1, column: 1), IconCell(row: 1, column: 3), IconCell(row: 2, column: 2)])
        #expect(IconArt.mCells.count == 13 && Set(IconArt.mCells) == m && IconArt.gridSize == 5)
        #expect(IconArt.mCells == IconArt.mCells.sorted { ($0.row, $0.column) < ($1.row, $1.column) })
        for r in 0..<5 { for c in 0..<5 {
            #expect(IconArt.isLit(IconCell(row: r, column: c)) == m.contains(IconCell(row: r, column: c)), "\(r),\(c)") } }
        for cell in IconArt.mCells { #expect(m.contains(IconCell(row: cell.row, column: 4 - cell.column))) } }
    @Test func theTilesSitOnTheGrid() {
        #expect(IconArt.canvas == 1024 && IconArt.tile == 140 && IconArt.gap == 30 && IconArt.tileRadius == 32)
        #expect(2 * IconArt.inset + 5 * IconArt.tile + 4 * IconArt.gap == IconArt.canvas)
        for (r, c, x, y) in [(0, 0, 102, 102), (1, 3, 612, 272), (4, 4, 782, 782)] {
            let o = IconArt.tileOrigin(IconCell(row: r, column: c))
            #expect(o.x == x && o.y == y, "\(r),\(c)") }
        #expect(IconArt.litTop == IconArt.inset && IconArt.litBottom == IconArt.canvas - IconArt.inset && IconArt.litBottom == 922) }
    /// The design's colours (8.1); lit runs over the whole grid, so each row of the M is a slice of one gradient.
    @Test func theColoursAreTheDesigns() {
        #expect(IconArt.ground(.light) == [IconStop(0, 0xFCFAF7), IconStop(1, 0xECE5DD)])
        #expect(IconArt.lit(.light) == [IconStop(0, 0xF29A55), IconStop(1, 0xD2481F)])
        #expect(IconArt.unlit(.light) == [IconStop(0, 0xFFFFFF), IconStop(1, 0xF4EEE7)])
        #expect(IconArt.ground(.dark) == [IconStop(0, 0x2A2928), IconStop(1, 0x1D1C1A)])
        #expect(IconArt.lit(.dark) == [IconStop(0, 0xFAD566), IconStop(1.0 / 3, 0xF7C948), IconStop(2.0 / 3, 0xF29343), IconStop(1, 0xE4572E)])
        #expect(IconArt.unlit(.dark) == [IconStop(0, 0x3B3835), IconStop(1, 0x2F2D2A)]) }
    /// At 16 pixels a solid M with no gaps, on whole pixels: light #E2552C on #F3EEE8; dark lit cells on #24221F.
    @Test func theSmallMIsSolid() {
        #expect(IconArt.small == 16 && IconArt.smallCell == 2 && IconArt.smallMOrigin == 3)
        #expect(IconArt.smallBodyOrigin == 1 && IconArt.smallBodySize == 14 && IconArt.smallBodyRadius == 3)
        #expect(IconArt.smallMOrigin + 5 * IconArt.smallCell <= IconArt.smallBodyOrigin + IconArt.smallBodySize - 2)
        for (r, c, x, y) in [(0, 0, 3, 3), (1, 3, 9, 5), (4, 4, 11, 11)] {
            let o = IconArt.smallCellOrigin(IconCell(row: r, column: c))
            #expect(o.x == x && o.y == y, "\(r),\(c)") }
        #expect(IconArt.smallGround(.light) == 0xF3EEE8 && IconArt.smallM(.light) == [IconStop(0, 0xE2552C), IconStop(1, 0xE2552C)])
        #expect(IconArt.smallGround(.dark) == 0x24221F && IconArt.smallM(.dark) == IconArt.lit(.dark)) }
    /// scripts/draw-icon/main.swift is compiled with this one file, so it may use nothing else (Review Focus 3).
    @Test func theTableNeedsNothingButTheStandardLibrary() throws {
        let source = try String(contentsOf: repoRoot().appendingPathComponent("Sources/MacMoshKit/Look/IconArt.swift"), encoding: .utf8)
        #expect(!source.split(separator: "\n").contains { $0.hasPrefix("import ") }) }
}
