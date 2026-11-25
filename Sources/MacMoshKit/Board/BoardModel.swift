import Foundation

/// Builds the window's board from what the menu's checks found (main window design, sections 7.1
/// and 7.2). Pure: no clock, no network, no files; "now" and the time zone are passed in.
///
/// Every word and rule it shows comes from where the menu's does: `WorkhorseBlock` (the headline, the
/// hint, the summary, which buttons in which order, which desks), `ButtonRules` under it, and
/// `MenuModel`'s symbols. What is the window's own: the desks in name order, the folder shown the short
/// way, "Open the N not in a tab", the greyed list, the ended desks' buttons, and a workhorse whose check
/// is running keeping its last result.
///
/// With `tabs`, the records, terminal and time the menu's last build had, each desk past the menu's gate
/// (`WindowLinesGate`) takes the menu's choices for it (issue #134): its Open button is the menu's first line
/// for that desk, each of its windows carries the menu's window line, and New window is the menu's.
public enum BoardModel {
    /// - `latest`, `lastReady`, `checking`, `waitingForDeskServer` and `tabs`: what `MenuRefresher` publishes.
    ///   With no `tabs` (no menu built yet), no desk has the menu's line per window.
    /// - `order`: the saved list of workhorses. Only these are on the board, in this order, each once.
    /// - `ended`: the ended desks by workhorse id (none until the tracker exists).
    /// - `results`: the last action's sentence by workhorse id.
    public static func build(latest: [String: CheckResult], lastReady: [String: CheckResult], checking: Set<String>,
                             order: [Workhorse], waitingForDeskServer: Set<String>, tabs: TabsSeen? = nil,
                             ended: [String: [EndedDesk]] = [:], results: [String: String] = [:],
                             now: Date, timeZone: TimeZone) -> Board {
        if order.isEmpty { return Board(workhorses: [], symbol: MenuModel.noWorkhorsesSymbol) }
        var seen: Set<String> = []
        var workhorses: [BoardWorkhorse] = []
        var states: [WorkhorseState] = []
        for saved in order where seen.insert(saved.id).inserted {
            let id = saved.id
            let r = latest[id]
            var block = r.map { WorkhorseBlock.of($0, waitingForDeskServer: waitingForDeskServer, now: now,
                                                  timeZone: timeZone) }
                ?? .stillChecking(saved)
            // The desks as the menu's build saw them: the same records, terminal and time. Not the board's own
            // `now`, which shapes only the times it shows.
            if let r, let tabs, block.kind == .ready {
                block.desks = ButtonRules.desks(r, tabs: tabs.tabs, now: tabs.at)
            }
            // As in the menu, a workhorse with no answer or waiting for its desk server adds nothing to the symbol.
            let counted = block.kind == .waitingForDeskServer ? nil : r?.state
            if let counted { states.append(counted) }
            let user = (r?.workhorse ?? saved).user
            let lines = block.desks.sorted { inNameOrder($0.name, $1.name) }
            let desks = lines.map { desk($0, workhorse: id, user: user, withButtons: true) }
            var lastReadyDesks: [BoardDesk]?
            var lastReadyAt: Date?
            if block.kind != .ready, let good = lastReady[id] {
                lastReadyDesks = ButtonRules.desks(good).sorted { inNameOrder($0.name, $1.name) }
                    .map { desk($0, workhorse: id, user: good.workhorse.user, withButtons: false) }
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
                buttons: buttons(block, desks: lines, workhorse: id), result: results[id],
                scriptVersion: r?.status?.scriptVersion))
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

    /// The block's buttons as the window takes them (`BoardAction`), with "Open the N not in a tab" just
    /// before New desk… when there is a tab to open (`notInATab`). N is the number of tabs it opens.
    private static func buttons(_ block: WorkhorseBlock, desks: [DeskLine], workhorse id: String) -> [BoardButton] {
        var buttons = block.buttons.map(BoardButton.init)
        let tabs = notInATab(desks, workhorse: id)
        if !tabs.isEmpty, let newDesk = block.newDesk, let at = block.buttons.firstIndex(of: newDesk) {
            buttons.insert(BoardButton(title: "Open the \(tabs.count) not in a tab",
                                       action: .window(.openAllWithoutTab(workhorse: id, tabs: tabs))), at: at)
        }
        return buttons
    }

    /// The tabs "Open the N not in a tab" opens, desk by desk in the order given: for a running desk past the
    /// menu's gate, a tab on each window no tab shows (a window counts as in a tab as the menu counts it); for
    /// any other running desk with no tab attached, one plain tab, as the menu's click on it opens. A closed
    /// desk gets none.
    public static func notInATab(_ desks: [DeskLine], workhorse id: String) -> [[String]] {
        desks.flatMap { line -> [[String]] in
            guard let session = line.session else { return [] }
            if let windows = line.windows { return windows.notInATab }
            return session.attached == 0 ? [ButtonRules.connect(workhorse: id, desk: line.name).words] : []
        }
    }

    /// One desk from `ButtonRules.desks`, which decides which desks there are: the open ones, and a
    /// definition with no session only when it is permanent (the same rule the menu's lines use).
    /// Its Open button is the row's own click; the rest are its buttons. The greyed list has neither.
    ///
    /// A desk with the menu's line per window (`DeskLine.windows`) takes the menu's choices: Open is the menu's
    /// first line, each window has its window line (by window id), and New window is the menu's. Its tab count
    /// is the menu's too. Any other desk keeps `ButtonRules.forDesk`, as the menu does.
    private static func desk(_ line: DeskLine, workhorse id: String, user: String, withButtons: Bool) -> BoardDesk {
        let saved = line.definition
        let session = line.session
        let perWindow = line.windows
        var deskButtons = line.buttons
        if let perWindow {
            deskButtons = deskButtons.compactMap { b in
                switch b.key {
                case "open": return perWindow.first
                case "window": return perWindow.newWindow
                default: return b
                }
            }
        }
        let open = withButtons ? deskButtons.first { $0.key == "open" }.map(BoardButton.init) : nil
        // The menu's Name a window… asks in a tab which window; the window has a button per window instead (issue
        // 144): "Name its window…" in the strip of a desk with one window, "Name…" on each window of any other.
        let canName = withButtons && deskButtons.contains { $0.key == ButtonRules.nameWindowKey }
        let all = session?.windows ?? []
        func naming(_ window: String, _ title: String) -> BoardButton {
            BoardButton(title: title, action: .window(.nameWindow(workhorse: id, desk: line.name, window: window)))
        }
        let onlyWindow = canName && all.count == 1 ? all[0].id : nil
        let buttons = withButtons ? deskButtons.filter { $0.key != "open" }.compactMap { b -> BoardButton? in
            guard b.key == ButtonRules.nameWindowKey else { return BoardButton(b) }
            return onlyWindow.map { naming($0, WindowWords.nameItsWindow) }
        } : []
        let lines = withButtons ? perWindow?.windows ?? [] : []
        return BoardDesk(
            name: line.name, isOpen: line.isOpen,
            windows: all.map { w in
                let mine = w.id.flatMap { id in lines.first { $0.key == "win:\(id)" } }
                let name = canName && all.count > 1 ? w.id.map { naming($0, WindowWords.nameWindow) } : nil
                return BoardWindow(index: w.index, name: w.name, id: w.id, tabs: w.tabs, button: mine.map(BoardButton.init),
                                   nameButton: name)
            },
            windowCount: session?.windowCount ?? 0,
            tabsOpen: session == nil ? 0 : perWindow?.tabs ?? session?.attached ?? 0,
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
    static func inNameOrder(_ a: String, _ b: String) -> Bool {
        let (x, y) = (a.lowercased(), b.lowercased())
        return x == y ? a < b : x < y
    }
}
