import Combine
import Foundation

/// Holds the menu the app shows and refreshes it. All logic the app needs that can be tested lives here, not in a view.
@MainActor
public final class MenuRefresher: ObservableObject {
    @Published public private(set) var menu: Menu

    private let load: @Sendable () throws -> [Workhorse]
    private let gather: @Sendable ([Workhorse]) async -> [Gathered]
    private let save: @Sendable (CheckResult) -> Void
    private var refreshing = false

    /// `load` reads the saved list, `gather` checks the workhorses, and `save` keeps what a report
    /// taught about one of them. Until the first refresh the menu is one line, `Checking…`.
    public init(load: @escaping @Sendable () throws -> [Workhorse],
                gather: @escaping @Sendable ([Workhorse]) async -> [Gathered],
                save: @escaping @Sendable (CheckResult) -> Void) {
        self.load = load
        self.gather = gather
        self.save = save
        self.menu = Menu(symbol: MenuModel.stillCheckingSymbol,
                         items: [.line("Checking…", indent: 0)])
    }

    /// Loads the list, checks every workhorse, saves what the reports changed and builds the menu.
    /// A saved list that can't be read gives a menu with the warning symbol and one line saying so.
    /// A refresh that starts while another is still running does nothing.
    public func refresh() async {
        if refreshing { return }
        refreshing = true
        defer { refreshing = false }

        let load = self.load
        let list: [Workhorse]
        do {
            list = try await Task.detached { try load() }.value
        } catch {
            menu = Menu(symbol: "exclamationmark.triangle",
                        items: [.line(StatusFormat.storeMessage(error), indent: 0)])
            return
        }

        let gathered = await gather(list)
        let save = self.save
        let checked: [CheckResult] = gathered.compactMap {
            if case .checked(let result) = $0 { return result }
            return nil
        }
        // The saved list is written under a file lock, so it is done off the main thread.
        await Task.detached { for result in checked { save(result) } }.value
        menu = MenuModel.build(gathered)
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
