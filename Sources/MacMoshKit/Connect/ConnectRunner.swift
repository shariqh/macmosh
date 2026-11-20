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

    func run(_ plan: ConnectPlan, title: String, workhorse: Workhorse?, ui: Interaction) async -> Int32 {
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
                let result = Self.result(state, workhorse)
                ui.say(StatusFormat.headline(result))
                return ui.finish(code, reason: StatusFormat.hint(result))
            }
        }
        return ui.finish(code, reason: Self.reason(for: code, tool: plan.argv.first))
    }

    private static func reason(for code: Int32, tool: String?) -> String {
        let name = tool.map { ($0 as NSString).lastPathComponent } ?? "The connection"
        var sentence = "\(name) ended with exit code \(code)."
        if code == connectionLost {
            sentence += " It couldn't connect, or the connection dropped. Your work keeps running on the workhorse."
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
    public func connect(_ check: CheckResult, desk: DeskName, requestedMode: ConnectionMode?, paths: Paths,
                        environment: [String: String], findMosh: () -> String?, ui: Interaction) async -> Int32 {
        let w = check.workhorse
        guard Self.mayConnect(check.state) else {
            ui.say(StatusFormat.headline(check))
            return ui.finish(1, reason: StatusFormat.hint(check) ?? "MacMosh can't open a desk there yet.")
        }

        var mode = requestedMode ?? w.mode
        if mode == .tabs, environment["TERM_PROGRAM"] != "iTerm.app" {
            ui.say("Tabs mode needs iTerm2, and this isn't iTerm2. Opening over mosh instead.")
            mode = .mosh
        }
        var moshPath = ""
        if mode == .mosh {
            guard let found = findMosh() else {
                return ui.finish(1, reason: "mosh isn't installed on this Mac. Run: macmosh prepare \(w.id) --fix")
            }
            moshPath = found
        }

        let plan = ConnectPlanner.plan(workhorse: w, desk: desk, mode: mode, address: check.answeredAt ?? w.mainAddress,
                                       paths: paths, moshPath: moshPath, localeEnvironment: environment,
                                       path: environment["PATH"] ?? ProcessInfo.processInfo.environment["PATH"])
        return await run(plan, title: desk.value, workhorse: w, ui: ui)
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
