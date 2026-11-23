import Foundation

/// What the menu shows: its lines and the notice line above them (what the last action said).
public struct MenuShown: Sendable, Equatable {
    public var menu: MenuLines
    public var notice: String?

    public init(menu: MenuLines, notice: String?) {
        self.menu = menu
        self.notice = notice
    }
}

/// Keeps an open menu still while it shows a submenu (issue #107, decision 3).
///
/// On GitHub's macOS 15 and 26 runners every change to the menu's content, a changed title included,
/// closed an open submenu; it came back only while the pointer rested on its parent row, and a click
/// where it had been closed the whole menu and ran nothing (`trial-submenus` branch, question 5). So:
/// - a menu equal to the one on screen is never published again;
/// - while the menu is open and the menu on screen has at least one submenu, a different menu, or a
///   different notice, waits; a newer one replaces what waits;
/// - when the menu closes, changes keep waiting in the same way for a short moment (`closingWait` in
///   `MenuOnScreen`, 300 milliseconds); when that moment has passed and the menu has not begun to
///   open again, what waits is shown and changes go through at once again. On the same runners AppKit
///   posted the end of tracking about 2 ms before it sent the clicked line's action (question 6), so a
///   change shown inside the close notice would reach the screen between a click and its action;
/// - what waits is also shown when the menu next begins to open, so a missed "closed" notice can never
///   freeze the menu for good; that opening makes the moment after an earlier close void;
/// - a menu on screen with no submenu (every state that is not Ready) updates at once, as before.
///
/// It is pure: the app feeds it AppKit's two notices, `NSMenu.didBeginTrackingNotification` (`menuBegan`)
/// and `NSMenu.didEndTrackingNotification` (`menuEnded`), and `MenuOnScreen` tells it when the moment
/// after a close has passed (`closingPassed`). Each call returns what to put on screen now, or nil when
/// the screen stays as it is; `menuEnded` returns the close whose moment `MenuOnScreen` waits out.
public struct HoldStill: Sendable, Equatable {
    /// One close of the menu. A timer carries it back to `closingPassed`, which acts only when it is
    /// still the latest close and the menu has not begun to open since.
    public struct Closing: Sendable, Equatable {
        fileprivate let number: UInt64
    }

    /// Where the menu is.
    public enum Phase: Sendable, Equatable {
        /// Changes go through at once.
        case closed
        /// Between a begin and an end of tracking.
        case open
        /// From an end of tracking until the moment after it has passed. Changes wait as while open.
        case closing(Closing)
    }

    /// What the menu shows now.
    public private(set) var onScreen: MenuShown
    /// The newest menu that differs from the one on screen and is held back until the moment after the
    /// menu closes has passed, or until it next begins to open.
    public private(set) var waiting: MenuShown?
    /// Closed, open, or closing.
    public private(set) var phase: Phase = .closed
    /// How many closes there have been; numbers each `Closing`, so an earlier one's timer is told apart.
    private var closes: UInt64 = 0

    /// Between a begin and an end of tracking.
    public var isOpen: Bool { phase == .open }

    public init(_ first: MenuShown) {
        onScreen = first
    }

    /// A new menu or notice from the refresher.
    public mutating func offer(_ next: MenuShown) -> MenuShown? {
        if next == onScreen {
            waiting = nil   // what waited is older than this, which is already on screen
            return nil
        }
        if phase != .closed && onScreen.menu.hasSubmenu {
            waiting = next
            return nil
        }
        return show(next)
    }

    /// The menu began to open. What waits is applied now, in case the last close was never heard, and
    /// the moment after an earlier close, if one is running, no longer counts.
    public mutating func menuBegan() -> MenuShown? {
        phase = .open
        return applyWaiting()
    }

    /// The menu closed. Nothing is shown now: what waits keeps waiting until the moment after this close
    /// has passed. The caller waits that moment and then passes the returned close to `closingPassed`.
    public mutating func menuEnded() -> Closing {
        closes &+= 1
        let closing = Closing(number: closes)
        phase = .closing(closing)
        return closing
    }

    /// The moment after `closing` has passed. If the menu is still in that close (no later close, and no
    /// opening since), it counts as closed and what waits is shown; otherwise this is a late timer and
    /// does nothing.
    public mutating func closingPassed(_ closing: Closing) -> MenuShown? {
        guard phase == .closing(closing) else { return nil }
        phase = .closed
        return applyWaiting()
    }

    private mutating func applyWaiting() -> MenuShown? {
        guard let next = waiting else { return nil }
        return show(next)
    }

    private mutating func show(_ next: MenuShown) -> MenuShown {
        onScreen = next
        waiting = nil
        return next
    }
}
