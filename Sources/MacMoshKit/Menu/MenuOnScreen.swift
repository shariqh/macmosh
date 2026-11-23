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
///
/// It also keeps the moment after each close: `HoldStill` holds changes from the close notice until
/// `closingWait` has passed, and this object schedules that wait and cancels it when the menu opens
/// again or closes again. A timer that still arrives late does nothing, because `HoldStill` checks
/// that its close is still the latest.
@MainActor
public final class MenuOnScreen: ObservableObject {
    /// How long after the menu closes a held change waits before it is shown. AppKit posts the end of
    /// tracking before it sends the clicked line's action (about 2 ms before, on the trial's macOS 15
    /// and 26 runners, question 6), so a change shown inside the close notice would reach the screen
    /// between a click and its action; this keeps it well clear of that.
    public static let closingWait: Duration = .milliseconds(300)

    /// What the menu shows. Changes only when it differs from what is on screen, and while the menu is
    /// open with a submenu only when the moment after it closes has passed or when it next opens.
    @Published public private(set) var shown: MenuShown

    /// Checks the workhorses and does what a line asks. Kept here so the app observes only this object.
    public let refresher: MenuRefresher

    /// The wait for the moment after the latest close, while it runs; nil otherwise.
    private(set) var closing: Task<Void, Never>?

    private var hold: HoldStill
    private let log: @Sendable (String) -> Void
    private let sleep: @Sendable (Duration) async -> Void
    private var watch: AnyCancellable?

    /// Follows `refresher`'s menu and notice from now on. `log` takes the lines of `MenuLog`; `sleep`
    /// is how the moment after a close is waited out, and tests pass a stand-in that doesn't wait.
    public init(refresher: MenuRefresher, log: @escaping @Sendable (String) -> Void = { MenuLog.write($0) },
                sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }) {
        let first = MenuShown(menu: refresher.menu, notice: refresher.notice)
        shown = first
        hold = HoldStill(first)
        self.refresher = refresher
        self.log = log
        self.sleep = sleep
        // Apple, Published (https://developer.apple.com/documentation/combine/published): "publishing
        // occurs in the property's willSet block, meaning subscribers receive the new value before it's
        // actually set on the property". So this reads the new pair from the publishers, never from the
        // refresher. The refresher is a main-actor class, so its values are set on the main actor, and
        // this runs there; `MainActor.assumeIsolated` "will crash" if that is ever not so
        // (https://developer.apple.com/documentation/swift/mainactor/assumeisolated(_:file:line:)).
        watch = refresher.$menu.combineLatest(refresher.$notice)
            .sink { [weak self] menu, notice in
                MainActor.assumeIsolated { self?.offer(MenuShown(menu: menu, notice: notice)) }
            }
    }

    /// AppKit says the menu began tracking: the person is opening it. What was held is shown now, in
    /// case its close was never heard, and the moment after an earlier close is cancelled.
    public func menuBegan() {
        cancelClosing()
        if let next = hold.menuBegan() { show(next, log: MenuLog.heldShown(.opened)) }
    }

    /// AppKit says the menu ended tracking: it closed. Nothing is shown now, because AppKit sends the
    /// clicked line's action after this notice (the trial, question 6). What was held is shown once
    /// `closingWait` has passed, unless the menu begins to open again first.
    public func menuEnded() {
        cancelClosing()
        let ended = hold.menuEnded()
        let sleep = self.sleep
        closing = Task { [weak self] in
            await sleep(Self.closingWait)
            self?.closingPassed(ended)
        }
    }

    /// The moment after `ended` has passed. `HoldStill` does nothing if a later close or an opening
    /// came since, so a late timer cannot show a change while the menu is open.
    private func closingPassed(_ ended: HoldStill.Closing) {
        let next = hold.closingPassed(ended)
        // Closed now only if this was the latest close: its wait is over.
        if hold.phase == .closed { closing = nil }
        if let next { show(next, log: MenuLog.heldShown(.closed)) }
    }

    private func cancelClosing() {
        closing?.cancel()
        closing = nil
    }

    private func offer(_ next: MenuShown) {
        let wasWaiting = hold.waiting != nil
        if let now = hold.offer(next) {
            shown = now
        } else if !wasWaiting, hold.waiting != nil {
            log(MenuLog.held(hold.isOpen ? .open : .closing))
        }
    }

    private func show(_ next: MenuShown, log line: String) {
        shown = next
        log(line)
    }
}
