import Foundation

/// Builds the window's board from what the menu's checks found (main window design, sections 7.1
/// and 7.2). Pure: no clock, no network, no files; "now" and the time zone are passed in.
///
/// Every word and rule it shows comes from where the menu's does: `WorkhorseBlock` (the headline, the
/// hint, the summary, which buttons in which order, which desks), `ButtonRules` under it, and
/// `MenuModel`'s symbols. What is the window's own: the desks in name order, the folder shown the short
/// way, "Open the N not in a tab", the greyed list, the ended desks' buttons, and a workhorse whose check
/// is running keeping its last result.
public enum BoardModel {
    /// - `latest`, `lastReady`, `checking` and `waitingForDeskServer`: what `MenuRefresher` publishes.
    /// - `order`: the saved list of workhorses. Only these are on the board, in this order, each once.
    /// - `ended`: the ended desks by workhorse id (none until the tracker exists).
    /// - `results`: the last action's sentence by workhorse id.
    public static func build(latest: [String: CheckResult], lastReady: [String: CheckResult], checking: Set<String>,
                             order: [Workhorse], waitingForDeskServer: Set<String>,
                             ended: [String: [EndedDesk]] = [:], results: [String: String] = [:],
                             now: Date, timeZone: TimeZone) -> Board {
        if order.isEmpty { return Board(workhorses: [], symbol: MenuModel.noWorkhorsesSymbol) }
        var seen: Set<String> = []
        var workhorses: [BoardWorkhorse] = []
        var states: [WorkhorseState] = []
        for saved in order where seen.insert(saved.id).inserted {
            let id = saved.id
            let r = latest[id]
            let block = r.map { WorkhorseBlock.of($0, waitingForDeskServer: waitingForDeskServer, now: now,
                                                  timeZone: timeZone) }
                ?? .stillChecking(saved)
            // As in the menu, a workhorse with no answer or waiting for its desk server adds nothing to the symbol.
            let counted = block.kind == .waitingForDeskServer ? nil : r?.state
            if let counted { states.append(counted) }
            let user = (r?.workhorse ?? saved).user
            let desks = block.desks.map { desk($0, workhorse: id, user: user, withButtons: true) }
                .sorted(by: inNameOrder)
            var lastReadyDesks: [BoardDesk]?
            var lastReadyAt: Date?
            if block.kind != .ready, let good = lastReady[id] {
                lastReadyDesks = ButtonRules.desks(good).map { desk($0, workhorse: id, user: good.workhorse.user,
                                                                   withButtons: false) }
                    .sorted(by: inNameOrder)
                lastReadyAt = good.checkedAt
            }
            workhorses.append(BoardWorkhorse(
                id: id, name: r?.workhorse.name ?? saved.name, state: r?.state,
                symbol: counted.map(MenuModel.symbol(for:)) ?? MenuModel.stillCheckingSymbol,
                headline: block.headline, hint: block.hint, checkedAt: r?.checkedAt,
                isChecking: checking.contains(id), isWaitingForDeskServer: block.kind == .waitingForDeskServer,
                summary: block.summary, homeReachable: block.homeReachable, desks: desks,
                ended: (ended[id] ?? []).map { onBoard($0, workhorse: id, user: user) },
                lastReadyDesks: lastReadyDesks, lastReadyAt: lastReadyAt,
                buttons: buttons(block, desks: desks, workhorse: id), result: results[id]))
        }
        return Board(workhorses: workhorses, symbol: MenuModel.symbol(forAll: states))
    }

    /// A folder that starts with `/Users/<user>/` is shown with `~/` in its place, and the home folder
    /// itself as `~`; any other folder in full. The report has no home folder (section 5.2), so this
    /// goes by the workhorse's saved user.
    public static func shortFolder(_ folder: String, user: String) -> String {
        guard !user.isEmpty else { return folder }
        let home = "/Users/\(user)"
        if folder == home { return "~" }
        if folder.hasPrefix(home + "/") { return "~" + folder.dropFirst(home.count) }
        return folder
    }

    /// The block's buttons as the window takes them (`BoardAction`), with "Open the N not in a tab"
    /// just before New desk… when a running desk has no tab.
    private static func buttons(_ block: WorkhorseBlock, desks: [BoardDesk], workhorse id: String) -> [BoardButton] {
        var buttons = block.buttons.map(BoardButton.init)
        let noTab = desks.filter { $0.isOpen && $0.tabsOpen == 0 }.map(\.name)
        if !noTab.isEmpty, let newDesk = block.newDesk, let at = block.buttons.firstIndex(of: newDesk) {
            buttons.insert(BoardButton(title: "Open the \(noTab.count) not in a tab",
                                       action: .window(.openAllWithoutTab(workhorse: id, desks: noTab))), at: at)
        }
        return buttons
    }

    /// One desk from `ButtonRules.desks`, which decides which desks there are: the open ones, and a
    /// definition with no session only when it is permanent (the same rule the menu's lines use).
    /// Its Open button is the row's own click; the rest are its buttons. The greyed list has neither.
    private static func desk(_ line: DeskLine, workhorse id: String, user: String, withButtons: Bool) -> BoardDesk {
        let saved = line.definition
        let session = line.session
        let open = withButtons ? line.buttons.first { $0.key == "open" }.map(BoardButton.init) : nil
        let buttons = withButtons ? line.buttons.filter { $0.key != "open" }.map(BoardButton.init) : []
        return BoardDesk(
            name: line.name, isOpen: line.isOpen,
            windows: (session?.windows ?? []).map { BoardWindow(index: $0.index, name: $0.name, id: $0.id, tabs: $0.tabs) },
            windowCount: session?.windowCount ?? 0, tabsOpen: session?.attached ?? 0,
            folder: saved.map { shortFolder($0.folder, user: user) },
            command: saved.flatMap { $0.command.isEmpty ? nil : $0.command },
            reopen: saved?.reopen, keep: saved.map { _ in line.isKept }, permanent: saved.map { _ in line.isPermanent },
            madeByMacMosh: saved != nil, open: open, buttons: buttons)
    }

    /// An ended desk with its folder shown the short way and the window's three buttons for it.
    private static func onBoard(_ desk: EndedDesk, workhorse id: String, user: String) -> EndedDesk {
        var desk = desk
        desk.shownFolder = shortFolder(desk.folder, user: user)
        desk.buttons = [
            BoardButton(title: "Start again", action: .window(.startAgain(workhorse: id, desk: desk.name, keepIt: false))),
            BoardButton(title: "Start again and keep it",
                        action: .window(.startAgain(workhorse: id, desk: desk.name, keepIt: true))),
            BoardButton(title: "Forget", action: .window(.forget(workhorse: id, desk: desk.name))),
        ]
        return desk
    }

    /// Rows are in name order (section 7.1 A), letter case aside, closed desks among them.
    private static func inNameOrder(_ a: BoardDesk, _ b: BoardDesk) -> Bool {
        let (x, y) = (a.name.lowercased(), b.name.lowercased())
        return x == y ? a.name < b.name : x < y
    }
}
