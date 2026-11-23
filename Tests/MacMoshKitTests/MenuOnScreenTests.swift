import Combine
import Foundation
import Testing
@testable import MacMoshKit

/// Gives one scripted answer per gather; the last one again once the script runs out.
private final class Answers: @unchecked Sendable {
    private let lock = NSLock()
    private var steps: [[Gathered]]
    init(_ steps: [[Gathered]]) { self.steps = steps }
    func next() -> [Gathered] {
        lock.withLock { steps.count > 1 ? steps.removeFirst() : (steps.first ?? []) }
    }
}

private final class Lines: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    func add(_ line: String) { lock.withLock { lines.append(line) } }
    var all: [String] { lock.withLock { lines } }
}

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

/// Ready with the sample desk (so the menu has submenus), checked `at` seconds after t0.
private func ready(_ name: String = "MacBook Pro", at offset: TimeInterval = 0) -> Gathered {
    .checked(.sample(.ready(signIns: true), workhorse: .sample(id: "mbp", name: name), status: .sampleWithDesk,
                     homeReachable: true, checkedAt: t0.addingTimeInterval(offset)))
}

private func locked(at offset: TimeInterval = 0) -> Gathered {
    .checked(.sample(.locked, workhorse: .sample(id: "mbp", name: "MacBook Pro"), checkedAt: t0.addingTimeInterval(offset)))
}

/// The object the menu's view observes (issue #107): only the menu on screen and its notice, let
/// through by `HoldStill`.
@MainActor @Suite struct MenuOnScreenTests {
    private func make(_ steps: [[Gathered]], log: Lines = Lines()) -> (MenuRefresher, MenuOnScreen) {
        let answers = Answers(steps)
        let r = MenuRefresher(load: { [.sample(id: "mbp", name: "MacBook Pro")] }, gather: { _ in answers.next() },
                              save: { _ in }, log: { _ in }, pause: { _ in })
        return (r, MenuOnScreen(refresher: r, log: { log.add($0) }))
    }

    @Test func itStartsWithTheRefreshersMenu() {
        let (r, screen) = make([])
        #expect(screen.shown == MenuShown(menu: r.menu, notice: nil))
        #expect(screen.shown.menu.items.map(\.title) == ["Checking…"])
    }

    @Test func whileClosedEachNewMenuIsShown() async {
        let (r, screen) = make([[ready()], [locked()]])
        await r.refresh()
        #expect(screen.shown.menu == r.menu)
        #expect(screen.shown.menu.items.first?.title == "MacBook Pro · Ready")
        await r.refresh()
        #expect(screen.shown.menu.items.first?.title == "MacBook Pro · Locked after a restart")
    }

    /// `latest`, `checking` and `isRefreshing` change on every check; the menu's object does not.
    @Test func theRefreshersOtherValuesChangingDoesNotPublishIt() async {
        let (r, screen) = make([[ready(at: 0)], [ready(at: 30)], [ready(at: 60)]])
        await r.refresh()
        var published = 0
        let watch = screen.objectWillChange.sink { _ in published += 1 }
        let before = r.latest
        await r.refresh()
        await r.refresh()
        #expect(r.latest != before)   // the check's time changed, and with it what the refresher keeps
        #expect(published == 0)
        watch.cancel()
    }

    @Test func anOpenMenuWithASubmenuHoldsStillUntilItCloses() async {
        let log = Lines()
        let (r, screen) = make([[ready()], [ready("Renamed")]], log: log)
        await r.refresh()
        let first = screen.shown
        screen.menuBegan()
        await r.menuOpened()   // the check that runs when the menu opens still runs
        #expect(r.menu.items.first?.title == "Renamed · Ready")
        #expect(screen.shown == first)
        screen.menuEnded()
        #expect(screen.shown.menu.items.first?.title == "Renamed · Ready")
        #expect(log.all == ["menu held a change: open with a submenu", "menu showed the held change: closed"])
    }

    @Test func aMissedCloseIsMadeUpForWhenTheMenuNextOpens() async {
        let log = Lines()
        let (r, screen) = make([[ready()], [ready("Renamed")]], log: log)
        await r.refresh()
        screen.menuBegan()
        await r.refresh()
        screen.menuBegan()   // no close was heard
        #expect(screen.shown.menu.items.first?.title == "Renamed · Ready")
        #expect(log.all.last == "menu showed the held change: opened")
    }

    @Test func anOpenMenuWithNoSubmenuUpdatesAtOnce() async {
        let log = Lines()
        let (r, screen) = make([[locked(at: 0)], [locked(at: 0)], [ready()]], log: log)
        await r.refresh()
        screen.menuBegan()
        await r.refresh()
        await r.refresh()
        #expect(screen.shown.menu.items.first?.title == "MacBook Pro · Ready")
        #expect(log.all.isEmpty)
    }

    @Test func theNoticeWaitsTooWhileAMenuWithASubmenuIsOpen() async {
        let (r, screen) = make([[ready()]])
        await r.refresh()
        let fake = FakeRunner { _ in FakeRunner.failed(1, stderr: "no screen sharing\n") }
        let actions = MenuActionRunner(macmoshPath: "/Applications/MacMosh.app/Contents/Helpers/macmosh",
                                       tabs: RecordingTabs(), runner: fake)
        screen.menuBegan()
        await r.perform(.run(["screen", "mbp"]), title: "Share screen", using: actions)
        #expect(r.notice == "no screen sharing")
        #expect(screen.shown.notice == nil)
        screen.menuEnded()
        #expect(screen.shown.notice == "no screen sharing")
    }
}
