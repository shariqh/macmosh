import AppKit
import Foundation
import Testing
@testable import MacMoshKit

/// Look step 6 (issue 183): the mark in the menu bar for each state, design section 9.
@Suite struct MenuBarMarkTests {
    let m = Set(IconArt.mCells)
    func all(_ look: MarkCell, _ cells: Set<IconCell>) -> [IconCell: MarkCell] {
        Dictionary(uniqueKeysWithValues: cells.map { ($0, look) }) }

    /// Design 9's table, read with the picture the owner chose.
    @Test func eachNameHasTheMarkOfTheDesignsTable() {
        let legs = m.subtracting(MenuBarMark.badgeHole)
        let row2 = Set((0..<5).map { IconCell(row: 2, column: $0) })
        let want: [(String, MenuBarMark)] = [
            ("checkmark.circle", MenuBarMark(cells: all(.solid, m), badge: nil)),
            ("exclamationmark.circle", MenuBarMark(cells: all(.solid, legs), badge: .exclamation)),
            ("person.crop.circle.badge.questionmark", MenuBarMark(cells: all(.solid, legs), badge: .person)),
            ("lock.circle", MenuBarMark(cells: all(.solid, legs), badge: .padlock)),
            ("exclamationmark.triangle", MenuBarMark(cells: all(.solid, legs), badge: .warning)),
            ("wifi.slash", MenuBarMark(cells: all(.hollow, legs), badge: .noEntry)),
            ("wrench.and.screwdriver", MenuBarMark(cells: all(.solid, legs), badge: .wrench)),
            ("ellipsis.circle", MenuBarMark(cells: all(.faint, m.subtracting(row2)).merging(all(.solid, row2)) { $1 }, badge: nil)),
            ("plus.circle", MenuBarMark(cells: all(.faint, legs), badge: .plus))]
        #expect(MenuBarMark.symbols == want.map(\.0))
        for (name, mark) in want { #expect(MenuBarMark.of(symbol: name) == mark, "\(name)") }
        #expect(MarkBadge.allCases.map(\.symbolName) == ["exclamationmark.circle.fill", "person.fill", "lock.fill",
            "exclamationmark.triangle.fill", "nosign", "wrench.fill", "plus"]) }

    /// Review Focus 1: every name the menu can carry, the refresher's own two included.
    @MainActor @Test func everyNameTheModelGivesHasAMark() async {
        let states: [WorkhorseState] = [.ready(signIns: true), .ready(signIns: false), .waitingForLogin, .locked, .cantVerify,
            .cantReach(.tailscaleOff), .cantReach(.noNetwork), .cantReach(.otherVPN), .cantReach(.awayAndOffline),
            .cantReach(.nothingAnswers), .notSetUp(.notPaired), .notSetUp(.identityUnusable), .notSetUp(.hostScriptMissing),
            .notSetUp(.hostScriptOutdated), .notSetUp(.unreadableReport), .notSetUp(.deskServerDown)]
        var names = Set(states.map(MenuModel.symbol(for:)))
        names.insert(MenuModel.build([]).symbol)
        names.insert(MenuModel.symbol(forAll: []))
        names.insert(MenuRefresher(load: { [] }, gather: { _ in [] }, save: { _ in }, log: { _ in }).menu.symbol)
        let damaged = MenuRefresher(load: { throw StoreError.unreadable("workhorses.json: not JSON") },
                                    gather: { _ in [] }, save: { _ in }, log: { _ in })
        await damaged.refresh()
        names.insert(damaged.menu.symbol)
        #expect(names == Set(MenuBarMark.symbols)) }

    /// Review Focus 3: faint and hollow cells count as drawn; the marks still differ.
    @Test func noTwoMarksShareAShapeEvenInOneColour() {
        let marks = MenuBarMark.symbols.map(MenuBarMark.of(symbol:))
        #expect(Set(marks).count == 9)
        #expect(Set(marks.map { MenuBarMark(cells: all(.solid, $0.drawn), badge: $0.badge) }).count == 9)
        #expect(Set(marks.compactMap(\.badge)).count == 7) }

    @Test func anUnknownNameDrawsTheStillCheckingMark() {   // Review Focus 4
        #expect(MenuBarMark.of(symbol: "gearshape") == MenuBarMark.of(symbol: "ellipsis.circle"))
        #expect(MenuBarMark.of(symbol: "") == MenuBarMark.of(symbol: "ellipsis.circle")) }

    @Test func everyBadgeIsASystemSymbolHere() {   // Review Focus 2; ci.yml runs it on macOS 15 and 26
        for b in MarkBadge.allCases { #expect(NSImage(systemSymbolName: b.symbolName, accessibilityDescription: nil) != nil, "\(b)") } }

    @Test func theSizesAreSectionNines() {
        #expect(MenuBarMark.box == 16 && MenuBarMark.inset == 1 && MenuBarMark.cell == 2 && MenuBarMark.gap == 1)
        #expect(MenuBarMark.cornerRadius == 0.5 && MenuBarMark.faintOpacity == 1.0 / 3 && MenuBarMark.hollowLine == 0.5)
        #expect(MenuBarMark.badgePointSize == 6 && MenuBarMark.badgeWeight == .bold)
        #expect(2 * MenuBarMark.inset + 5 * MenuBarMark.cell + 4 * MenuBarMark.gap == MenuBarMark.box)
        #expect(MenuBarMark.cellRect(IconCell(row: 0, column: 0)) == CGRect(x: 1, y: 1, width: 2, height: 2))
        #expect(MenuBarMark.cellRect(IconCell(row: 4, column: 4)) == CGRect(x: 13, y: 13, width: 2, height: 2))
        #expect(MenuBarMark.hollowRect(IconCell(row: 0, column: 0)) == CGRect(x: 1.25, y: 1.25, width: 1.5, height: 1.5))
        #expect(MenuBarMark.hollowCornerRadius == 0.25)
        #expect(MenuBarMark.alpha(.solid) == 1 && MenuBarMark.alpha(.hollow) == 1 && MenuBarMark.alpha(.faint) == 1.0 / 3)
        for r in 0..<5 { for c in 0..<5 {
            let o = MenuBarMark.cellRect(IconCell(row: r, column: c)).origin
            #expect(o.x == o.x.rounded() && o.y == o.y.rounded()) } }
        #expect(MenuBarMark.badgeRect == CGRect(x: 10, y: 10, width: 6, height: 6))
        #expect(MenuBarMark.badgeHole == [IconCell(row: 3, column: 4), IconCell(row: 4, column: 4)])
        for name in MenuBarMark.symbols where MenuBarMark.of(symbol: name).badge != nil {
            for cell in MenuBarMark.of(symbol: name).drawn {
                let r = MenuBarMark.cellRect(cell), b = MenuBarMark.badgeRect
                #expect(r.maxY + 1 <= b.minY || r.maxX + 1 <= b.minX, "\(name) \(cell)") } } }

    @Test func aBadgeFitsItsSquareAndStandsOnItsFoot() {
        #expect(MenuBarMark.badgeFrame(natural: CGSize(width: 8, height: 8)) == CGRect(x: 10, y: 10, width: 6, height: 6))
        #expect(MenuBarMark.badgeFrame(natural: CGSize(width: 8, height: 7)) == CGRect(x: 10, y: 10.75, width: 6, height: 5.25))
        let person = MenuBarMark.badgeFrame(natural: CGSize(width: 6, height: 7))
        #expect(abs(person.width - 36.0 / 7) < 1e-9 && person.height == 6 && person.maxY == 16 && abs(person.midX - 13) < 1e-9) }

    /// Decision 4: the menu-bar item keeps the words it has today. Push 1 (Menu pictures run 45883300450, macOS 15 and
    /// 26, light and dark) read them as the item's AXTitle; its AXDescription was empty for every state.
    @Test func theSpokenNamesAreTodays() {
        #expect(MenuBarMark.spokenName(for: "checkmark.circle") == "Selected")
        #expect(MenuBarMark.spokenName(for: "exclamationmark.circle") == "Error")
        #expect(MenuBarMark.spokenName(for: "person.crop.circle.badge.questionmark") == "person.crop.circle.badge.questionmark")
        #expect(MenuBarMark.spokenName(for: "lock.circle") == "Lock")
        #expect(MenuBarMark.spokenName(for: "exclamationmark.triangle") == "Warning")
        #expect(MenuBarMark.spokenName(for: "wifi.slash") == "Wi-Fi Off")
        #expect(MenuBarMark.spokenName(for: "wrench.and.screwdriver") == "wrench.and.screwdriver")
        #expect(MenuBarMark.spokenName(for: "ellipsis.circle") == "More")
        #expect(MenuBarMark.spokenName(for: "plus.circle") == "Add")
        #expect(MenuBarMark.spokenName(for: "gearshape") == MenuBarMark.spokenName(for: "ellipsis.circle")) }
}
