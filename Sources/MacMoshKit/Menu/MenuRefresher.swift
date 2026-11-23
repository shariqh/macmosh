import Combine
import Foundation

/// Holds the menu the app shows and refreshes it. All logic the app needs that can be tested lives here, not in a view.
@MainActor
public final class MenuRefresher: ObservableObject {
    @Published public private(set) var menu: MenuLines
    /// The last sentence from an action, shown as the menu's first line until the next action.
    @Published public private(set) var notice: String?

    // What the checks found, kept for the window (main window design, section 7.2). The menu reads
    // none of it: it is built from each check's own results, as before.

    /// The last real result for each workhorse on the list, by id. A check that comes back still
    /// running leaves the one before in place.
    @Published public private(set) var latest: [String: CheckResult] = [:]
    /// The last Ready result for each workhorse on the list, by id, kept while it is in another state.
    @Published public private(set) var lastReady: [String: CheckResult] = [:]
    /// The workhorses being checked. A check asks every one at once, so every id goes in when a check
    /// starts; each leaves when it answers, and one still being checked when the time is up stays in.
    @Published public private(set) var checking: Set<String> = []
    /// True from the start of a refresh until it ends, the one run after it included.
    @Published public private(set) var isRefreshing = false
    /// The workhorses shown as "Waiting for the desk server" (issue #88). Like `latest` and
    /// `lastReady`, it is left as it was when the saved list can't be read.
    @Published public private(set) var waitingForDeskServer: Set<String> = []

    private let load: @Sendable () throws -> [Workhorse]
    private let gather: @Sendable ([Workhorse]) async -> [Gathered]
    private let save: @Sendable (CheckResult) -> Void
    private let log: @Sendable (String) -> Void
    private let pause: @Sendable (Duration) async -> Void
    /// The last "menu refreshed" line written, so that a check that changes nothing writes nothing.
    private var lastRefreshLine: String?
    private var refreshAgain = false
    /// How many checks in a row found a workhorse that can't be reached; sets the wait in `runInBackground`.
    private var missesInARow = 0
    /// Which workhorses have just been logged in to and are given a minute to start their desk server (issue #88).
    private var deskServerWait = DeskServerWait()

    /// How long to wait before looking again at a workhorse that has just stopped answering.
    static let secondLook: Duration = .seconds(5)

    /// `load` reads the saved list, `gather` checks the workhorses, and `save` keeps what a report
    /// taught about one of them. Until the first refresh the menu is one line, `Checking…`.
    /// `log` takes the lines of `MenuLog`; the real one writes them to the Mac's system log.
    /// `pause` is how the wait before a second look is done; tests pass one that doesn't wait.
    public init(load: @escaping @Sendable () throws -> [Workhorse],
                gather: @escaping @Sendable ([Workhorse]) async -> [Gathered],
                save: @escaping @Sendable (CheckResult) -> Void,
                log: @escaping @Sendable (String) -> Void = { MenuLog.write($0) },
                pause: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }) {
        self.load = load
        self.gather = gather
        self.save = save
        self.log = log
        self.pause = pause
        self.menu = MenuLines(symbol: MenuModel.stillCheckingSymbol,
                              entries: [MenuEntry(id: "top:checking", title: "Checking…")])
    }

    /// Loads the list, checks every workhorse, saves what the reports changed and builds the menu.
    /// A saved list that can't be read gives a menu with the warning symbol and one line saying so.
    /// Never two at once: a refresh asked for while one is running returns at once and is
    /// remembered, and exactly one more refresh runs right after the current one, however many were
    /// asked for. That keeps the check that follows an action from being lost to one already in flight.
    public func refresh() async {
        if isRefreshing {
            refreshAgain = true
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        repeat {
            refreshAgain = false
            await refreshOnce()
        } while refreshAgain
    }

    private func refreshOnce() async {
        let load = self.load
        let list: [Workhorse]
        do {
            list = try await Task.detached { try load() }.value
        } catch {
            if !checking.isEmpty { checking = [] }
            menu = MenuLines(symbol: "exclamationmark.triangle",
                             entries: [MenuEntry(id: "top:unreadable", title: StatusFormat.storeMessage(error))])
            missesInARow = 0
            logRefresh(MenuLog.listUnreadable)
            return
        }

        // Written only when it changes. That saves a redraw only when nothing changed: in the usual
        // run `checking` goes from empty to every id here and back to empty in `keep`.
        let all = Set(list.map(\.id))
        if checking != all { checking = all }
        var gathered = await gather(list)
        // One check that can't reach a workhorse is not news yet: a Mac that has just woken has no
        // network for a moment (issue #83). So the first miss gets a second look a few seconds
        // later, and the menu keeps what it showed until then. A miss that follows a miss is
        // shown at once.
        if missesInARow == 0, PollSchedule.isMiss(gathered) {
            await pause(Self.secondLook)
            gathered = await gather(list)
        }
        missesInARow = PollSchedule.isMiss(gathered) ? missesInARow + 1 : 0
        let save = self.save
        let checked: [CheckResult] = gathered.compactMap {
            if case .checked(let result) = $0 { return result }
            return nil
        }
        // The saved list is written under a file lock, so it is done off the main thread.
        await Task.detached { for result in checked { save(result) } }.value
        keep(gathered, list: list)
        let waiting = deskServerWait.update(gathered)
        if waitingForDeskServer != waiting { waitingForDeskServer = waiting }
        menu = MenuModel.build(gathered, waitingForDeskServer: waiting)
        logRefresh(MenuLog.refreshed(menu, workhorses: list.count))
    }

    /// Takes in one check's results: each answer replaces that workhorse's `latest` (and its
    /// `lastReady`, when Ready) and takes it out of `checking`. A workhorse no longer on the list is forgotten.
    private func keep(_ gathered: [Gathered], list: [Workhorse]) {
        let ids = Set(list.map(\.id))
        var latest = self.latest.filter { ids.contains($0.key) }
        var lastReady = self.lastReady.filter { ids.contains($0.key) }
        var checking = self.checking
        for case .checked(let result) in gathered {
            let id = result.workhorse.id
            latest[id] = result
            if case .ready = result.state { lastReady[id] = result }
            checking.remove(id)
        }
        if self.latest != latest { self.latest = latest }
        if self.lastReady != lastReady { self.lastReady = lastReady }
        if self.checking != checking { self.checking = checking }
    }

    /// The checks repeat every 30 seconds or so; only a change is worth a line.
    private func logRefresh(_ line: String) {
        if line == lastRefreshLine { return }
        lastRefreshLine = line
        log(line)
    }

    /// The menu was opened: says so in the log and checks again, so what is shown is fresh.
    public func menuOpened() async {
        log(MenuLog.opened)
        await refresh()
    }

    /// Refreshes, waits as long as `PollSchedule` says, and does it again, until the task is cancelled.
    /// `sleep` is how the waiting is done; tests pass a stand-in that doesn't wait.
    public func runInBackground(sleep: @escaping @Sendable (Duration) async -> Void) async {
        while !Task.isCancelled {
            await refresh()
            if Task.isCancelled { break }
            await sleep(PollSchedule.delay(missesInARow: missesInARow))
        }
    }

    /// Does what a menu item asks, keeps the sentence it gives back as the `notice`, and checks again.
    /// The notice from the action before is cleared first.
    public func perform(_ item: MenuItem, using actions: MenuActionRunner) async {
        notice = nil
        log(MenuLog.asked(item.action))
        let outcome = await actions.outcome(of: item.action, title: item.title)
        log(MenuLog.finished(item.action, summary: outcome.summary))
        notice = outcome.notice
        await refresh()
    }

    /// The real thing: this Mac's saved list and folders, the real checks with a 20-second budget,
    /// and `WorkhorseStore.absorb` to keep what the reports teach. With no workhorses saved it
    /// makes no ssh call at all.
    public static func standard() -> MenuRefresher {
        let paths = Paths.standard()
        let store = WorkhorseStore(paths: paths)
        let runner = ProcessRunner()
        let checker = StatusChecker(runner: runner, paths: paths, hints: SystemHints(runner: runner))
        return MenuRefresher(
            load: { try store.load() },
            gather: { list in await MenuData.gather(list, checker: checker, budget: .seconds(20)) },
            save: { try? store.absorb($0) })
    }
}

/// Tells a login that has just happened from a desk server that stays down (issue #88).
///
/// Right after a login the workhorse's report has a console user and no desk server, because the
/// login agent hasn't started it yet. `StateResolver` calls that `notSetUp(.deskServerDown)`, and the
/// menu used to offer a fix for something that fixes itself. The result of the check is not changed:
/// this only decides, for the menu, which workhorses to show as waiting for a minute.
///
/// A wait begins on a check that finds the desk server down with the login agent installed, when the
/// check before it in this run of the app found nobody logged in or couldn't tell (or there was none).
/// It lasts while later checks say the same, for less than `limit` after the check that began it.
/// It uses each result's `checkedAt`, so it needs no clock.
struct DeskServerWait {
    /// How long after the first such check the menu waits before it says "Desk server is off".
    static let limit: TimeInterval = 60
    private var last: [String: WorkhorseState] = [:]   // what the last finished check found, by id
    private var since: [String: Date] = [:]            // when a wait began, by id, only while waiting

    /// Takes one refresh's results and returns the ids to show as "Waiting for the desk server".
    /// `.stillChecking` entries leave that workhorse's memory as it was.
    mutating func update(_ gathered: [Gathered]) -> Set<String> {
        var waiting: Set<String> = []
        for entry in gathered {
            guard case .checked(let r) = entry else { continue }
            let id = r.workhorse.id
            let before = last[id]
            last[id] = r.state
            guard r.state == .notSetUp(.deskServerDown), r.status?.agentInstalled == true else {
                since[id] = nil
                continue
            }
            if since[id] == nil, Self.mayBegin(after: before) { since[id] = r.checkedAt }
            if let began = since[id] {
                let elapsed = r.checkedAt.timeIntervalSince(began)
                if elapsed >= 0, elapsed < Self.limit {   // a clock set back ends the wait
                    waiting.insert(id)
                } else {
                    since[id] = nil
                }
            }
        }
        return waiting
    }

    /// Nobody logged in, or no way to tell, or no earlier check: a login may have just happened.
    private static func mayBegin(after before: WorkhorseState?) -> Bool {
        switch before {
        case nil, .waitingForLogin?, .locked?, .cantReach?: return true
        default: return false
        }
    }
}
