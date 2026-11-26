import Foundation
import Testing
@testable import MacMoshKit

/// The look's values (look design, section 5): the tokens in every appearance, WCAG 2's contrast, the pairs of text
/// on background the window draws, and the sizes.
@Suite struct LookTests {
    @Test func theContrastFunctionIsWCAGs() {
        #expect(abs(Contrast.ratio(LookRGB(0xFFFFFF), LookRGB(0x000000)) - 21) < 0.001)
        #expect(abs(Contrast.ratio(LookRGB(0x767676), LookRGB(0xFFFFFF)) - 4.54) < 0.01)
        #expect(abs(Contrast.ratio(LookRGB(0x777777), LookRGB(0xFFFFFF)) - 4.48) < 0.01)
        #expect(Contrast.ratio(LookRGB(0x1D1C1A), LookRGB(0xF0EFED)) == Contrast.ratio(LookRGB(0xF0EFED), LookRGB(0x1D1C1A)))
        #expect(Contrast.luminance(LookRGB(0x000000)) == 0 && Contrast.luminance(LookRGB(0xFFFFFF)) == 1)
        // WCAG 2.2's threshold is 0.04045: 10 / 255 (0.0392) is under both it and the older 0.03928, 11 / 255 (0.0431)
        // over both, so the two agree on every 8-bit value. The linear part below it is c / 12.92.
        #expect(abs(Contrast.luminance(LookRGB(0x0A0A0A)) - (10.0 / 255) / 12.92) < 1e-12)
        #expect(Contrast.minimum == 4.5 && Contrast.increased == 7.0)
    }

    /// 4.5:1 in light and dark, 7:1 with increased contrast, for every pair.
    @Test func everyPairReachesItsContrast() {
        for p in Look.pairs + Look.reservedPairs {
            for a in LookAppearance.allCases {
                #expect(Look.ratio(p, in: a) >= (a.isIncreased ? Contrast.increased : Contrast.minimum), "\(p) in \(a)")
            }
        }
    }

    /// The design's values; a value the contrast tests move is changed here too, and listed in the pull request.
    /// No light or dark value moved. `clayArt` waits for the art (step 3).
    @Test func theTokensAreTheDesigns() {
        let design: [(LookToken, UInt32, UInt32)] = [
            (.ink, 0x1D1C1A, 0xF3F1EE), (.ink2, 0x55524E, 0xB9B5AE), (.ink3, 0x6B6762, 0x9D9992),
            (.ground, 0xF0EFED, 0x1B1A19), (.surface, 0xFFFFFF, 0x2A2928), (.surface2, 0xF7F6F4, 0x222120),
            (.hairline, 0xE0DEDA, 0x3A3836), (.ember, 0xE4572E, 0xFF7A4D), (.emberText, 0xB93F12, 0xFF7A4D),
            (.glow, 0xF7C948, 0xF7C948), (.clayCell, 0xD5D2CD, 0x4A4744), (.clayOutline, 0xA9A49D, 0x8A867F),
            (.green, 0x2A7230, 0x7BC67E), (.amber, 0x8A5300, 0xF0B44C),
            (.red, 0xB3261E, 0xFF8A7A), (.onPrimary, 0xFFFFFF, 0x1B1A19)]
        #expect(design.map(\.0) == LookToken.allCases)
        for (t, light, dark) in design {
            #expect(Look.value(t, in: .light) == LookRGB(light) && Look.value(t, in: .dark) == LookRGB(dark), "\(t)")
        }
    }

    /// Design 5.1: text greys step up one token, hairlines become ink-3, the rest stay; a moved value replaces its line.
    /// ink-3 in light with increased contrast is ink-2 moved 3 per cent toward black (#55524E to #52504C), for 7:1 on
    /// the ground.
    @Test func increasedContrastStepsTextAndHairlinesUp() {
        for (plain, more) in [(LookAppearance.light, LookAppearance.lightIncreased), (.dark, .darkIncreased)] {
            for (t, from) in [(LookToken.ink2, LookToken.ink), (.ink3, .ink2), (.hairline, .ink3)]
                where !(plain == .light && t == .ink3) {
                #expect(Look.value(t, in: more) == Look.value(from, in: plain), "\(t)")
            }
            for t in [LookToken.ink, .ground, .surface, .surface2, .ember, .glow, .clayCell, .clayOutline, .onPrimary] {
                #expect(Look.value(t, in: more) == Look.value(t, in: plain), "\(t)")
            }
        }
        #expect(Look.value(.ink3, in: .lightIncreased) == LookRGB(0x52504C))
    }

    /// The "builder computes" tokens (design 5.1): each started as its plain value and moved, toward black in light and
    /// toward white in dark, until its pairs reach 7:1. The pull request lists each move. Red in light increased moved
    /// again in step 2, from #9A211A to #952019, for 7:1 on a pressed tile (`aPressedButtonKeepsItsContrast`).
    @Test func theBuilderComputedTheIncreasedColours() {
        let computed: [(LookToken, UInt32, UInt32)] = [
            (.emberText, 0x8E310E, 0xFF9A78), (.green, 0x225B26, 0x7BC67E),
            (.amber, 0x804D00, 0xF0B44C), (.red, 0x952019, 0xFF998B)]
        for (t, light, dark) in computed {
            #expect(Look.value(t, in: .lightIncreased) == LookRGB(light) && Look.value(t, in: .darkIncreased) == LookRGB(dark),
                    "\(t)")
        }
    }

    @Test func theAppearanceNamesPickTheirTables() {   // Review Focus 4
        let names = ["NSAppearanceNameAqua": LookAppearance.light, "NSAppearanceNameDarkAqua": .dark,
                     "NSAppearanceNameAccessibilityHighContrastAqua": .lightIncreased,
                     "NSAppearanceNameAccessibilityHighContrastDarkAqua": .darkIncreased, "NSAppearanceNameVibrantDark": .dark]
        for (name, table) in names { #expect(LookAppearance.of(appearanceName: name) == table, "\(name)") }
        #expect(LookAppearance.darkIncreased.isDark && LookAppearance.darkIncreased.isIncreased)
        #expect(!LookAppearance.light.isDark && !LookAppearance.dark.isIncreased)
    }

    @Test func everyTextRoleIsDrawnOnSomeBackground() {
        for role in TextRole.allCases where role != .warm { #expect(Look.pairs.contains { $0.text == role }, "\(role)") }
        #expect(Set(Look.pairs).count == Look.pairs.count)
        #expect(Look.reservedPairs == [LookPair(text: .warm, background: .ground), LookPair(text: .warm, background: .surface)])
    }

    /// Each role names its token; the primary button's background is ink.
    @Test func eachRoleHasItsToken() {
        #expect(TextRole.allCases.map(\.token) == [.ink, .ink2, .ink3, .green, .amber, .red, .onPrimary, .emberText])
        #expect(BackgroundRole.allCases.map(\.token) == [.ground, .surface, .surface2, .ink])
        #expect(LookRGB(0xB93F12).description == "#B93F12")
        #expect(LookRGB(0xB93F12) == LookRGB(0xB93F12) && LookRGB(0xB93F12).red == 0xB9 && LookRGB(0xB93F12).blue == 0x12)
    }

    /// Design 6.4: one primary button per page, Restart… set apart, red words for what removes or forgets.
    @Test func eachButtonHasItsKind() {
        #expect(ButtonKind.of(.window(.newDesk(workhorse: "attic"))) == .primary && ButtonKind.of(.menu(.tab(["pair"]))) == .primary)
        #expect(ButtonKind.of(.menu(.tab(["restart", "attic"]))) == .setApart)
        #expect(ButtonKind.of(.window(.remove(workhorse: "attic", desk: "website"))) == .destructive)
        #expect(ButtonKind.of(.window(.forget(workhorse: "attic", desk: "shop"))) == .destructive)
        #expect(ButtonKind.of(BoardAction(ButtonRules.removeMacMosh("attic").action)) == .destructive)
        for a: BoardAction in [.menu(.refresh), .menu(.tab(["prepare", "attic", "--pause"])),
                               .window(.rename(workhorse: "attic", desk: "api")),
                               .window(.openAllWithoutTab(workhorse: "attic", tabs: [])),
                               .window(.startAgain(workhorse: "attic", desk: "shop", keepIt: false)),
                               .menu(.tab(["pair", "attic"])), .menu(.tab(["restart"]))] {
            #expect(ButtonKind.of(a) == .secondary, "\(a)")
        }
        for k in [ButtonKind.primary, .secondary, .setApart, .destructive] { #expect(Look.pairs.contains(k.words), "\(k)") }
        #expect(ButtonKind.primary.words == LookPair(text: .onPrimary, background: .primary))
        #expect(ButtonKind.secondary.words == LookPair(text: .primary, background: .surface))
        #expect(ButtonKind.setApart.words == LookPair(text: .primary, background: .ground))
        #expect(ButtonKind.destructive.words == LookPair(text: .cannot, background: .surface))
    }

    /// Design 5.1, 5.2 and 6.5.
    @Test func theSizesAreTheDesigns() {
        #expect(LookSize.deskTile == 40)
        #expect(LookSize.deskTileRadius == 10)
        #expect(LookSize.smallTile == 28)
        #expect(LookSize.smallTileRadius == 8)
        #expect(LookSize.buttonHeight == 28)
        #expect(LookSize.buttonRadius == 8)
        #expect(LookSize.panelRadius == 12)
        #expect(LookSize.shadowY == 1)
        #expect(LookSize.shadowBlur == 2)
        #expect(LookSize.shadowOpacity == 0.08)
        #expect(LookSize.ringOpacity == 0.04)
        #expect(LookSize.ringWidth == 1)
        #expect(LookSize.cell == 6)
        #expect(LookSize.cellGap == 3)
        #expect(LookSize.cellRadius == 1.5)
        #expect(LookSize.rowHeight == 52)
        #expect(LookSize.sidebarWidth == 200)
        #expect(LookSize.stateCellWidth == 92)
        #expect(LookSize.nameMaxWidth == 200)
        #expect(LookSize.resultLines == 2)
        #expect(LookSize.titleFont == 22)
        #expect(LookSize.bodyFont == 13)
        #expect(LookSize.secondFont == 12)
        #expect(LookSize.tagFont == 11)
        #expect(LookSize.smallButtonHeight == 24 && LookSize.pagePadding == 20 && LookSize.panelPadding == 12)
        #expect(LookSize.detailsInset == 22)
        #expect(LookSize.detailsStackBelowPageWidth == 620 && LookSize.detailsStackBelowColumnsWidth == 534)
        #expect(LookSize.windowNamesFewest == 4)
    }

    /// Side by side, the details' facts keep their own width and the window lines take the rest, so a long window name
    /// is cut and the facts are not; the lines never get less than half the width. The numbers are run 3's at 880
    /// points: the lines 300 wide, the facts 231, 578 points offered, 25 between them (two gaps and the hairline).
    @Test func sideBySideTheFactsKeepTheirWidthAndALongWindowNameGivesWay() {
        #expect(LookSize.detailsColumnGap == 12)
        let between = 2 * LookSize.detailsColumnGap + 1
        // The sample's names: the lines keep their own width.
        #expect(LookSize.detailsLinesWidth(offered: 578, lines: 300, facts: 231) == 300)
        // A 32-letter name makes the lines 480 wide: they give way, and the facts keep 231.
        let long = LookSize.detailsLinesWidth(offered: 578, lines: 480, facts: 231)
        #expect(long == 578 - between - 231)
        // Lines wider than the whole width: the facts still start inside it, at their own width.
        let wider = LookSize.detailsLinesWidth(offered: 578, lines: 900, facts: 231)
        #expect(wider + between + 231 == 578)
        // Facts wider than half: the lines keep half the width, never less.
        #expect(LookSize.detailsLinesWidth(offered: 534, lines: 300, facts: 400) == 267)
        // Short lines stay short.
        #expect(LookSize.detailsLinesWidth(offered: 534, lines: 120, facts: 231) == 120)
    }

    /// Design 6.6 and 6.7: a window's name, a fact's value and "Keeps its command running" (primary), "in a tab" and
    /// "open in another tab" (good), "not in a tab", a fact's label and the greyed list (tertiary), all on surface-2.
    @Test func theDetailsAndTheGreyedListHaveTheirPairs() {   // everyPairReachesItsContrast then covers them
        for p in [LookPair(text: .primary, background: .surface2), LookPair(text: .good, background: .surface2),
                  LookPair(text: .tertiary, background: .surface2)] {
            #expect(Look.pairs.contains(p), "\(p)")
        }
    }

    /// Our own floor, borrowing WCAG 2.2 1.4.11's 3:1: a mark beside words reaches 3:1 against what it sits on.
    @Test func everyMarkBesideWordsReachesThreeToOne() {
        #expect(Contrast.nonText == 3.0)
        #expect(Look.marks == [LookMark(token: .green, background: .ground), LookMark(token: .red, background: .ground),
                               LookMark(token: .ink3, background: .ground), LookMark(token: .ink2, background: .ground)])
        #expect(LookMark(token: .green, background: .ground).description == "green on ground")
        for m in Look.marks {
            for a in LookAppearance.allCases { #expect(Look.ratio(m, in: a) >= Contrast.nonText, "\(m) in \(a)") }
        }
    }

    /// A pressed button lays black at 8 per cent over its fill, under its words; the words, not darkened, still reach
    /// their pair's contrast on the darkened fill.
    @Test func aPressedButtonKeepsItsContrast() {   // Review Focus 4
        #expect(LookSize.pressedOverlay == 0.08 && Look.pressed(LookRGB(0xFFFFFF)) == LookRGB(0xEBEBEB))
        #expect(LookRGB(red: 0xB9, green: 0x3F, blue: 0x12) == LookRGB(0xB93F12))
        for k in [ButtonKind.primary, .secondary, .setApart, .destructive] {
            for a in LookAppearance.allCases {
                let r = Contrast.ratio(Look.value(k.words.text.token, in: a), Look.pressed(Look.value(k.words.background.token, in: a)))
                #expect(r >= (a.isIncreased ? Contrast.increased : Contrast.minimum), "\(k) in \(a)")
            }
        }
    }
}
