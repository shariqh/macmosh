import Foundation
import Testing
@testable import MacMoshKit

/// Collects what `save` was given. The closure is `@Sendable`, so the list sits behind a lock.
private final class Saved: @unchecked Sendable {
    private let lock = NSLock()
    private var ids: [String] = []

    func add(_ id: String) { lock.lock(); ids.append(id); lock.unlock() }
    var all: [String] { lock.lock(); defer { lock.unlock() }; return ids }
}

@MainActor @Suite struct MenuRefresherTests {
    @Test func refreshBuildsTheMenuFromWhatWasGathered() async {
        let r = MenuRefresher(load: { [.sample(id: "mbp", name: "MacBook Pro")] },
                              gather: { list in list.map { .checked(.sampleReady(id: $0.id, name: $0.name)) } },
                              save: { _ in })
        await r.refresh()
        #expect(r.menu.symbol == "checkmark.circle")
        #expect(r.menu.items.first?.title == "MacBook Pro · Ready")
    }

    @Test func theMenuStartsAsStillLoading() {
        let r = MenuRefresher(load: { [] }, gather: { _ in [] }, save: { _ in })
        #expect(r.menu.symbol == "ellipsis.circle")
        #expect(r.menu.items.map(\.title) == ["Checking…"])
    }

    @Test func aDamagedListShowsAPlainMessageNotACrash() async {
        let r = MenuRefresher(load: { throw StoreError.unreadable("workhorses.json: not JSON") },
                              gather: { _ in Issue.record("gather must not run"); return [] },
                              save: { _ in Issue.record("save must not run") })
        await r.refresh()
        #expect(r.menu.symbol == "exclamationmark.triangle")
        #expect(r.menu.items.count == 1)
        #expect(r.menu.items.first?.title == "Can't read MacMosh's saved settings: workhorses.json: not JSON")
    }

    @Test func refreshSavesOnlyCheckedResults() async {
        let saved = Saved()
        let r = MenuRefresher(
            load: { [.sample(id: "a", name: "A"), .sample(id: "b", name: "B")] },
            gather: { list in
                let first: Gathered = .checked(.sampleReady(id: list[0].id, name: list[0].name))
                let second: Gathered = .stillChecking(list[1])
                return [first, second]
            },
            save: { saved.add($0.workhorse.id) })
        await r.refresh()
        #expect(saved.all == ["a"])
        #expect(r.menu.items.contains { $0.title == "B · Still checking…" })
    }

    /// Counts gathers, how many run at once, and holds the first one open until released.
    private final class Gate: @unchecked Sendable {
        private let lock = NSLock()
        private var calls = 0, running = 0, mostAtOnce = 0, open = false
        var total: Int { lock.withLock { calls } }
        var peak: Int { lock.withLock { mostAtOnce } }
        var started: Bool { lock.withLock { calls > 0 } }
        func release() { lock.withLock { open = true } }
        func enter() -> Bool {
            lock.withLock {
                calls += 1; running += 1; mostAtOnce = max(mostAtOnce, running)
                return calls == 1
            }
        }
        func leave() { lock.withLock { running -= 1 } }
        func isOpen() -> Bool { lock.withLock { open } }
    }

    private func heldRefresher(_ gate: Gate) -> MenuRefresher {
        MenuRefresher(load: { [.sample()] },
                      gather: { list in
                          let first = gate.enter()
                          defer { gate.leave() }
                          while first && !gate.isOpen() { try? await Task.sleep(for: .milliseconds(10)) }
                          return list.map { .checked(.sampleReady(id: $0.id, name: $0.name)) }
                      },
                      save: { _ in })
    }

    @Test(.timeLimit(.minutes(1))) func aRefreshWhileOneIsRunningRunsOnceMoreAfterIt() async {
        let gate = Gate()
        let r = heldRefresher(gate)
        async let first: Void = r.refresh()
        while !gate.started { try? await Task.sleep(for: .milliseconds(10)) }   // the first is now gathering
        await r.refresh()   // returns at once, and is remembered
        #expect(r.menu.symbol == "ellipsis.circle")
        gate.release()
        await first
        #expect(gate.total == 2)
        #expect(gate.peak == 1)
        #expect(r.menu.symbol == "checkmark.circle")
    }

    @Test(.timeLimit(.minutes(1))) func aRefreshAskedForDuringOneRunsOnceAfterIt() async {
        let gate = Gate()
        let r = heldRefresher(gate)
        async let first: Void = r.refresh()
        while !gate.started { try? await Task.sleep(for: .milliseconds(10)) }
        await r.refresh()
        await r.refresh()   // two asked for during one: still only one more
        gate.release()
        await first
        #expect(gate.total == 2)
        #expect(gate.peak == 1)
        await r.refresh()   // nothing is left over: a later one runs once, and only once
        #expect(gate.total == 3)
    }

    // MARK: background checks (Task 27)

    /// Counts refreshes and says which of them find a workhorse that can't be reached.
    private final class Misses: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        private let pattern: [Bool]
        init(_ pattern: [Bool]) { self.pattern = pattern }
        func next() -> Bool {
            lock.withLock {
                defer { count += 1 }
                return count < pattern.count ? pattern[count] : false
            }
        }
        /// How many checks have run.
        var checks: Int { lock.withLock { count } }
    }

    /// Collects the waits a stand-in sleep was asked for, and ends the loop after `limit` of them.
    private final class Waits: @unchecked Sendable {
        private let lock = NSLock()
        private var seen: [Duration] = []
        let limit: Int
        init(limit: Int) { self.limit = limit }
        var all: [Duration] { lock.withLock { seen } }
        func record(_ wait: Duration) {
            let enough = lock.withLock { () -> Bool in
                seen.append(wait)
                return seen.count >= limit
            }
            // This runs inside the loop's own task, so this stops the loop.
            if enough { withUnsafeCurrentTask { $0?.cancel() } }
        }
    }

    /// `pattern` says which checks, in order, find the workhorse out of reach. `pauses` collects the
    /// waits before a second look; nothing really waits.
    private func refresher(missing pattern: [Bool], misses: Misses? = nil, pauses: Waits? = nil) -> MenuRefresher {
        let misses = misses ?? Misses(pattern)
        return MenuRefresher(
            load: { [.sample(id: "mbp", name: "MacBook Pro")] },
            gather: { list in
                let missed = misses.next()
                return list.map { w in
                    missed ? .checked(.sample(.cantReach(.nothingAnswers), workhorse: w))
                           : .checked(.sampleReady(id: w.id, name: w.name))
                }
            },
            save: { _ in },
            pause: { pauses?.record($0) })
    }

    @Test(.timeLimit(.minutes(1))) func theBackgroundLoopWaitsLongerAfterMisses() async {
        let waits = Waits(limit: 5)
        // The first miss is looked at twice before it counts, so it takes two entries here.
        let r = refresher(missing: [true, true, true, true, true, false])
        let task = Task { await r.runInBackground(sleep: { waits.record($0) }) }
        await task.value
        // Four refreshes in a row that miss: the wait grows to the cap. One that doesn't: back to 30.
        #expect(waits.all == [.seconds(30), .seconds(60), .seconds(120), .seconds(300), .seconds(30)])
    }

    // MARK: a second look before "Can't reach it" (issue #83)

    @Test func aFirstMissIsLookedAtAgainBeforeTheMenuSaysSo() async {
        // A Mac that has just woken has no network for a moment: the first check fails, the next works.
        let misses = Misses([true, false])
        let pauses = Waits(limit: .max)
        let r = refresher(missing: [], misses: misses, pauses: pauses)
        await r.refresh()
        #expect(r.menu.symbol == "checkmark.circle")
        #expect(misses.checks == 2)
        #expect(pauses.all == [.seconds(5)])
    }

    @Test func aMissThatIsStillThereAtTheSecondLookIsShown() async {
        let misses = Misses([true, true, true])
        let pauses = Waits(limit: .max)
        let r = refresher(missing: [], misses: misses, pauses: pauses)
        await r.refresh()
        #expect(r.menu.symbol == "wifi.slash")
        #expect(misses.checks == 2)
        // Once the menu says so, a check that misses again is not doubled.
        await r.refresh()
        #expect(r.menu.symbol == "wifi.slash")
        #expect(misses.checks == 3)
        #expect(pauses.all == [.seconds(5)])
    }

    @Test func aCheckThatReachesEveryWorkhorseIsNotRepeated() async {
        let misses = Misses([false])
        let pauses = Waits(limit: .max)
        let r = refresher(missing: [], misses: misses, pauses: pauses)
        await r.refresh()
        #expect(r.menu.symbol == "checkmark.circle")
        #expect(misses.checks == 1)
        #expect(pauses.all.isEmpty)
    }

    @Test func afterAGoodCheckTheNextMissGetsItsSecondLookAgain() async {
        let misses = Misses([true, true, false, true, false])
        let pauses = Waits(limit: .max)
        let r = refresher(missing: [], misses: misses, pauses: pauses)
        await r.refresh()   // misses twice: shown
        await r.refresh()   // reaches it
        await r.refresh()   // misses once, then reaches it: never shown
        #expect(r.menu.symbol == "checkmark.circle")
        #expect(misses.checks == 5)
        #expect(pauses.all == [.seconds(5), .seconds(5)])
    }

    @Test(.timeLimit(.minutes(1))) func theBackgroundLoopStopsWhenCancelled() async {
        let r = refresher(missing: [])
        let task = Task { await r.runInBackground(sleep: { _ in try? await Task.sleep(for: .seconds(3600)) }) }
        while r.menu.symbol == "ellipsis.circle" { try? await Task.sleep(for: .milliseconds(10)) }
        task.cancel()
        await task.value   // returns; it would hang here if the loop ignored the cancel
        #expect(r.menu.symbol == "checkmark.circle")
    }

    @Test func anActionsSentenceShowsUntilTheNextAction() async {
        let r = refresher(missing: [])
        let fake = FakeRunner { argv in argv.contains("screen") ? FakeRunner.failed(1, stderr: "no screen sharing\n") : FakeRunner.ok() }
        let actions = MenuActionRunner(macmoshPath: "/Applications/MacMosh.app/Contents/Helpers/macmosh",
                                       tabs: RecordingTabs(), runner: fake)
        #expect(r.notice == nil)
        await r.perform(.line("Share screen", .run(["screen", "mbp"])), using: actions)
        #expect(r.notice == "no screen sharing")
        #expect(r.menu.symbol == "checkmark.circle")   // the check after the action ran
        await r.perform(.line("Check now", .refresh), using: actions)
        #expect(r.notice == nil)
    }
}
