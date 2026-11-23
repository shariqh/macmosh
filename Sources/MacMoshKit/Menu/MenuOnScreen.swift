import Combine
import Foundation

/// The one object the menu's view observes: the menu on screen and its notice line, nothing else
/// (issue #107).
///
/// `MenuRefresher` also publishes what the checks found, for the main window (`latest`, `lastReady`,
/// `checking`, `isRefreshing`, `waitingForDeskServer`), and each change to any of them would make every
/// view that observes the refresher draw again. A change to the menu's content closes an open submenu
/// (the trial, question 5), and whether drawing the same content again does was not tried. So the view
/// observes this instead, and this changes only when `HoldStill` lets a different menu through.
@MainActor
public final class MenuOnScreen: ObservableObject {
    /// What the menu shows. Changes only when it differs from what is on screen, and while the menu is
    /// open with a submenu only when the menu closes or next opens.
    @Published public private(set) var shown: MenuShown

    private var hold: HoldStill
    private let log: @Sendable (String) -> Void
    private var watch: AnyCancellable?

    /// Follows `refresher`'s menu and notice from now on. `log` takes the lines of `MenuLog`.
    public init(refresher: MenuRefresher, log: @escaping @Sendable (String) -> Void = { MenuLog.write($0) }) {
        let first = MenuShown(menu: refresher.menu, notice: refresher.notice)
        shown = first
        hold = HoldStill(first)
        self.log = log
        // `@Published` sends each new value on the thread that sets it, before it is stored; the refresher
        // sets its values on the main actor, so this runs there, with the new pair.
        watch = refresher.$menu.combineLatest(refresher.$notice)
            .sink { [weak self] menu, notice in
                MainActor.assumeIsolated { self?.offer(MenuShown(menu: menu, notice: notice)) }
            }
    }

    /// AppKit says the menu began tracking: the person is opening it. What was held is shown now, in
    /// case its close was never heard.
    public func menuBegan() {
        if let next = hold.menuBegan() { show(next, log: MenuLog.heldShown(.opened)) }
    }

    /// AppKit says the menu ended tracking: it closed. What was held is shown now.
    public func menuEnded() {
        if let next = hold.menuEnded() { show(next, log: MenuLog.heldShown(.closed)) }
    }

    private func offer(_ next: MenuShown) {
        let wasWaiting = hold.waiting != nil
        if let now = hold.offer(next) {
            shown = now
        } else if !wasWaiting, hold.waiting != nil {
            log(MenuLog.held)
        }
    }

    private func show(_ next: MenuShown, log line: String) {
        shown = next
        log(line)
    }
}
