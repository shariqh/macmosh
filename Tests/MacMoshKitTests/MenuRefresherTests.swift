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
        #expect(r.menu.items == [MenuItem(title: "Checking…", action: .none, indent: 0, isSeparator: false)])
    }

    @Test func aDamagedListShowsAPlainMessageNotACrash() async {
        let r = MenuRefresher(load: { throw StoreError.unreadable("workhorses.json: not JSON") },
                              gather: { _ in Issue.record("gather must not run"); return [] },
                              save: { _ in Issue.record("save must not run") })
        await r.refresh()
        #expect(r.menu.symbol == "exclamationmark.triangle")
        #expect(r.menu.items == [MenuItem(title: "Can't read MacMosh's saved settings: workhorses.json: not JSON",
                                          action: .none, indent: 0, isSeparator: false)])
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
                                       tabs: RecordingTabs(), runner: fake, records: scratchTabRecords())
        #expect(r.notice == nil)
        await r.perform(.line("Share screen", .run(["screen", "mbp"])), using: actions)
        #expect(r.notice == "no screen sharing")
        #expect(r.menu.symbol == "checkmark.circle")   // the check after the action ran
        await r.perform(.line("Check now", .refresh), using: actions)
        #expect(r.notice == nil)
    }

    // MARK: the wait after a login (issue #88)

    private static let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private static func found(_ state: WorkhorseState, id: String = "mbp", agent: Bool = true,
                              at offset: TimeInterval) -> Gathered {
        var status = HostStatus.sampleReady
        status.agentInstalled = agent
        status.serverUp = state != .notSetUp(.deskServerDown)
        return .checked(.sample(state, workhorse: .sample(id: id, name: "MacBook Pro"), status: status,
                                checkedAt: t0.addingTimeInterval(offset)))
    }

    private static func down(id: String = "mbp", agent: Bool = true, at offset: TimeInterval) -> Gathered {
        found(.notSetUp(.deskServerDown), id: id, agent: agent, at: offset)
    }

    /// Gives one scripted answer per refresh.
    private final class Script: @unchecked Sendable {
        private let lock = NSLock()
        private var steps: [[Gathered]]
        init(_ steps: [[Gathered]]) { self.steps = steps }
        func next() -> [Gathered] { lock.withLock { steps.isEmpty ? [] : steps.removeFirst() } }
    }

    private func scripted(_ steps: [Gathered]) -> MenuRefresher {
        let script = Script(steps.map { [$0] })
        return MenuRefresher(load: { [.sample(id: "mbp", name: "MacBook Pro")] },
                             gather: { _ in script.next() }, save: { _ in })
    }

    // MARK: clearing old tab records (issue #120)

    private static let liveLabel = "aaaaaaaaaaaaaaaa", deadLabel = "bbbbbbbbbbbbbbbb"
    private static let otherLabel = "cccccccccccccccc", newLabel = "dddddddddddddddd"

    /// A Ready report from `id` whose desk has a view line for each label.
    private static func report(_ labels: [String], id: String = "mbp") -> Gathered {
        var status = HostStatus.sampleWithDesk
        status.desks[0].views = labels.enumerated().map {
            HostStatus.View(name: "website+\($0.offset)", windowId: "@\($0.offset)", tabs: 1, label: $0.element)
        }
        return .checked(.sample(.ready(signIns: true), workhorse: .sample(id: id, name: "MacBook Pro"), status: status))
    }

    /// Records of `mbp` (one live and seen, one dead, one live and new) and one dead record of `attic`.
    private func storeWithRecords() throws -> TabRecordStore {
        let store = scratchTabRecords(running: [1: 10, 3: 30, 4: 40])
        try store.write(sampleTabRecord(label: Self.liveLabel, workhorse: "mbp", pid: 1, started: 10,
                                        openedAt: Self.t0.addingTimeInterval(-3600)))
        try store.write(sampleTabRecord(label: Self.deadLabel, workhorse: "mbp", pid: 2, started: 20,
                                        openedAt: Self.t0.addingTimeInterval(-3600)))
        try store.write(sampleTabRecord(label: Self.newLabel, workhorse: "mbp", pid: 4, started: 40, openedAt: Self.t0))
        try store.write(sampleTabRecord(label: Self.otherLabel, workhorse: "attic", pid: 9, started: 90,
                                        openedAt: Self.t0.addingTimeInterval(-3600)))
        return store
    }

    private func sweeping(_ steps: [[Gathered]], store: TabRecordStore, clock: Box<Date>,
                          lines: LockedLines = LockedLines()) -> MenuRefresher {
        let script = Script(steps)
        return MenuRefresher(load: { [.sample(id: "mbp", name: "MacBook Pro"), .sample(id: "attic", name: "Attic")] },
                             gather: { _ in script.next() }, save: { _ in }, log: { lines.add($0) },
                             pause: { _ in }, tabRecords: store, now: { clock.value })
    }

    @Test func aGoodReportClearsThatWorkhorsesDeadAndLongUnseenRecordsOnly() async throws {
        let store = try storeWithRecords()
        let clock = Box(Self.t0)
        let lines = LockedLines()
        // Locked, with no report: not a miss, so no second look takes the next step.
        let r = sweeping([[Self.report([Self.liveLabel]), .checked(.sample(.locked, workhorse: .sample(id: "attic")))],
                          [Self.report([]), .stillChecking(.sample(id: "attic"))],
                          [Self.report([])]],
                         store: store, clock: clock, lines: lines)
        await r.refresh()
        // The dead one goes at once; the other workhorse's dead record stays, as it had no good report.
        #expect(store.records().map(\.label).sorted() == [Self.liveLabel, Self.otherLabel, Self.newLabel].sorted())
        #expect(lines.all.contains("tab records cleared: 1"))

        clock.value = Self.t0.addingTimeInterval(120)
        await r.refresh()
        // Two minutes exactly since the live one was last seen and the new one opened: both stay.
        #expect(store.records().map(\.label).sorted() == [Self.liveLabel, Self.otherLabel, Self.newLabel].sorted())

        clock.value = Self.t0.addingTimeInterval(121)
        await r.refresh()
        #expect(store.records().map(\.label) == [Self.otherLabel])
        #expect(lines.all.filter { $0.hasPrefix("tab records cleared") } == ["tab records cleared: 1", "tab records cleared: 2"])
    }

    @Test func aCheckWithNoReportClearsNothing() async throws {
        let store = try storeWithRecords()
        let r = sweeping([[.checked(.sample(.locked, workhorse: .sample(id: "mbp"))), .stillChecking(.sample(id: "attic"))],
                          [.checked(.sample(.cantReach(.tailscaleOff), workhorse: .sample(id: "mbp")))],
                          [.checked(.sample(.cantReach(.tailscaleOff), workhorse: .sample(id: "mbp")))]],
                         store: store, clock: Box(Self.t0.addingTimeInterval(3600)))
        await r.refresh()
        #expect(store.records().count == 4)
        await r.refresh()   // can't reach it, and the second look the same
        #expect(store.records().count == 4)
    }

    /// The refresher's default has no records to clear, so a test that gives none touches no folder.
    @Test func withNoRecordStoreNothingIsCleared() async {
        let r = scripted([Self.report([])])
        await r.refresh()
        #expect(r.menu.symbol == "checkmark.circle")
    }

    // MARK: this Mac's tabs reach the menu as a value (issue #124)

    /// Attic's report of the menu design's example, with its two website labels and notes' label.
    private static func windowsGathered(mode: ConnectionMode = .mosh) -> Gathered {
        .checked(.sample(.ready(signIns: true), workhorse: .sample(id: "attic", name: "Attic", mode: mode),
                         status: windowsReport(), homeReachable: true))
    }

    /// A store holding website's claude record, live, and zsh's, whose process has ended.
    private func windowsStore() throws -> TabRecordStore {
        let store = scratchTabRecords(running: [1: 10])
        try store.write(sampleTabRecord(label: "3f9a2c71e5b7d4a6", workhorse: "attic", pid: 1, started: 10,
                                        openedAt: Self.t0.addingTimeInterval(-600)))
        try store.write(sampleTabRecord(label: "b04e5d12c3a4f5e6", workhorse: "attic", pid: 2, started: 20,
                                        openedAt: Self.t0.addingTimeInterval(-600)))
        return store
    }

    private func withTabs(_ gathered: Gathered, store: TabRecordStore?, terminal: TerminalApp = .iterm2) -> MenuRefresher {
        let t0 = Self.t0
        return MenuRefresher(load: { [.sample(id: "attic", name: "Attic")] }, gather: { _ in [gathered] }, save: { _ in },
                             log: { _ in }, pause: { _ in }, tabRecords: store, now: { t0 }, tabTerminal: { terminal })
    }

    /// The refresher reads the live records (off the main actor, after clearing the old ones) and builds the
    /// menu with them: a live record's window is in a tab this Mac can find, a dead one's only in another tab.
    @Test func theLiveRecordsReachTheMenu() async throws {
        let store = try windowsStore()
        let r = withTabs(Self.windowsGathered(), store: store)
        #expect(r.tabsSeen == nil)
        await r.refresh()
        #expect(entry(r.menu.entries, "desk:attic:website:win:@1")?.title == "claude (in a tab)")
        #expect(entry(r.menu.entries, "desk:attic:website:win:@2")?.title == "zsh (open in another tab)")
        #expect(entry(r.menu.entries, "desk:attic:website:win:@1")?.action
                == .focus(label: "3f9a2c71e5b7d4a6", orOpen: ["connect", "attic", "website", "--window", "@1"]))
        // The dead record was cleared after the good report.
        #expect(store.records().map(\.label) == ["3f9a2c71e5b7d4a6"])
        let expected = MenuModel.build([Self.windowsGathered()],
                                       tabs: TabsOnThisMac(records: store.records(), terminal: .iterm2), now: Self.t0)
        #expect(r.menu == expected)
        // What the build had is kept for the window's board, which reads no record itself (issue #134).
        #expect(r.tabsSeen == TabsSeen(tabs: TabsOnThisMac(records: store.records(), terminal: .iterm2), at: Self.t0))
    }

    /// The terminal the refresher is told tabs open in decides the gate in Tabs mode, as connect would.
    @Test func whereTabsOpenDecidesTheGateInTabsMode() async throws {
        let inITerm = withTabs(Self.windowsGathered(mode: .tabs), store: try windowsStore(), terminal: .iterm2)
        await inITerm.refresh()
        #expect(entry(inITerm.menu.entries, "desk:attic:website")?.title == "website (3 windows: claude, zsh, vim, kept running, permanent)")
        let inTerminal = withTabs(Self.windowsGathered(mode: .tabs), store: try windowsStore(), terminal: .appleTerminal)
        await inTerminal.refresh()
        #expect(entry(inTerminal.menu.entries, "desk:attic:website")?.title == "website · 3 windows, 2 in tabs")
    }

    /// With no record store, the menu still has a line per window, with no tab this Mac can find.
    @Test func withNoRecordStoreTheMenuHasNoFindableTab() async {
        let r = withTabs(Self.windowsGathered(), store: nil)
        await r.refresh()
        #expect(entry(r.menu.entries, "desk:attic:website:win:@1")?.title == "claude (open in another tab)")
    }

    @Test func theSitting2LoginGoesFromWaitingForLoginToReady() async {
        let r = scripted([Self.found(.waitingForLogin, at: 0),
                          Self.down(at: 83),
                          Self.found(.ready(signIns: true), at: 112)])
        await r.refresh()
        #expect(r.menu.items.first?.title == "MacBook Pro · Waiting for login")
        await r.refresh()
        #expect(r.menu.items.first?.title == "MacBook Pro · Waiting for the desk server")
        #expect(r.menu.symbol == "ellipsis.circle")
        #expect(!r.menu.items.contains { $0.title == "Finish setting up…" })
        #expect(!r.menu.items.contains { $0.title.hasPrefix("Run: macmosh prepare") })
        #expect(r.menu.items.contains { $0.title == "Run the checklist…" })
        await r.refresh()
        #expect(r.menu.items.first?.title == "MacBook Pro · Ready")
    }

    @Test func theLogLineTellsTheWaitApartFromTheOldWrongMenu() async {
        let lines = LockedLines()
        let script = Script([[Self.found(.waitingForLogin, at: 0)], [Self.down(at: 83)]])
        let r = MenuRefresher(load: { [.sample(id: "mbp", name: "MacBook Pro")] },
                              gather: { _ in script.next() }, save: { _ in }, log: { lines.add($0) })
        await r.refresh()
        await r.refresh()
        #expect(lines.all.last == "menu refreshed: symbol=ellipsis.circle workhorses=1 lines=6")
    }

    private final class LockedLines: @unchecked Sendable {
        private let lock = NSLock()
        private var lines: [String] = []
        func add(_ line: String) { lock.withLock { lines.append(line) } }
        var all: [String] { lock.withLock { lines } }
    }

    @Test func aDeskServerThatStaysDownShowsTheFixAfterAMinute() async {
        var wait = DeskServerWait()
        #expect(wait.update([Self.found(.waitingForLogin, at: -30)]) == [])
        #expect(wait.update([Self.down(at: 0)]) == ["mbp"])
        #expect(wait.update([Self.down(at: 30)]) == ["mbp"])
        #expect(wait.update([Self.down(at: 60)]) == [])
        #expect(wait.update([Self.down(at: 90)]) == [])   // the wait does not start again

        let r = scripted([Self.found(.waitingForLogin, at: -30), Self.down(at: 0), Self.down(at: 30), Self.down(at: 60)])
        for _ in 0..<3 { await r.refresh() }
        #expect(r.menu.items.first?.title == "MacBook Pro · Waiting for the desk server")
        await r.refresh()
        #expect(r.menu.items.first?.title == "MacBook Pro · Desk server is off")
        #expect(r.menu.items.contains { $0.title == "Finish setting up…" })
    }

    @Test func aServerThatStopsWhileReadyShowsTheFixAtOnce() async {
        var wait = DeskServerWait()
        #expect(wait.update([Self.found(.ready(signIns: true), at: 0)]) == [])
        #expect(wait.update([Self.down(at: 30)]) == [])
        let r = scripted([Self.found(.ready(signIns: true), at: 0), Self.down(at: 30)])
        await r.refresh()
        await r.refresh()
        #expect(r.menu.items.first?.title == "MacBook Pro · Desk server is off")
        #expect(r.menu.items.contains { $0.title == "Finish setting up…" })
    }

    @Test func noLoginAgentMeansNoWait() async {
        var wait = DeskServerWait()
        #expect(wait.update([Self.found(.waitingForLogin, at: 0)]) == [])
        #expect(wait.update([Self.down(agent: false, at: 30)]) == [])
        let r = scripted([Self.found(.waitingForLogin, at: 0), Self.down(agent: false, at: 30)])
        await r.refresh()
        await r.refresh()
        #expect(r.menu.items.first?.title == "MacBook Pro · Desk server is off")
    }

    @Test func aFirstCheckWithTheServerDownWaitsAMinute() {
        var wait = DeskServerWait()
        #expect(wait.update([Self.down(at: 0)]) == ["mbp"])
        #expect(wait.update([Self.down(at: DeskServerWait.limit - 1)]) == ["mbp"])
        #expect(wait.update([Self.down(at: DeskServerWait.limit)]) == [])
    }

    @Test func aWaitThatAnotherStateClearsDoesNotComeBack() {
        // Ready ends a running wait, so a server that stops later shows the fix at once.
        var wait = DeskServerWait()
        _ = wait.update([Self.found(.waitingForLogin, at: -30)])
        #expect(wait.update([Self.down(at: 0)]) == ["mbp"])
        #expect(wait.update([Self.found(.ready(signIns: true), at: 30)]) == [])
        #expect(wait.update([Self.down(at: 45)]) == [])
        // So does a check that finds no login agent.
        var noAgent = DeskServerWait()
        #expect(noAgent.update([Self.down(at: 0)]) == ["mbp"])
        #expect(noAgent.update([Self.down(agent: false, at: 20)]) == [])
        #expect(noAgent.update([Self.down(at: 40)]) == [])
    }

    @Test func aClockSetBackDoesNotKeepTheWaitUp() {
        var wait = DeskServerWait()
        #expect(wait.update([Self.down(at: 0)]) == ["mbp"])
        #expect(wait.update([Self.down(at: -300)]) == [])
    }

    @Test func aLockedOrUnreachableWorkhorseThatComesBackLoggedInWaits() {
        var locked = DeskServerWait()
        _ = locked.update([Self.found(.locked, at: 0)])
        #expect(locked.update([Self.down(at: 30)]) == ["mbp"])

        var unreachable = DeskServerWait()
        _ = unreachable.update([Self.found(.cantReach(.nothingAnswers), at: 0)])
        #expect(unreachable.update([Self.down(at: 30)]) == ["mbp"])

        var broken = DeskServerWait()
        _ = broken.update([Self.found(.notSetUp(.hostScriptMissing), at: 0)])
        #expect(broken.update([Self.down(at: 30)]) == [])
    }

    @Test func stillCheckingNeitherStartsNorEndsTheWait() {
        var wait = DeskServerWait()
        _ = wait.update([Self.found(.waitingForLogin, at: -30)])
        #expect(wait.update([Self.down(at: 0)]) == ["mbp"])
        #expect(wait.update([.stillChecking(.sample(id: "mbp"))]) == [])
        #expect(wait.update([Self.down(at: 45)]) == ["mbp"])

        var afterReady = DeskServerWait()
        _ = afterReady.update([Self.found(.ready(signIns: true), at: 0)])
        _ = afterReady.update([.stillChecking(.sample(id: "mbp"))])
        #expect(afterReady.update([Self.down(at: 60)]) == [])
    }

    @Test func eachWorkhorseWaitsOnItsOwn() {
        var wait = DeskServerWait()
        _ = wait.update([Self.found(.waitingForLogin, id: "a", at: 0), Self.found(.ready(signIns: true), id: "b", at: 0)])
        #expect(wait.update([Self.down(id: "a", at: 30), Self.down(id: "b", at: 30)]) == ["a"])
    }

    // MARK: what the refresher keeps for the window (main window design 7.2)

    /// A refresher over a fixed list whose every gather gives the next scripted answer, with no waiting.
    private func keeping(_ list: [Workhorse], _ steps: [[Gathered]]) -> MenuRefresher {
        let script = Script(steps)
        return MenuRefresher(load: { list }, gather: { _ in script.next() },
                             save: { _ in }, pause: { _ in })
    }

    nonisolated private static let a = Workhorse.sample(id: "a", name: "A")
    nonisolated private static let b = Workhorse.sample(id: "b", name: "B")

    private static func ready(_ w: Workhorse, at offset: TimeInterval = 0) -> CheckResult {
        .sample(.ready(signIns: true), workhorse: w, status: .sampleWithDesk, checkedAt: t0.addingTimeInterval(offset))
    }

    @Test func nothingIsKeptBeforeTheFirstCheck() {
        let r = MenuRefresher(load: { [] }, gather: { _ in [] }, save: { _ in })
        #expect(r.latest.isEmpty)
        #expect(r.lastReady.isEmpty)
        #expect(r.checking.isEmpty)
        #expect(!r.isRefreshing)
        #expect(r.waitingForDeskServer.isEmpty)
    }

    @Test func latestKeepsTheLastRealResultWhileACheckIsStillRunning() async {
        let first = Self.ready(Self.a)
        let r = keeping([Self.a], [[.checked(first)], [.stillChecking(Self.a)]])
        await r.refresh()
        #expect(r.latest == ["a": first])
        await r.refresh()
        #expect(r.latest == ["a": first])
        // The menu still says so, exactly as before.
        #expect(r.menu.items.first?.title == "A · Still checking…")
    }

    @Test func latestTakesEachNewResultAndLastReadyOnlyAReadyOne() async {
        let ready = Self.ready(Self.a)
        let locked = CheckResult.sample(.locked, workhorse: Self.a, checkedAt: Self.t0.addingTimeInterval(30))
        let again = Self.ready(Self.a, at: 60)
        let r = keeping([Self.a], [[.checked(ready)], [.checked(locked)], [.checked(again)]])
        await r.refresh()
        #expect(r.latest == ["a": ready])
        #expect(r.lastReady == ["a": ready])
        await r.refresh()
        #expect(r.latest == ["a": locked])
        #expect(r.lastReady == ["a": ready])
        await r.refresh()
        #expect(r.latest == ["a": again])
        #expect(r.lastReady == ["a": again])
    }

    @Test func aWorkhorseTakenOffTheListIsForgotten() async {
        let list = SavedList([Self.a, Self.b])
        let script = Script([[.checked(Self.ready(Self.a)), .checked(Self.ready(Self.b))], [.checked(Self.ready(Self.a))]])
        let r = MenuRefresher(load: { list.all }, gather: { _ in script.next() }, save: { _ in }, pause: { _ in })
        await r.refresh()
        #expect(Set(r.latest.keys) == ["a", "b"])
        list.set([Self.a])
        await r.refresh()
        #expect(Set(r.latest.keys) == ["a"])
        #expect(Set(r.lastReady.keys) == ["a"])
    }

    @Test(.timeLimit(.minutes(1))) func everyWorkhorseIsCheckingWhileARefreshRuns() async {
        let held = Held()
        let r = MenuRefresher(load: { [Self.a, Self.b] }, gather: { _ in await held.gather() }, save: { _ in },
                              pause: { _ in })
        async let done: Void = r.refresh()
        await held.untilGathering()
        #expect(r.isRefreshing)
        #expect(r.checking == ["a", "b"])
        held.answer([.checked(Self.ready(Self.a)), .stillChecking(Self.b)])
        await done
        #expect(!r.isRefreshing)
        // One that came back is no longer checking; one still being checked stays until it answers.
        #expect(r.checking == ["b"])
        #expect(held.calls == 1)   // no check of its own was added

        async let again: Void = r.refresh()
        await held.untilGathering()
        #expect(r.checking == ["a", "b"])
        held.answer([.checked(Self.ready(Self.a)), .checked(Self.ready(Self.b))])
        await again
        #expect(r.checking.isEmpty)
        #expect(held.calls == 2)
    }

    @Test func aListThatCantBeReadChecksNothingAndKeepsWhatItHad() async {
        let list = SavedList([Self.a])
        let first = Self.ready(Self.a)
        let r = MenuRefresher(load: { try list.load() }, gather: { _ in [.checked(first)] }, save: { _ in },
                              pause: { _ in })
        await r.refresh()
        list.breakIt()
        await r.refresh()
        #expect(r.checking.isEmpty)
        #expect(!r.isRefreshing)
        #expect(r.latest == ["a": first])
    }

    @Test func theWaitForTheDeskServerIsPublished() async {
        let r = scripted([Self.found(.waitingForLogin, at: 0), Self.down(at: 30), Self.found(.ready(signIns: true), at: 60)])
        await r.refresh()
        #expect(r.waitingForDeskServer.isEmpty)
        await r.refresh()
        #expect(r.waitingForDeskServer == ["mbp"])
        await r.refresh()
        #expect(r.waitingForDeskServer.isEmpty)
    }

    /// A saved list a test can change, or make unreadable, between refreshes.
    private final class SavedList: @unchecked Sendable {
        private let lock = NSLock()
        private var list: [Workhorse]
        private var broken = false
        init(_ list: [Workhorse]) { self.list = list }
        var all: [Workhorse] { lock.withLock { list } }
        func set(_ new: [Workhorse]) { lock.withLock { list = new } }
        func breakIt() { lock.withLock { broken = true } }
        func load() throws -> [Workhorse] {
            try lock.withLock {
                if broken { throw StoreError.unreadable("workhorses.json: not JSON") }
                return list
            }
        }
    }

    /// Holds each gather until the test answers it, and lets the test wait until one has begun. No sleeps.
    private final class Held: @unchecked Sendable {
        private let lock = NSLock()
        private var pending: CheckedContinuation<[Gathered], Never>?
        private var waiter: CheckedContinuation<Void, Never>?
        private var begun = false
        private var count = 0
        var calls: Int { lock.withLock { count } }

        func gather() async -> [Gathered] {
            await withCheckedContinuation { c in
                let w: CheckedContinuation<Void, Never>? = lock.withLock {
                    count += 1
                    pending = c
                    if let w = waiter { waiter = nil; return w }
                    begun = true
                    return nil
                }
                w?.resume()
            }
        }

        func untilGathering() async {
            await withCheckedContinuation { c in
                let now: Bool = lock.withLock {
                    if begun { begun = false; return true }
                    waiter = c
                    return false
                }
                if now { c.resume() }
            }
        }

        func answer(_ gathered: [Gathered]) {
            let c: CheckedContinuation<[Gathered], Never>? = lock.withLock {
                defer { pending = nil }
                return pending
            }
            c?.resume(returning: gathered)
        }
    }

    /// Each check that ends is counted, a list that can't be read included, so the window can wait for the
    /// check after its action (step 4).
    @Test func everyCheckThatEndsIsCounted() async {
        let broken = BrokenFlag()
        let r = MenuRefresher(load: { if broken.on { throw StoreError.unreadable("x") }; return [.sample()] },
                              gather: { list in list.map { .checked(.sampleReady(id: $0.id, name: $0.name)) } },
                              save: { _ in })
        #expect(r.checksDone == 0)
        await r.refresh()
        await r.refresh()
        #expect(r.checksDone == 2)
        broken.on = true
        await r.refresh()
        #expect(r.checksDone == 3)
    }
}

/// Whether a test's saved list reads as damaged now.
private final class BrokenFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var on: Bool {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
}
