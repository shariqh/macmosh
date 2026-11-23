import Foundation
import Testing
@testable import MacMoshKit

/// A menu with one row that opens a submenu, titled `title`.
private func withSubmenu(_ title: String = "A") -> MenuLines {
    MenuLines(symbol: "checkmark.circle", entries: [
        MenuEntry(id: "wh:a", title: title, submenu: [MenuEntry(id: "wh:a:share", title: "Share screen", action: .run(["screen", "a"]))]),
    ])
}

/// A flat menu, titled `title`.
private func flat(_ title: String = "B") -> MenuLines {
    MenuLines(symbol: "lock.circle", entries: [MenuEntry(id: "wh:a", title: title)])
}

private func shown(_ menu: MenuLines, _ notice: String? = nil) -> MenuShown { MenuShown(menu: menu, notice: notice) }

/// The rule that keeps an open menu with a submenu still (issue #107, decision 3): every branch.
/// Three phases: closed, open (between a begin and an end of tracking), and closing (from an end of
/// tracking until the moment after it has passed). Changes wait in the last two alike.
@Suite struct HoldStillTests {
    @Test func aMenuEqualToTheOneOnScreenIsNeverPublishedAgain() {
        var hold = HoldStill(shown(withSubmenu()))
        #expect(hold.offer(shown(withSubmenu())) == nil)
        _ = hold.menuBegan()
        #expect(hold.offer(shown(withSubmenu())) == nil)
        let closing = hold.menuEnded()
        #expect(hold.offer(shown(withSubmenu())) == nil)
        #expect(hold.closingPassed(closing) == nil)
        var flatHold = HoldStill(shown(flat()))
        #expect(flatHold.offer(shown(flat())) == nil)
    }

    @Test func itStartsClosed() {
        let hold = HoldStill(shown(withSubmenu()))
        #expect(hold.phase == .closed)
        #expect(!hold.isOpen)
    }

    @Test func whileClosedADifferentMenuIsPublishedAtOnce() {
        var hold = HoldStill(shown(withSubmenu()))
        #expect(hold.offer(shown(withSubmenu("A2"))) == shown(withSubmenu("A2")))
        #expect(hold.onScreen == shown(withSubmenu("A2")))
        #expect(hold.offer(shown(flat())) == shown(flat()))
    }

    @Test func whileOpenWithASubmenuOnScreenADifferentMenuWaits() {
        var hold = HoldStill(shown(withSubmenu()))
        #expect(hold.menuBegan() == nil)
        #expect(hold.phase == .open)
        #expect(hold.offer(shown(withSubmenu("A2"))) == nil)
        #expect(hold.offer(shown(flat())) == nil)   // a flat one waits too: the submenu on screen is what matters
        #expect(hold.onScreen == shown(withSubmenu()))
        #expect(hold.waiting == shown(flat()))      // the newest waits
    }

    /// AppKit posts the end of tracking before it sends the clicked line's action (the trial, question 6),
    /// so the close shows nothing: what waits keeps waiting until the moment after the close has passed.
    @Test func theCloseShowsNothingAndWhatWaitsKeepsWaiting() {
        var hold = HoldStill(shown(withSubmenu()))
        _ = hold.menuBegan()
        _ = hold.offer(shown(withSubmenu("A2")))
        let closing = hold.menuEnded()
        #expect(hold.phase == .closing(closing))
        #expect(!hold.isOpen)
        #expect(hold.onScreen == shown(withSubmenu()))
        #expect(hold.waiting == shown(withSubmenu("A2")))
    }

    @Test func whileClosingADifferentMenuWaitsAndTheNewestWins() {
        var hold = HoldStill(shown(withSubmenu()))
        _ = hold.menuBegan()
        _ = hold.menuEnded()
        #expect(hold.offer(shown(withSubmenu("A2"))) == nil)
        #expect(hold.offer(shown(withSubmenu("A3"))) == nil)
        #expect(hold.onScreen == shown(withSubmenu()))
        #expect(hold.waiting == shown(withSubmenu("A3")))
    }

    @Test func whatWaitsIsShownWhenTheMomentAfterTheClosePasses() {
        var hold = HoldStill(shown(withSubmenu()))
        _ = hold.menuBegan()
        _ = hold.offer(shown(withSubmenu("A2")))
        let closing = hold.menuEnded()
        #expect(hold.closingPassed(closing) == shown(withSubmenu("A2")))
        #expect(hold.onScreen == shown(withSubmenu("A2")))
        #expect(hold.waiting == nil)
        #expect(hold.phase == .closed)
        #expect(hold.closingPassed(closing) == nil)   // nothing left, and it is closed
    }

    @Test func afterTheMomentHasPassedChangesGoThroughAtOnce() {
        var hold = HoldStill(shown(withSubmenu()))
        _ = hold.menuBegan()
        let closing = hold.menuEnded()
        #expect(hold.closingPassed(closing) == nil)   // nothing waited
        #expect(hold.phase == .closed)
        #expect(hold.offer(shown(withSubmenu("A2"))) == shown(withSubmenu("A2")))
    }

    @Test func whatWaitsIsAppliedWhenTheMenuNextOpensIfTheCloseWasMissed() {
        var hold = HoldStill(shown(withSubmenu()))
        _ = hold.menuBegan()
        _ = hold.offer(shown(withSubmenu("A2")))
        // No "closed" notice came. The next opening applies it.
        #expect(hold.menuBegan() == shown(withSubmenu("A2")))
        #expect(hold.onScreen == shown(withSubmenu("A2")))
        #expect(hold.waiting == nil)
        #expect(hold.isOpen)
    }

    /// The menu opens again before the moment after its close has passed: what waits is shown at once,
    /// as at any opening, and the menu counts as open. The earlier close's timer, arriving late, does nothing.
    @Test func anOpeningDuringTheMomentShowsWhatWaitsAndVoidsTheLateTimer() {
        var hold = HoldStill(shown(withSubmenu()))
        _ = hold.menuBegan()
        _ = hold.offer(shown(withSubmenu("A2")))
        let closing = hold.menuEnded()
        #expect(hold.menuBegan() == shown(withSubmenu("A2")))
        #expect(hold.phase == .open)
        #expect(hold.offer(shown(withSubmenu("A3"))) == nil)   // open with a submenu: it waits
        #expect(hold.closingPassed(closing) == nil)            // late: void
        #expect(hold.phase == .open)
        #expect(hold.onScreen == shown(withSubmenu("A2")))
        #expect(hold.waiting == shown(withSubmenu("A3")))
    }

    /// Two closes in a row: only the moment after the second counts. The first's timer does nothing.
    @Test func twoClosesInARowOnlyTheLastMomentCounts() {
        var hold = HoldStill(shown(withSubmenu()))
        _ = hold.menuBegan()
        _ = hold.offer(shown(withSubmenu("A2")))
        let first = hold.menuEnded()
        let second = hold.menuEnded()
        #expect(first != second)
        #expect(hold.phase == .closing(second))
        #expect(hold.closingPassed(first) == nil)   // late: void, still closing
        #expect(hold.phase == .closing(second))
        #expect(hold.waiting == shown(withSubmenu("A2")))
        #expect(hold.closingPassed(second) == shown(withSubmenu("A2")))
        #expect(hold.phase == .closed)
    }

    /// A timer from a close two openings ago does nothing once a later close is under way.
    @Test func aTimerFromAnEarlierOpeningDoesNothingDuringALaterClose() {
        var hold = HoldStill(shown(withSubmenu()))
        _ = hold.menuBegan()
        let old = hold.menuEnded()
        _ = hold.menuBegan()
        _ = hold.offer(shown(withSubmenu("A2")))
        let now = hold.menuEnded()
        #expect(hold.closingPassed(old) == nil)
        #expect(hold.phase == .closing(now))
        #expect(hold.closingPassed(now) == shown(withSubmenu("A2")))
    }

    @Test func aTimerArrivingWhenAlreadyClosedDoesNothing() {
        var hold = HoldStill(shown(withSubmenu()))
        let closing = hold.menuEnded()
        #expect(hold.closingPassed(closing) == nil)
        #expect(hold.closingPassed(closing) == nil)
        #expect(hold.phase == .closed)
    }

    @Test func theMenuOpeningWithNothingWaitingPublishesNothing() {
        var hold = HoldStill(shown(withSubmenu()))
        #expect(hold.menuBegan() == nil)
        #expect(hold.isOpen)
        let closing = hold.menuEnded()
        #expect(!hold.isOpen)
        #expect(hold.closingPassed(closing) == nil)
        #expect(hold.phase == .closed)
    }

    @Test func aMenuWithNoSubmenuOnScreenUpdatesAtOnceEvenWhileOpen() {
        var hold = HoldStill(shown(flat()))
        _ = hold.menuBegan()
        #expect(hold.offer(shown(flat("B2"))) == shown(flat("B2")))
        // Once a menu with a submenu is on screen, the next change waits.
        #expect(hold.offer(shown(withSubmenu())) == shown(withSubmenu()))
        #expect(hold.offer(shown(withSubmenu("A2"))) == nil)
        let closing = hold.menuEnded()
        #expect(hold.closingPassed(closing) == shown(withSubmenu("A2")))
    }

    @Test func aMenuWithNoSubmenuOnScreenUpdatesAtOnceWhileClosing() {
        var hold = HoldStill(shown(flat()))
        _ = hold.menuBegan()
        let closing = hold.menuEnded()
        #expect(hold.offer(shown(flat("B2"))) == shown(flat("B2")))
        #expect(hold.closingPassed(closing) == nil)
    }

    @Test func theNoticeFollowsTheSameRule() {
        var hold = HoldStill(shown(withSubmenu()))
        #expect(hold.offer(shown(withSubmenu(), "The tab didn't open.")) == shown(withSubmenu(), "The tab didn't open."))
        #expect(hold.offer(shown(withSubmenu(), "The tab didn't open.")) == nil)
        _ = hold.menuBegan()
        #expect(hold.offer(shown(withSubmenu(), nil)) == nil)
        #expect(hold.onScreen.notice == "The tab didn't open.")
        let closing = hold.menuEnded()
        #expect(hold.offer(shown(withSubmenu(), "Another")) == nil)   // waits while closing too
        #expect(hold.onScreen.notice == "The tab didn't open.")
        #expect(hold.closingPassed(closing) == shown(withSubmenu(), "Another"))

        var flatHold = HoldStill(shown(flat()))
        _ = flatHold.menuBegan()
        #expect(flatHold.offer(shown(flat(), "no screen sharing")) == shown(flat(), "no screen sharing"))
    }

    @Test func aMenuEqualToTheOneOnScreenDropsWhatWaited() {
        var hold = HoldStill(shown(withSubmenu()))
        _ = hold.menuBegan()
        _ = hold.offer(shown(withSubmenu("A2")))
        // The newest is the one on screen again, so nothing changes when the moment after the close passes.
        #expect(hold.offer(shown(withSubmenu())) == nil)
        #expect(hold.waiting == nil)
        let closing = hold.menuEnded()
        #expect(hold.closingPassed(closing) == nil)
        #expect(hold.onScreen == shown(withSubmenu()))
    }

    @Test func aCloseWithNoOpenBeforeItWaitsForItsMomentThenChangesGoThrough() {
        // An end with no begin before it: it counts as a close, so the moment after it applies too.
        var hold = HoldStill(shown(withSubmenu()))
        let closing = hold.menuEnded()
        #expect(hold.offer(shown(withSubmenu("A2"))) == nil)
        #expect(hold.closingPassed(closing) == shown(withSubmenu("A2")))
        #expect(hold.offer(shown(withSubmenu("A3"))) == shown(withSubmenu("A3")))
    }
}
