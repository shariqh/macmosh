import Combine
import Foundation
import Testing
@testable import MacMoshKit

/// Gives one scripted answer per gather; the last one again once the script runs out. Counts gathers.
private final class Script: @unchecked Sendable {
    private let lock = NSLock()
    private var steps: [[Gathered]]
    private var calls = 0
    init(_ steps: [[Gathered]]) { self.steps = steps }
    func next() -> [Gathered] {
        lock.withLock {
            calls += 1
            return steps.count > 1 ? steps.removeFirst() : (steps.first ?? [])
        }
    }
    var gathers: Int { lock.withLock { calls } }
}

/// The saved list a test can change, or make unreadable.
private final class SavedList: @unchecked Sendable {
    private let lock = NSLock()
    private var list: [Workhorse]
    private var broken = false
    init(_ list: [Workhorse]) { self.list = list }
    func set(_ list: [Workhorse]) { lock.withLock { self.list = list; broken = false } }
    func breakIt() { lock.withLock { broken = true } }
    func load() throws -> [Workhorse] {
        try lock.withLock {
            if broken { throw StoreError.unreadable("workhorses.json: not JSON") }
            return list
        }
    }
}

/// A saved list whose reads can be held: after `holdNext`, each read takes the list as it is then and
/// waits until `release`, like a slow disk.
private final class GatedList: @unchecked Sendable {
    private let condition = NSCondition()
    private var list: [Workhorse]
    private var holding = false
    private var released = false
    private var held = 0
    init(_ list: [Workhorse]) { self.list = list }
    /// A new list; the reads after this one are not held.
    func set(_ list: [Workhorse]) { condition.withLock { self.list = list; holding = false } }
    func holdNext() { condition.withLock { holding = true; released = false } }
    func release() { condition.withLock { released = true; condition.broadcast() } }
    func load() -> [Workhorse] {
        condition.lock()
        defer { condition.unlock() }
        let taken = list
        guard holding else { return taken }
        held += 1
        while !released { condition.wait() }
        return taken
    }
    /// Returns once a read is being held, or fails after two seconds.
    func waitUntilHeld() async throws {
        for _ in 0..<200 {
            if condition.withLock({ held > 0 }) { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("no read was held")
    }
}

private final class Lines: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    func add(_ line: String) { lock.withLock { lines.append(line) } }
    var all: [String] { lock.withLock { lines } }
}

private let attic = Workhorse.sample(id: "attic", name: "Attic", user: "alex", osVersion: "27.3", arch: "arm64")
private let den = Workhorse.sample(id: "den", name: "Den", user: "alex")
private let checkedAt = utcDate(2027, 1, 15, 14, 2)

private func ready(_ w: Workhorse = attic) -> Gathered {
    .checked(.sample(.ready(signIns: true), workhorse: w, status: .sampleWithDesk, homeReachable: true, checkedAt: checkedAt))
}

private func locked(_ w: Workhorse = attic) -> Gathered {
    .checked(.sample(.locked, workhorse: w, checkedAt: checkedAt))
}

@MainActor @Suite struct BoardOnScreenTests {
    private func make(_ script: Script, saved: SavedList, lines: Lines = Lines(),
                      timeZone: TimeZone = formatZone) -> (MenuRefresher, BoardOnScreen) {
        let refresher = MenuRefresher(load: { try saved.load() }, gather: { _ in script.next() }, save: { _ in },
                                      log: { lines.add($0) }, pause: { _ in })
        let screen = BoardOnScreen(refresher: refresher, load: { try saved.load() }, log: { lines.add($0) },
                                   now: { formatNow }, timeZone: timeZone)
        return (refresher, screen)
    }

    /// What `BoardModel.build` makes of the refresher's values now.
    private func expected(_ r: MenuRefresher, order: [Workhorse], timeZone: TimeZone = formatZone) -> Board {
        BoardModel.build(latest: r.latest, lastReady: r.lastReady, checking: r.checking, order: order,
                         waitingForDeskServer: r.waitingForDeskServer, tabs: r.tabsSeen, now: formatNow, timeZone: timeZone)
    }

    /// Only this Mac's tab records change between two checks: the board changes with them, as the menu does,
    /// and is built from the records, terminal and time the menu's build had (issue #134).
    @Test func aChangeInTheTabRecordsAloneChangesTheBoard() async throws {
        let w = Workhorse.sample(id: "attic", name: "Attic", user: "alex")
        let same = Gathered.checked(.sample(.ready(signIns: true), workhorse: w, status: windowsReport(),
                                            homeReachable: true, checkedAt: checkedAt))
        let store = scratchTabRecords(running: [1: 10])
        let saved = SavedList([w])
        let refresher = MenuRefresher(load: { try saved.load() }, gather: { _ in [same] }, save: { _ in }, log: { _ in },
                                      pause: { _ in }, tabRecords: store, now: { windowsNow }, tabTerminal: { .iterm2 })
        let screen = BoardOnScreen(refresher: refresher, load: { try saved.load() }, log: { _ in },
                                   now: { formatNow }, timeZone: formatZone)
        await screen.reloadList()
        await refresher.refresh()
        func notes() -> BoardDesk? { screen.board.workhorses.first?.desks.first { $0.name == "notes" } }
        #expect(notes()?.open?.title == "Open notes in a new tab")
        let latest = refresher.latest, before = screen.board

        try store.write(sampleTabRecord(label: "c1d2e3f4a5b6c7d8", workhorse: "attic", desk: "notes", askedWindow: "@7",
                                        pid: 1, started: 10, openedAt: windowsNow.addingTimeInterval(-60)))
        await refresher.refresh()
        #expect(refresher.latest == latest)
        #expect(refresher.tabsSeen == TabsSeen(tabs: TabsOnThisMac(records: store.records(), terminal: .iterm2), at: windowsNow))
        #expect(screen.board != before)
        #expect(notes()?.open == BoardButton(title: "Go to notes", action: .menu(.focus(
            label: "c1d2e3f4a5b6c7d8", orOpen: ["connect", "attic", "notes", "--window", "@7"]))))
        #expect(screen.board == expected(refresher, order: [w]))
        // The menu, built from the same check, offers the same.
        #expect(entry(refresher.menu.entries, "desk:attic:notes")?.action == notes()?.open.map { b -> MenuAction in
            if case .menu(let a) = b.action { return a }
            return .none
        })
    }

    @Test func itFollowsTheRefreshersValues() async {
        let (refresher, screen) = make(Script([[ready()], [locked()]]), saved: SavedList([attic]))
        await screen.reloadList()
        await refresher.refresh()
        #expect(screen.board == expected(refresher, order: [attic]))
        #expect(screen.board.workhorses.first?.headline == "Attic · Ready")
        #expect(screen.board.workhorses.first?.desks.isEmpty == false)

        await refresher.refresh()
        #expect(screen.board == expected(refresher, order: [attic]))
        let w = screen.board.workhorses.first
        #expect(w?.state == .locked)
        // The last Ready check is the greyed list now.
        #expect(w?.lastReadyDesks?.isEmpty == false)
    }

    @Test func beforeAnyCheckTheBoardHasTheSavedWorkhorsesStillChecking() async {
        let (_, screen) = make(Script([[ready()]]), saved: SavedList([attic, den]))
        await screen.reloadList()
        #expect(screen.board.workhorses.map(\.id) == ["attic", "den"])
        #expect(screen.board.workhorses.allSatisfy { $0.state == nil })
    }

    @Test func itPublishesAChangedBoard() async {
        let (refresher, screen) = make(Script([[ready()], [locked()]]), saved: SavedList([attic]))
        await screen.reloadList()
        var boards: [Board] = []
        let watch = screen.$board.dropFirst().sink { boards.append($0) }
        await refresher.refresh()
        #expect(boards.last?.workhorses.first?.state == .ready(signIns: true))
        let afterFirst = boards.count
        await refresher.refresh()
        #expect(boards.count > afterFirst)
        #expect(boards.last?.workhorses.first?.state == .locked)
        // While the check ran, the board said so and kept the Ready result.
        #expect(boards.contains { $0.workhorses.first?.isChecking == true && $0.workhorses.first?.state == .ready(signIns: true) })
        watch.cancel()
    }

    /// A second check with the same answer: the board only says that a check runs and then that it
    /// ended. The refresher publishes more than that (each of its values), and none of the rest reaches it.
    @Test func itDoesNotPublishAnEqualBoard() async {
        let (refresher, screen) = make(Script([[ready()]]), saved: SavedList([attic]))
        await screen.reloadList()
        await refresher.refresh()
        let before = screen.board
        var boards: [Board] = []
        let watch = screen.$board.dropFirst().sink { boards.append($0) }

        await refresher.refresh()
        #expect(boards.count == 2)
        #expect(boards.first?.workhorses.first?.isChecking == true)
        #expect(boards.last == before)

        // Reading the same list again, and an action's notice, change nothing on the board.
        await screen.reloadList()
        let actions = MenuActionRunner(macmoshPath: "/x/macmosh", tabs: RecordingTabs(),
                                       runner: FakeRunner { _ in FakeRunner.ok() }, records: scratchTabRecords())
        let count = boards.count
        await refresher.perform(.none, title: "Nothing", from: .window, using: actions)
        #expect(boards.count == count + 2)   // only the check after the action: on, then off
        #expect(boards.last == before)
        watch.cancel()
    }

    @Test func aChangedListAddsAWorkhorseAndAnUnreadableOneKeepsTheLast() async {
        let saved = SavedList([attic])
        let (refresher, screen) = make(Script([[ready()]]), saved: saved)
        await screen.reloadList()
        await refresher.refresh()
        saved.set([attic, den])
        await screen.reloadList()
        #expect(screen.board.workhorses.map(\.id) == ["attic", "den"])
        #expect(screen.board.workhorses.last?.headline == "Den · Still checking…")
        saved.breakIt()
        await screen.reloadList()
        #expect(screen.board.workhorses.map(\.id) == ["attic", "den"])
    }

    /// A list that can't be read from the start: the board stays empty and the window has the menu's
    /// own sentence for it, until a read works again.
    @Test func aListThatCantBeReadSaysTheMenusSentence() async {
        let saved = SavedList([attic])
        saved.breakIt()
        let (_, screen) = make(Script([[ready()]]), saved: saved)
        await screen.reloadList()
        #expect(screen.board.workhorses.isEmpty)
        #expect(screen.listProblem == StatusFormat.storeMessage(StoreError.unreadable("workhorses.json: not JSON")))
        saved.set([attic])
        await screen.reloadList()
        #expect(screen.listProblem == nil)
        #expect(screen.board.workhorses.map(\.id) == ["attic"])
    }

    /// A slow read of the saved list that started before a later one was shown can't put the older list back.
    @Test func aSlowEarlierReadDoesNotReplaceALaterOne() async throws {
        let saved = GatedList([attic])
        let refresher = MenuRefresher(load: { [attic] }, gather: { _ in [] }, save: { _ in }, log: { _ in },
                                      pause: { _ in })
        let screen = BoardOnScreen(refresher: refresher, load: { saved.load() }, log: { _ in }, now: { formatNow },
                                   timeZone: formatZone)
        await screen.reloadList()
        saved.holdNext()
        let slow = Task { await screen.reloadList() }
        try await saved.waitUntilHeld()
        saved.set([attic, den])
        await screen.reloadList()
        #expect(screen.board.workhorses.map(\.id) == ["attic", "den"])
        saved.release()
        await slow.value
        #expect(screen.board.workhorses.map(\.id) == ["attic", "den"])
    }

    /// The time and the time zone are passed in: the hint's "Last seen" follows them.
    @Test func theTimeZoneIsPassedIn() async {
        let seen = Workhorse.sample(id: "attic", name: "Attic", user: "alex", lastSeen: utcDate(2027, 1, 15, 14, 2))
        let away: Gathered = .checked(.sample(.cantReach(.tailscaleOff), workhorse: seen, checkedAt: checkedAt))
        let (refresher, screen) = make(Script([[away]]), saved: SavedList([seen]))
        await screen.reloadList()
        await refresher.refresh()
        #expect(screen.board.workhorses.first?.hint == "Last seen 14:02. Tailscale is off on this Mac.")

        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        let (r2, s2) = make(Script([[away]]), saved: SavedList([seen]), timeZone: tokyo)
        await s2.reloadList()
        await r2.refresh()
        #expect(s2.board == expected(r2, order: [seen], timeZone: tokyo))
        #expect(s2.board.workhorses.first?.hint?.hasPrefix("Last seen 14:02") == false)
    }

    /// The page the window shows for a workhorse is laid out with the time and time zone passed in.
    @Test func aWorkhorsesPageUsesTheTimePassedIn() async throws {
        let (refresher, screen) = make(Script([[ready()]]), saved: SavedList([attic]))
        await screen.reloadList()
        await refresher.refresh()
        let w = try #require(screen.board.workhorses.first)
        #expect(screen.page("attic") == WorkhorsePage(w, now: formatNow, timeZone: formatZone))
        #expect(screen.page("attic")?.checked == "Checked 14:02")
        #expect(screen.page("gone") == nil)
    }

    /// The window adds exactly one check, when it opens, and the log says it opened.
    @Test func openingTheWindowLogsItAndChecksOnce() async {
        let script = Script([[ready()]])
        let lines = Lines()
        let (_, screen) = make(script, saved: SavedList([attic]), lines: lines)
        #expect(!lines.all.contains("window opened"))
        await screen.opened()
        #expect(lines.all.filter { $0 == "window opened" }.count == 1)
        #expect(script.gathers == 1)
        #expect(screen.board.workhorses.first?.state == .ready(signIns: true))
    }

    @Test func itFollowsTheRefreshersNotice() async {
        let (refresher, screen) = make(Script([[ready()]]), saved: SavedList([attic]))
        let tabs = RecordingTabs(failure: LaunchError.failed("osascript said no (-1728)"))
        let actions = MenuActionRunner(macmoshPath: "/x/macmosh", tabs: tabs,
                                       runner: FakeRunner { _ in FakeRunner.ok() }, records: scratchTabRecords())
        await refresher.perform(.tab(["connect", "attic", "api"]), title: "Open api", from: .window, using: actions)
        #expect(screen.notice == refresher.notice)
        #expect(screen.notice?.hasPrefix("The tab didn't open.") == true)
    }

    /// The two objects the views observe don't move each other: the menu opening and closing doesn't
    /// publish a board, and a list read for the window doesn't publish a menu.
    @Test func theMenuAndTheWindowDoNotRedrawEachOther() async {
        let (refresher, screen) = make(Script([[ready()]]), saved: SavedList([attic]))
        let menu = MenuOnScreen(refresher: refresher, log: { _ in }, sleep: { _ in })
        await screen.reloadList()
        await refresher.refresh()
        var boards = 0, menus = 0
        let a = screen.$board.dropFirst().sink { _ in boards += 1 }
        let b = menu.$shown.dropFirst().sink { _ in menus += 1 }
        menu.menuBegan()
        menu.menuEnded()
        await screen.reloadList()
        #expect(boards == 0)
        #expect(menus == 0)
        a.cancel()
        b.cancel()
    }

    /// A window action's result line reaches the board, and the menu's notice is the same sentence.
    @Test func aWindowActionsResultLineIsOnTheBoard() async {
        let (refresher, screen) = make(Script([[ready()]]), saved: SavedList([attic]))
        await screen.reloadList()
        await refresher.refresh()
        refresher.finishWindowAction(id: "attic", result: "Removed the desk website from Attic.", kind: .done)
        #expect(screen.board.workhorses.first?.result == "Removed the desk website from Attic.")
        #expect(screen.notice == "Removed the desk website from Attic.")
    }

    /// Whether it worked reaches the board with the sentence (look design 6.3).
    @Test func aWindowActionsResultKindIsOnTheBoard() async {
        let (refresher, screen) = make(Script([[ready()]]), saved: SavedList([attic]))
        await screen.reloadList(); await refresher.refresh()
        refresher.finishWindowAction(id: "attic", result: "Removed the desk website from Attic.", kind: .done)
        #expect(screen.board.workhorses.first?.resultKind == .done)
        refresher.finishWindowAction(id: "attic", result: "website wasn't removed. It didn't work.", kind: .failed)
        let w = screen.board.workhorses.first
        #expect(w?.result == "website wasn't removed. It didn't work." && w?.resultKind == .failed)
        refresher.finishWindowAction(id: "attic", result: "MacMosh didn't hear back from Attic about website within 15 seconds.",
                                     kind: .unknown)
        #expect(screen.board.workhorses.first?.resultKind == .unknown)
    }
}
