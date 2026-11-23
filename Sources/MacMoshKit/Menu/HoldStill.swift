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
/// - what waits is applied when the menu closes, and also when it next begins to open, so a missed
///   "closed" notice can never freeze the menu for good;
/// - a menu on screen with no submenu (every state that is not Ready) updates at once, as before.
///
/// It is pure: the app feeds it AppKit's two notices, `NSMenu.didBeginTrackingNotification` (`menuBegan`)
/// and `NSMenu.didEndTrackingNotification` (`menuEnded`), and each call returns what to put on screen
/// now, or nil when the screen stays as it is.
public struct HoldStill: Sendable, Equatable {
    /// What the menu shows now.
    public private(set) var onScreen: MenuShown
    /// The newest menu that differs from the one on screen and is held back until the menu closes or opens.
    public private(set) var waiting: MenuShown?
    /// Between a begin and an end of tracking.
    public private(set) var isOpen = false

    public init(_ first: MenuShown) {
        onScreen = first
    }

    /// A new menu or notice from the refresher.
    public mutating func offer(_ next: MenuShown) -> MenuShown? {
        if next == onScreen {
            waiting = nil   // what waited is older than this, which is already on screen
            return nil
        }
        if isOpen && onScreen.menu.hasSubmenu {
            waiting = next
            return nil
        }
        return show(next)
    }

    /// The menu began to open. What waits is applied now, in case the last close was never heard.
    public mutating func menuBegan() -> MenuShown? {
        isOpen = true
        return applyWaiting()
    }

    /// The menu closed. What waits is applied.
    public mutating func menuEnded() -> MenuShown? {
        isOpen = false
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
