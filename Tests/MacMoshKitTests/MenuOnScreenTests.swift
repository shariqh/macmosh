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

/// Stands in for the wait after the menu closes: records each wait asked for, and each one ends only
/// when the test ends it (by its number, in the order they were asked), so nothing really sleeps.
private final class Moments: @unchecked Sendable {
    private let lock = NSLock()
    private var asked: [Duration] = []
    private var gates: [Int: CheckedContinuation<Void, Never>] = [:]
    private var endedEarly: Set<Int> = []
    private var askedWatchers: [(count: Int, ready: CheckedContinuation<Void, Never>)] = []
    var durations: [Duration] { lock.withLock { asked } }

    func sleep(_ duration: Duration) async {
        await withCheckedContinuation { (gate: CheckedContinuation<Void, Never>) in
            let (now, ready): (Bool, [CheckedContinuation<Void, Never>]) = lock.withLock {
                let number = asked.count
                asked.append(duration)
                let ready = askedWatchers.filter { $0.count <= asked.count }.map(\.ready)
                askedWatchers.removeAll { $0.count <= asked.count }
                if endedEarly.remove(number) != nil { return (true, ready) }
                gates[number] = gate
                return (false, ready)
            }
            ready.forEach { $0.resume() }
            if now { gate.resume() }
        }
    }

    /// Returns once `count` waits have been asked for. Each timer task's wait reaches this stand-in
    /// off the main actor, so two timers started back to back can ask in either order; a test that
    /// ends waits by number awaits this between them to fix which timer holds which number.
    func asked(_ count: Int) async {
        await withCheckedContinuation { (ready: CheckedContinuation<Void, Never>) in
            let now: Bool = lock.withLock {
                if asked.count >= count { return true }
                askedWatchers.append((count, ready))
                return false
            }
            if now { ready.resume() }
        }
    }

    /// Ends wait `number`, or makes it end at once if it has not been asked for yet.
    func end(_ number: Int) {
        let gate: CheckedContinuation<Void, Never>? = lock.withLock {
            if let gate = gates.removeValue(forKey: number) { return gate }
            endedEarly.insert(number)
            return nil
        }
        gate?.resume()
    }
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
    private func make(_ steps: [[Gathered]], log: Lines = Lines(),
                      moments: Moments = Moments()) -> (MenuRefresher, MenuOnScreen) {
        let answers = Answers(steps)
        let r = MenuRefresher(load: { [.sample(id: "mbp", name: "MacBook Pro")] }, gather: { _ in answers.next() },
                              save: { _ in }, log: { _ in }, pause: { _ in })
        return (r, MenuOnScreen(refresher: r, log: { log.add($0) }, sleep: { await moments.sleep($0) }))
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

    /// AppKit posts the end of tracking before it sends the clicked line's action (the trial,
    /// question 6), so a held change is shown 300 milliseconds after the close, not in its notice.
    @Test func anOpenMenuWithASubmenuHoldsStillUntilAMomentAfterItCloses() async {
        let log = Lines()
        let moments = Moments()
        let (r, screen) = make([[ready()], [ready("Renamed")]], log: log, moments: moments)
        await r.refresh()
        let first = screen.shown
        screen.menuBegan()
        await r.menuOpened()   // the check that runs when the menu opens still runs
        #expect(r.menu.items.first?.title == "Renamed · Ready")
        #expect(screen.shown == first)
        screen.menuEnded()
        #expect(screen.shown == first)   // not in the close notice
        #expect(log.all == ["menu held a change: open with a submenu"])
        moments.end(0)
        await screen.closing?.value
        #expect(moments.durations == [.milliseconds(300)])
        #expect(screen.shown.menu.items.first?.title == "Renamed · Ready")
        #expect(log.all == ["menu held a change: open with a submenu", "menu showed the held change: closed"])
    }

    @Test func aChangeArrivingJustAfterTheCloseWaitsForTheMomentToo() async {
        let log = Lines()
        let moments = Moments()
        let (r, screen) = make([[ready()], [ready("Renamed")], [ready("Again")]], log: log, moments: moments)
        await r.refresh()
        let first = screen.shown
        screen.menuBegan()
        screen.menuEnded()
        await r.refresh()
        #expect(screen.shown == first)
        #expect(log.all == ["menu held a change: closing with a submenu"])
        moments.end(0)
        await screen.closing?.value
        #expect(screen.shown.menu.items.first?.title == "Renamed · Ready")
        #expect(log.all.last == "menu showed the held change: closed")
        // The moment has passed: the menu is closed, and changes go through at once again.
        await r.refresh()
        #expect(screen.shown.menu.items.first?.title == "Again · Ready")
        #expect(log.all.count == 2)
    }

    @Test func aCloseWithNothingWaitingShowsAndLogsNothing() async {
        let log = Lines()
        let moments = Moments()
        let (r, screen) = make([[ready()], [ready("Renamed")]], log: log, moments: moments)
        await r.refresh()
        let first = screen.shown
        var published = 0
        let watch = screen.objectWillChange.sink { _ in published += 1 }
        screen.menuBegan()
        screen.menuEnded()
        #expect(screen.closing != nil)
        moments.end(0)
        await screen.closing?.value
        #expect(moments.durations == [.milliseconds(300)])
        #expect(screen.closing == nil)
        #expect(screen.shown == first)
        #expect(published == 0)
        #expect(log.all.isEmpty)
        watch.cancel()
        await r.refresh()
        #expect(screen.shown.menu.items.first?.title == "Renamed · Ready")
    }

    /// The menu opens again before the moment after its close has passed: what waits is shown at once,
    /// the moment is cancelled, and its timer, should it still arrive, does nothing.
    @Test func anOpeningDuringTheMomentShowsWhatWaitsAndTheLateTimerDoesNothing() async {
        let log = Lines()
        let moments = Moments()
        let (r, screen) = make([[ready()], [ready("Renamed")], [ready("Again")]], log: log, moments: moments)
        await r.refresh()
        screen.menuBegan()
        await r.refresh()
        screen.menuEnded()
        let late = screen.closing
        screen.menuBegan()
        #expect(late?.isCancelled == true)
        #expect(screen.closing == nil)
        #expect(screen.shown.menu.items.first?.title == "Renamed · Ready")
        #expect(log.all.last == "menu showed the held change: opened")
        await r.refresh()   // open with a submenu again: it waits
        moments.end(0)
        await late?.value
        #expect(screen.shown.menu.items.first?.title == "Renamed · Ready")
        #expect(log.all == ["menu held a change: open with a submenu", "menu showed the held change: opened",
                            "menu held a change: open with a submenu"])
    }

    @Test func twoClosesInARowOnlyTheLastMomentShowsWhatWaits() async {
        let log = Lines()
        let moments = Moments()
        let (r, screen) = make([[ready()], [ready("Renamed")]], log: log, moments: moments)
        await r.refresh()
        let first = screen.shown
        screen.menuBegan()
        await r.refresh()
        screen.menuEnded()
        let earlier = screen.closing
        await moments.asked(1)   // the earlier close's wait is number 0
        screen.menuEnded()
        let later = screen.closing
        #expect(earlier?.isCancelled == true)
        moments.end(0)
        await earlier?.value
        #expect(screen.shown == first)
        moments.end(1)
        await later?.value
        #expect(moments.durations == [.milliseconds(300), .milliseconds(300)])
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
        let moments = Moments()
        let (r, screen) = make([[ready()]], moments: moments)
        await r.refresh()
        let fake = FakeRunner { _ in FakeRunner.failed(1, stderr: "no screen sharing\n") }
        let actions = MenuActionRunner(macmoshPath: "/Applications/MacMosh.app/Contents/Helpers/macmosh",
                                       tabs: RecordingTabs(), runner: fake, records: scratchTabRecords())
        screen.menuBegan()
        await r.perform(.run(["screen", "mbp"]), title: "Share screen", from: .line, using: actions)
        #expect(r.notice == "no screen sharing")
        #expect(screen.shown.notice == nil)
        screen.menuEnded()
        #expect(screen.shown.notice == nil)
        moments.end(0)
        await screen.closing?.value
        #expect(screen.shown.notice == "no screen sharing")
    }
}
