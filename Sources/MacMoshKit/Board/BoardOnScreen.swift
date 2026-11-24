import Combine
import Foundation

/// The one object the MacMosh window's views observe: the board on screen, and the notice of the last
/// action (main window design, section 7.2). It is the window's own, as `MenuOnScreen` is the menu's.
///
/// It follows the values `MenuRefresher` publishes for the window (`latest`, `lastReady`, `checking`,
/// `waitingForDeskServer`, and `tabsSeen`, the tabs the menu's last build had), builds the board from them
/// with `BoardModel.build`, and publishes it only
/// when it differs from the board on screen. The menu's view never observes this, and the window's
/// views never observe `MenuOnScreen`, so neither redraws the other. Nothing here changes the
/// refresher's menu: every change the window asks for goes through the refresher, and the menu takes
/// it through `MenuOnScreen` and `HoldStill` as it takes any other.
///
/// The board lists the workhorses on the saved list, in its order, which the refresher does not
/// publish. So this reads the saved list itself, off the main thread, when it starts, whenever a check
/// starts, and when the window opens; a list that can't be read leaves the last one in place and says so.
@MainActor
public final class BoardOnScreen: ObservableObject {
    /// The board the window shows. Changes only when it differs from the one on screen.
    @Published public private(set) var board: Board
    /// What the last action said, the sentence the menu shows as its first line; nil when there is none.
    @Published public private(set) var notice: String?
    /// The menu's sentence about a saved list that can't be read (`StatusFormat.storeMessage`), while the
    /// last read failed; nil once a read works. The board keeps the last list it read.
    @Published public private(set) var listProblem: String?

    /// Checks the workhorses and does what a button asks; the same one the menu uses.
    public let refresher: MenuRefresher

    private struct Inputs {
        var latest: [String: CheckResult]
        var lastReady: [String: CheckResult]
        var checking: Set<String>
        var waitingForDeskServer: Set<String>
        var tabs: TabsSeen?
    }

    private let load: @Sendable () throws -> [Workhorse]
    private let log: @Sendable (String) -> Void
    private let now: @Sendable () -> Date
    private let timeZone: TimeZone
    private var inputs: Inputs
    private var order: [Workhorse] = []
    /// Numbers each read of the saved list, so that a slow earlier read can't replace a later one.
    private var reads: UInt64 = 0
    /// The number of the read whose list the board uses.
    private var shownRead: UInt64 = 0
    private var watches: [AnyCancellable] = []

    /// Follows `refresher` from now on. `load` reads the saved list (the refresher's own), `log` takes
    /// the lines of `MenuLog`, and `now` and `timeZone` shape the times the board shows.
    public init(refresher: MenuRefresher, load: @escaping @Sendable () throws -> [Workhorse],
                log: @escaping @Sendable (String) -> Void = { MenuLog.write($0) },
                now: @escaping @Sendable () -> Date = { Date() }, timeZone: TimeZone = .current) {
        self.refresher = refresher
        self.load = load
        self.log = log
        self.now = now
        self.timeZone = timeZone
        inputs = Inputs(latest: refresher.latest, lastReady: refresher.lastReady, checking: refresher.checking,
                        waitingForDeskServer: refresher.waitingForDeskServer, tabs: refresher.tabsSeen)
        notice = refresher.notice
        board = BoardModel.build(latest: inputs.latest, lastReady: inputs.lastReady, checking: inputs.checking,
                                 order: [], waitingForDeskServer: inputs.waitingForDeskServer, tabs: inputs.tabs,
                                 now: now(), timeZone: timeZone)
        // Apple, Published (https://developer.apple.com/documentation/combine/published): "publishing
        // occurs in the property's willSet block, meaning subscribers receive the new value before it's
        // actually set on the property". So the new values are read from the publishers, never from the
        // refresher, as `MenuOnScreen` does. The refresher is a main-actor class, so they arrive on the
        // main actor; `MainActor.assumeIsolated` "will crash" if that is ever not so
        // (https://developer.apple.com/documentation/swift/mainactor/assumeisolated(_:file:line:)).
        // A fifth value is joined with Apple's combineLatest(_:) (https://developer.apple.com/documentation/combine/publisher/combinelatest(_:)):
        // "Subscribes to an additional publisher and publishes a tuple upon receiving output from either publisher."
        watches.append(refresher.$latest
            .combineLatest(refresher.$lastReady, refresher.$checking, refresher.$waitingForDeskServer)
            .combineLatest(refresher.$tabsSeen)
            .sink { [weak self] four, tabs in
                let (latest, lastReady, checking, waiting) = four
                MainActor.assumeIsolated {
                    self?.take(Inputs(latest: latest, lastReady: lastReady, checking: checking,
                                      waitingForDeskServer: waiting, tabs: tabs))
                }
            })
        watches.append(refresher.$notice.sink { [weak self] next in
            MainActor.assumeIsolated {
                guard let self, self.notice != next else { return }
                self.notice = next
            }
        })
        watches.append(refresher.$isRefreshing.sink { [weak self] starting in
            guard starting else { return }
            MainActor.assumeIsolated { self?.startReading() }
        })
        startReading()
    }

    /// The page for the workhorse with that id, laid out with the time and time zone passed in; nil when
    /// it is not on the board.
    public func page(_ id: String) -> WorkhorsePage? {
        board.workhorses.first { $0.id == id }.map { WorkhorsePage($0, now: now(), timeZone: timeZone) }
    }

    /// The window came on screen: says so in the log, reads the saved list, and asks for one check.
    /// This is the only check the window adds; Check now asks for another.
    public func opened() async {
        log(MenuLog.windowOpened)
        await reloadList()
        await refresher.refresh()
    }

    /// Reads the saved list off the main thread and rebuilds the board with it. A list that can't be
    /// read keeps the last one and sets `listProblem`. A read that started before one already shown
    /// changes nothing.
    public func reloadList() async {
        reads &+= 1
        let mine = reads
        let load = self.load
        let read = await Task.detached(operation: { Result { try load() } }).value
        guard mine > shownRead else { return }
        shownRead = mine
        switch read {
        case .success(let list):
            if listProblem != nil { listProblem = nil }
            order = list
            rebuild()
        case .failure(let error):
            let problem = StatusFormat.storeMessage(error)
            if listProblem != problem { listProblem = problem }
        }
    }

    private func startReading() {
        Task { [weak self] in await self?.reloadList() }
    }

    private func take(_ next: Inputs) {
        inputs = next
        rebuild()
    }

    private func rebuild() {
        let next = BoardModel.build(latest: inputs.latest, lastReady: inputs.lastReady, checking: inputs.checking,
                                    order: order, waitingForDeskServer: inputs.waitingForDeskServer, tabs: inputs.tabs,
                                    now: now(), timeZone: timeZone)
        if next != board { board = next }
    }
}
