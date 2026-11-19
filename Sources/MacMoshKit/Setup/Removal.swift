import Foundation

/// `remove` stopped before the workhorse left the list. The reason has already been said to the
/// person (and `ui.finish` has run); the command only needs to exit with a failure.
public enum RemovalError: Error, Equatable {
    case stopped(String)
}

/// `macmosh remove` (design 7.11): takes MacMosh off a workhorse, then off this Mac's list.
///
/// Over ssh it runs the workhorse script's `uninstall` with this Mac's public key, and nothing else:
/// the script deletes one line of `authorized_keys`, never the file, and refuses an empty key.
public struct Removal: Sendable {
    /// The six things design 7.11 says MacMosh puts on a workhorse, in plain words.
    public static let whatIsRemoved: [String] = [
        "The MacMosh script: ~/.macmosh/macmosh-host",
        "Its tmux settings: ~/.macmosh/tmux.conf",
        "Your desk definitions: ~/.macmosh/desks.tsv",
        "Its log: ~/.macmosh/host.log",
        "The login agent that starts the desk server: ~/Library/LaunchAgents/io.github.shariqh.macmosh.host.plist",
        "The one line in ~/.ssh/authorized_keys that holds this Mac's MacMosh key. The rest of that file stays as it is.",
    ]

    static let question = "Type remove to go ahead: "
    static let word = "remove"
    static let openDesksKeepRunning = "Desks that are open keep running until you close them."
    static let powerChangesSentence = "Power settings changed through MacMosh, in case you want to put them back:"
    /// The uninstall is one short ssh call.
    static let uninstallTimeLimit: Duration = .seconds(30)

    private let store: WorkhorseStore
    private let paths: Paths
    private let runner: CommandRunner
    private let keys: KeyManager
    private let checker: WorkhorseChecking

    public init(store: WorkhorseStore, paths: Paths, runner: CommandRunner, keys: KeyManager,
                checker: WorkhorseChecking) {
        self.store = store
        self.paths = paths
        self.runner = runner
        self.keys = keys
        self.checker = checker
    }

    /// Lists what goes, asks for the word `remove`, runs the uninstall on the workhorse (unless
    /// `forgetOnly`), prints the power changes and deletes the workhorse from the list. Any stop
    /// along the way leaves it in the list, says why, and throws `RemovalError.stopped`.
    /// `ui` is asked nothing when `skipQuestion` is true (a program started the command).
    public func remove(_ w: Workhorse, forgetOnly: Bool, skipQuestion: Bool = false, ui: Interaction) async throws {
        var blob = ""
        if !forgetOnly {
            // Key first: with a missing `-i` file ssh would quietly try the user's own keys.
            guard keys.identityState(for: w) == .usable else {
                let r = CheckResult(workhorse: w, state: .notSetUp(.identityUnusable), status: nil, probes: ProbeSet(),
                                    answeredAt: nil, homeReachable: nil, checkedAt: Date())
                ui.say(StatusFormat.headline(r))
                throw stop(ui, StatusFormat.hint(r))
            }
            do {
                blob = try keys.publicKeyBlob(for: w)
            } catch IdentityError.noPublicKey(let path) {
                throw stop(ui, "MacMosh can't read this Mac's public key at \(path), so it can't tell \(w.name) which key line to remove. To remove it from this Mac's list alone, run: macmosh remove \(w.id) --forget-only")
            }
        }

        if forgetOnly {
            ui.say("This removes \(w.name) from this Mac's list. Nothing on \(w.name) changes: what MacMosh put there stays.")
        } else {
            ui.say("Removing MacMosh from \(w.name) takes off:")
            for item in Self.whatIsRemoved { ui.say("  - " + item) }
            ui.say(Self.openDesksKeepRunning)
        }
        if !skipQuestion {
            let answer = ui.ask(Self.question).trimmingCharacters(in: .whitespacesAndNewlines)
            guard answer == Self.word else { throw stop(ui, "Nothing was removed.") }
        }

        if !forgetOnly {
            let r = await checker.check(w)
            guard Self.canUninstall(r.state), let address = r.answeredAt, !address.isEmpty else {
                ui.say(StatusFormat.headline(r))
                var reason = StatusFormat.hint(r).map { $0 + " " } ?? ""
                reason += "MacMosh can't reach \(w.name) to remove itself, so nothing was removed. "
                reason += "To remove it from this Mac's list alone, run: macmosh remove \(w.id) --forget-only"
                throw stop(ui, reason)
            }
            let argv = SSHInvocation.argv(for: w, address: address, paths: paths, batch: true, tty: false,
                                          remote: SSHInvocation.hostCommand(["uninstall", "--key", blob]))
            let result = await runner.run(argv[0], Array(argv.dropFirst()), environment: [:], stdin: nil,
                                          timeout: Self.uninstallTimeLimit)
            guard result.exitCode == 0, !result.timedOut else {
                let said = result.stderr.split(whereSeparator: \.isNewline).last.map(String.init) ?? ""
                var reason = result.timedOut ? "\(w.name) didn't answer in time." : "The uninstall on \(w.name) failed (exit code \(result.exitCode))."
                if !said.isEmpty { reason += " " + said }
                reason += " \(w.name) is still in your list. To remove it from this Mac's list alone, run: macmosh remove \(w.id) --forget-only"
                throw stop(ui, reason)
            }
            ui.say("MacMosh is off \(w.name).")
        }

        if !w.powerChanges.isEmpty {
            ui.say(Self.powerChangesSentence)
            for command in w.powerChanges { ui.say("  " + command) }
        }
        do {
            try store.remove(id: w.id)
        } catch StoreError.notFound {
            // Already gone from the list: nothing left to do.
        } catch {
            throw stop(ui, "MacMosh is off the workhorse, but couldn't change its list: \(StatusFormat.storeMessage(error))")
        }
        ui.say("\(w.name) is no longer in your list.")
    }

    /// The states in which the key works and the script can be run. Without a script on it
    /// (`hostScriptMissing`) there is nothing to run.
    static func canUninstall(_ state: WorkhorseState) -> Bool {
        switch state {
        case .ready, .waitingForLogin: return true
        case .notSetUp(let problem):
            switch problem {
            case .hostScriptOutdated, .unreadableReport, .deskServerDown: return true
            case .notPaired, .identityUnusable, .hostScriptMissing: return false
            }
        case .locked, .cantVerify, .cantReach: return false
        }
    }

    private func stop(_ ui: Interaction, _ reason: String?) -> RemovalError {
        _ = ui.finish(1, reason: reason)
        return .stopped(reason ?? "")
    }
}
