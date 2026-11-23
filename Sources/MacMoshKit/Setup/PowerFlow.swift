import Foundation

/// `macmosh power`: shows the exact `pmset` command, asks, and runs it over ssh with `sudo` (design 4, 7.5).
///
/// The password is typed by the person into ssh and `sudo`, which own the terminal at that moment;
/// nothing here reads, stores or sees it. The command comes from `PowerPlanner` as fixed text.
public struct PowerFlow: Sendable {
    static let sudoPrompt = "ssh asks for the Mac's password, for sudo. You are typing into ssh; MacMosh can't see it."
    static let question = "Type yes to run it: "
    static let yes = "yes"

    private let checker: WorkhorseChecking
    private let store: WorkhorseStore
    private let paths: Paths
    private let interactive: InteractiveRunner
    private let keys: KeyManager

    public init(checker: WorkhorseChecking, store: WorkhorseStore, paths: Paths,
                interactive: InteractiveRunner, keys: KeyManager) {
        self.checker = checker
        self.store = store
        self.paths = paths
        self.interactive = interactive
        self.keys = keys
    }

    public func power(_ w: Workhorse, setting: PowerSetting, turnOn: Bool = true, ui: Interaction) async -> Int32 {
        // Key first: with a missing `-i` file ssh would quietly try the user's own keys.
        guard keys.identityState(for: w) == .usable else {
            let r = CheckResult(workhorse: w, state: .notSetUp(.identityUnusable), status: nil, probes: ProbeSet(),
                                answeredAt: nil, homeReachable: nil, checkedAt: Date())
            ui.say(StatusFormat.headline(r))
            return ui.finish(1, reason: StatusFormat.hint(r))
        }

        let r = await checker.check(w)
        switch r.state {
        case .ready, .waitingForLogin:
            break
        default:
            ui.say(StatusFormat.headline(r))
            return ui.finish(1, reason: StatusFormat.hint(r))
        }
        guard let address = r.answeredAt, !address.isEmpty, let status = r.status else {
            var unreachable = r
            unreachable.state = .cantReach(.nothingAnswers)
            ui.say(StatusFormat.headline(unreachable))
            return ui.finish(1, reason: StatusFormat.hint(unreachable))
        }

        let plan: PowerPlan
        do {
            plan = try PowerPlanner.plan(setting, turnOn: turnOn, status: status)
        } catch PowerError.notApplicable(let why) {
            return ui.finish(1, reason: why)
        } catch {
            return ui.finish(1, reason: "\(error)")
        }

        ui.say("This runs on \(r.workhorse.name):")
        ui.say(plan.command)
        ui.say(plan.explanation)
        ui.say(Self.sudoPrompt)
        let answer = ui.ask(Self.question).trimmingCharacters(in: .whitespacesAndNewlines)
        guard answer == Self.yes else {
            return ui.finish(1, reason: "Nothing was changed.")
        }

        let argv = SSHInvocation.argv(for: w, address: address, paths: paths, batch: false, tty: true,
                                      remote: [plan.command])
        let code = await interactive.runAttached(argv, environment: [:])
        guard code == 0 else {
            return ui.finish(code, reason: "ssh ended with exit code \(code), so nothing was recorded. If the setting didn't change, check the password and try again.")
        }

        // Recorded once per command, so "Remove" lists it once however often it ran. A command that puts
        // an earlier one back (lid off) takes that note away instead: there is nothing left to put back.
        do {
            try store.update(id: w.id) { saved in
                if let undone = plan.undoes {
                    saved.powerChanges.removeAll { $0 == undone }
                } else if !saved.powerChanges.contains(plan.command) {
                    saved.powerChanges.append(plan.command)
                }
            }
        } catch {
            ui.say("The change ran, but MacMosh couldn't save a note of it: \(StatusFormat.storeMessage(error))")
        }

        let after = await checker.check(w)
        if let fresh = after.status, after.state.isReadyOrWaiting {
            ui.say(PowerPlanner.valuesLine(fresh))
        } else {
            ui.say("The change ran, but a new check couldn't read the values.")
            ui.say(StatusFormat.headline(after))
        }
        return 0
    }
}

extension WorkhorseState {
    /// Ready (either kind) or Waiting for login: the states in which a report was read and the key works.
    var isReadyOrWaiting: Bool {
        switch self {
        case .ready, .waitingForLogin: return true
        default: return false
        }
    }
}
