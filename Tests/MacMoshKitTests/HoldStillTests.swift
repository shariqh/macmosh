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
@Suite struct HoldStillTests {
    @Test func aMenuEqualToTheOneOnScreenIsNeverPublishedAgain() {
        var hold = HoldStill(shown(withSubmenu()))
        #expect(hold.offer(shown(withSubmenu())) == nil)
        _ = hold.menuBegan()
        #expect(hold.offer(shown(withSubmenu())) == nil)
        #expect(hold.menuEnded() == nil)
        var flatHold = HoldStill(shown(flat()))
        #expect(flatHold.offer(shown(flat())) == nil)
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
        #expect(hold.offer(shown(withSubmenu("A2"))) == nil)
        #expect(hold.offer(shown(flat())) == nil)   // a flat one waits too: the submenu on screen is what matters
        #expect(hold.onScreen == shown(withSubmenu()))
        #expect(hold.waiting == shown(flat()))      // the newest waits
    }

    @Test func whatWaitsIsAppliedWhenTheMenuCloses() {
        var hold = HoldStill(shown(withSubmenu()))
        _ = hold.menuBegan()
        _ = hold.offer(shown(withSubmenu("A2")))
        #expect(hold.menuEnded() == shown(withSubmenu("A2")))
        #expect(hold.onScreen == shown(withSubmenu("A2")))
        #expect(hold.waiting == nil)
        #expect(hold.menuEnded() == nil)   // nothing left
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

    @Test func theMenuOpeningWithNothingWaitingPublishesNothing() {
        var hold = HoldStill(shown(withSubmenu()))
        #expect(hold.menuBegan() == nil)
        #expect(hold.isOpen)
        #expect(hold.menuEnded() == nil)
        #expect(!hold.isOpen)
    }

    @Test func aMenuWithNoSubmenuOnScreenUpdatesAtOnceEvenWhileOpen() {
        var hold = HoldStill(shown(flat()))
        _ = hold.menuBegan()
        #expect(hold.offer(shown(flat("B2"))) == shown(flat("B2")))
        // Once a menu with a submenu is on screen, the next change waits.
        #expect(hold.offer(shown(withSubmenu())) == shown(withSubmenu()))
        #expect(hold.offer(shown(withSubmenu("A2"))) == nil)
        #expect(hold.menuEnded() == shown(withSubmenu("A2")))
    }

    @Test func theNoticeFollowsTheSameRule() {
        var hold = HoldStill(shown(withSubmenu()))
        #expect(hold.offer(shown(withSubmenu(), "The tab didn't open.")) == shown(withSubmenu(), "The tab didn't open."))
        #expect(hold.offer(shown(withSubmenu(), "The tab didn't open.")) == nil)
        _ = hold.menuBegan()
        #expect(hold.offer(shown(withSubmenu(), nil)) == nil)
        #expect(hold.onScreen.notice == "The tab didn't open.")
        #expect(hold.menuEnded() == shown(withSubmenu(), nil))

        var flatHold = HoldStill(shown(flat()))
        _ = flatHold.menuBegan()
        #expect(flatHold.offer(shown(flat(), "no screen sharing")) == shown(flat(), "no screen sharing"))
    }

    @Test func aMenuEqualToTheOneOnScreenDropsWhatWaited() {
        var hold = HoldStill(shown(withSubmenu()))
        _ = hold.menuBegan()
        _ = hold.offer(shown(withSubmenu("A2")))
        // The newest is the one on screen again, so nothing changes at close.
        #expect(hold.offer(shown(withSubmenu())) == nil)
        #expect(hold.waiting == nil)
        #expect(hold.menuEnded() == nil)
        #expect(hold.onScreen == shown(withSubmenu()))
    }

    @Test func aMissedOpenLeavesItClosedSoChangesGoThrough() {
        // An end with no begin before it, or two ends: the menu is closed, and changes are published.
        var hold = HoldStill(shown(withSubmenu()))
        #expect(hold.menuEnded() == nil)
        #expect(hold.offer(shown(withSubmenu("A2"))) == shown(withSubmenu("A2")))
    }
}
