import Combine
import Foundation

/// Holds the menu the app shows and refreshes it. All logic the app needs that can be tested lives here, not in a view.
@MainActor
public final class MenuRefresher: ObservableObject {
    @Published public private(set) var menu: Menu
    /// The last sentence from an action, shown as the menu's first line until the next action.
    @Published public private(set) var notice: String?

    private let load: @Sendable () throws -> [Workhorse]
    private let gather: @Sendable ([Workhorse]) async -> [Gathered]
    private let save: @Sendable (CheckResult) -> Void
    private let log: @Sendable (String) -> Void
    /// The last "menu refreshed" line written, so that a check that changes nothing writes nothing.
    private var lastRefreshLine: String?
    private var refreshing = false
    private var refreshAgain = false
    /// How many checks in a row found a workhorse that can't be reached; sets the wait in `runInBackground`.
    private var missesInARow = 0

    /// `load` reads the saved list, `gather` checks the workhorses, and `save` keeps what a report
    /// taught about one of them. Until the first refresh the menu is one line, `Checking…`.
    /// `log` takes the lines of `MenuLog`; the real one writes them to the Mac's system log.
    public init(load: @escaping @Sendable () throws -> [Workhorse],
                gather: @escaping @Sendable ([Workhorse]) async -> [Gathered],
                save: @escaping @Sendable (CheckResult) -> Void,
                log: @escaping @Sendable (String) -> Void = { MenuLog.write($0) }) {
        self.load = load
        self.gather = gather
        self.save = save
        self.log = log
        self.menu = Menu(symbol: MenuModel.stillCheckingSymbol,
                         items: [.line("Checking…", indent: 0)])
    }

    /// Loads the list, checks every workhorse, saves what the reports changed and builds the menu.
    /// A saved list that can't be read gives a menu with the warning symbol and one line saying so.
    /// Never two at once: a refresh asked for while one is running returns at once and is
    /// remembered, and exactly one more refresh runs right after the current one, however many were
    /// asked for. That keeps the check that follows an action from being lost to one already in flight.
    public func refresh() async {
        if refreshing {
            refreshAgain = true
            return
        }
        refreshing = true
        defer { refreshing = false }
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
            menu = Menu(symbol: "exclamationmark.triangle",
                        items: [.line(StatusFormat.storeMessage(error), indent: 0)])
            missesInARow = 0
            logRefresh(MenuLog.listUnreadable)
            return
        }

        let gathered = await gather(list)
        missesInARow = PollSchedule.isMiss(gathered) ? missesInARow + 1 : 0
        let save = self.save
        let checked: [CheckResult] = gathered.compactMap {
            if case .checked(let result) = $0 { return result }
            return nil
        }
        // The saved list is written under a file lock, so it is done off the main thread.
        await Task.detached { for result in checked { save(result) } }.value
        menu = MenuModel.build(gathered)
        logRefresh(MenuLog.refreshed(menu, workhorses: list.count))
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
