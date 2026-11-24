import Foundation

/// Opens a desk in this terminal tab: says what is about to happen, names the tab, hands the terminal
/// to ssh or mosh and, in Tabs mode, tries again while the connection drops (design 5.4, 7.2).
public struct ConnectRunner: Sendable {
    /// How long to wait before trying again after a drop (sitting 1, item 4).
    static let retryAfter: Duration = .seconds(3)
    /// ssh's exit code for a connection that failed or dropped.
    static let connectionLost: Int32 = 255

    private let interactive: InteractiveRunner
    private let sleep: @Sendable (Duration) async -> Void
    private let stateNow: @Sendable () async -> WorkhorseState

    /// `stateNow` is a fresh check of the workhorse; `sleep` waits between tries (tests pass one that returns at once).
    public init(interactive: InteractiveRunner, sleep: @escaping @Sendable (Duration) async -> Void,
                stateNow: @escaping @Sendable () async -> WorkhorseState) {
        self.interactive = interactive
        self.sleep = sleep
        self.stateNow = stateNow
    }

    // MARK: - run

    /// Says the intro, prints the tab's name, hands over the terminal and, with `retryOnDrop`, runs it
    /// again after each exit code 255 while the workhorse is Ready or can't be reached. Any other state
    /// (a different key, a locked disk, nobody logged in) stops the loop with that state's words. Any
    /// non-zero end leaves the tab open with the reason and waits for a key.
    public func run(_ plan: ConnectPlan, title: String, ui: Interaction) async -> Int32 {
        await run(plan, title: title, workhorse: nil, ui: ui)
    }

    /// `connectionEnded` runs once the connection is over for good, before the tab says why and waits for a key.
    func run(_ plan: ConnectPlan, title: String, workhorse: Workhorse?, ui: Interaction,
             connectionEnded: () -> Void = {}) async -> Int32 {
        ui.say(plan.intro)
        ui.say(TabTitle.escape(title))
        var code = await interactive.runAttached(plan.argv, environment: plan.environment)
        while plan.retryOnDrop, code == Self.connectionLost {
            ui.say("Connection lost. Trying again in 3 seconds…")
            await sleep(Self.retryAfter)
            let state = await stateNow()
            switch state {
            case .ready, .cantReach:
                code = await interactive.runAttached(plan.argv, environment: plan.environment)
            default:
                connectionEnded()
                let result = Self.result(state, workhorse)
                ui.say(StatusFormat.headline(result))
                return ui.finish(code, reason: StatusFormat.hint(result))
            }
        }
        connectionEnded()
        return ui.finish(code, reason: Self.reason(for: code, tool: plan.argv.first, desk: title))
    }

    /// The workhorse script's exit code for "no such desk", which ssh hands on as its own.
    static let noSuchDesk: Int32 = 4

    private static func reason(for code: Int32, tool: String?, desk: String) -> String {
        let name = tool.map { ($0 as NSString).lastPathComponent } ?? "The connection"
        var sentence = "\(name) ended with exit code \(code)."
        if code == connectionLost {
            sentence += " It couldn't connect, or the connection dropped. Your work keeps running on the workhorse."
        } else if code == noSuchDesk, name == "ssh" {
            // A tab keeps the desk's name it was opened with, and tries it again after a drop.
            sentence += " The workhorse has no desk named \(desk) now. If it was renamed or removed, open it again from the menu."
        }
        return sentence
    }

    // MARK: - connect

    /// The checks before anything runs, then `run`. A workhorse that isn't Ready gets its headline and hint and
    /// nothing is connected to: a different key (Can't verify it), a locked disk, nobody logged in, nothing answering,
    /// a key that can't be used or a workhorse that isn't paired or set up. A desk server that is only off is let
    /// through: the script's `attach` asks the login agent to start it.
    ///
    /// `requestedMode` is `--mode`; without it the workhorse's own setting is used. Tabs outside iTerm2
    /// (`TERM_PROGRAM` isn't `iTerm.app`) becomes mosh, and says so. `findMosh` finds mosh on this Mac.
    ///
    /// `tab` is `--window`, `--new-window` or `--view` (menu design 8.3). With one, the tab gets a label, a
    /// record (through `noting`, this process by default) and `attach --label <word>` with the option; the
    /// record is removed when the connection ends. Tabs mode refuses them, since it shows every window as its
    /// own tab already. The workhorse's script version is not checked: an older script refuses the option
    /// itself, and its message shows like any other `attach` failure.
    public func connect(_ check: CheckResult, desk: DeskName, requestedMode: ConnectionMode?, paths: Paths,
                        environment: [String: String], findMosh: () -> String?, ui: Interaction,
                        tab: TabTarget? = nil, noting: TabNoting? = nil) async -> Int32 {
        let w = check.workhorse
        guard Self.mayConnect(check.state) else {
            ui.say(StatusFormat.headline(check))
            return ui.finish(1, reason: StatusFormat.hint(check) ?? "MacMosh can't open a desk there yet.")
        }

        let asked = requestedMode ?? w.mode
        let mode = asked.used(inITerm2: environment["TERM_PROGRAM"] == "iTerm.app")
        if mode != asked {
            ui.say("Tabs mode needs iTerm2, and this isn't iTerm2. Opening over mosh instead.")
        }
        if tab != nil, mode == .tabs {
            return ui.finish(1, reason: "Tabs mode already shows every window as its own tab.")
        }
        var moshPath = ""
        if mode == .mosh {
            guard let found = findMosh() else {
                return ui.finish(1, reason: "mosh isn't installed on this Mac. Run: macmosh prepare \(w.id) --fix")
            }
            moshPath = found
        }

        var request: TabRequest?
        var noted: (store: TabRecordStore, label: String)?
        if let tab {
            let noting = noting ?? TabNoting.thisProcess(paths: paths)
            let label = noting.makeLabel()
            request = TabRequest(label: label, target: tab)
            if Self.note(tab, label: label, workhorse: w, desk: desk, environment: environment, noting: noting) {
                noted = (noting.store, label)
            } else {
                ui.say("MacMosh couldn't note this tab, so the menu may not find it later.")
            }
        }

        let plan = ConnectPlanner.plan(workhorse: w, desk: desk, mode: mode, address: check.answeredAt ?? w.mainAddress,
                                       paths: paths, moshPath: moshPath, localeEnvironment: environment,
                                       path: environment["PATH"] ?? ProcessInfo.processInfo.environment["PATH"],
                                       tab: request)
        return await run(plan, title: desk.value, workhorse: w, ui: ui,
                         connectionEnded: { if let noted { noted.store.remove(label: noted.label) } })
    }

    /// Writes the tab's record. False when it can't: without this process's start time the record could
    /// never be trusted, so none is written.
    private static func note(_ tab: TabTarget, label: String, workhorse w: Workhorse, desk: DeskName,
                             environment: [String: String], noting: TabNoting) -> Bool {
        guard let started = noting.started else { return false }
        let record = TabRecord(label: label, workhorse: w.id, desk: desk.value, askedWindow: tab.askedWindow,
                               pid: noting.pid, started: started, tty: noting.tty,
                               terminal: TabRecord.Terminal(environment: environment), openedAt: noting.now())
        do {
            try noting.store.write(record)
            return true
        } catch {
            return false
        }
    }

    static func mayConnect(_ state: WorkhorseState) -> Bool {
        switch state {
        case .ready, .notSetUp(.deskServerDown): return true
        default: return false
        }
    }

    // MARK: - Pieces

    /// A result to take words from, for a state seen by a fresh check that only gave the state.
    private static func result(_ state: WorkhorseState, _ workhorse: Workhorse?) -> CheckResult {
        let w = workhorse ?? Workhorse(id: "", name: "The workhorse", user: "", mainAddress: "", hostKey: "")
        return CheckResult(workhorse: w, state: state, status: nil, probes: ProbeSet(), answeredAt: nil,
                           homeReachable: nil, checkedAt: Date())
    }
}

extension ConnectionMode {
    /// The mode `connect` really uses in a tab: Tabs mode needs iTerm2, so outside it Tabs mode is mosh. The
    /// menu asks the same rule for the terminal its tabs open in (menu design 8.3).
    public func used(inITerm2: Bool) -> ConnectionMode {
        self == .tabs && !inITerm2 ? .mosh : self
    }
}
