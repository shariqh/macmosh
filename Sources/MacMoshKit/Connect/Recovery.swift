import Foundation

/// Gives a fresh check of one workhorse. `StatusChecker` is the real one; tests hand `Recovery`
/// a scripted one so they don't have to build every state from fake ssh output.
public protocol WorkhorseChecking: Sendable {
    func check(_ w: Workhorse) async -> CheckResult
}

extension StatusChecker: WorkhorseChecking {}

/// Restart recovery (design 5.5, 7.8): `unlock` after a restart, `restart`, and Screen Sharing.
///
/// Built from Apple's documentation and what the hand-built setup saw on one restart. Sitting 2
/// (2026-11-22) ran `restart --full`, `unlock` and `screen` on a real restart and they worked. The
/// `fdesetup authrestart` path (restart without the unlock) has not been run on a real Mac. Every
/// decision comes from a fresh check, never a saved state. Passwords are typed by the person into ssh or `sudo`, which own the terminal at that
/// moment; nothing here reads, stores or sees one.
public struct Recovery: Sendable {
    /// How often `unlock` checks again after the ssh ends, and for how long.
    static let recheckEvery: Duration = .seconds(5)
    static let recheckFor: Duration = .seconds(120)
    /// `open` hands the URL to Screen Sharing and returns at once.
    static let openTimeLimit: Duration = .seconds(10)

    // The words, as the plan gives them.
    static let alreadyUnlocked = "The disk is already unlocked."
    static let olderMac = "This Mac can't be unlocked over the network: that needs Apple silicon and macOS 26 or later. Unlock it at the Mac."
    static let typingIntoSSH = "You are about to type the Mac's password into ssh. MacMosh can't see it."
    static let closesByItself = "When the unlock works, the connection closes by itself."
    static let noDesks = "No desks are open."
    static let restartQuestion = "Type restart to go ahead: "
    static let restartWord = "restart"
    static let sudoPrompt = "ssh asks for the Mac's password, for sudo. You are typing into ssh; MacMosh can't see it."
    static let fdesetupPrompt = "Then fdesetup asks for a user name and password that can unlock the disk."
    static let authRestartCommand = "sudo fdesetup authrestart"
    static let plainRestartCommand = "sudo shutdown -r now"

    private let checker: WorkhorseChecking
    private let paths: Paths
    private let interactive: InteractiveRunner
    private let sleep: @Sendable (Duration) async -> Void

    /// `sleep` waits between the checks after an unlock; tests pass one that returns at once.
    public init(checker: WorkhorseChecking, paths: Paths, interactive: InteractiveRunner,
                sleep: @escaping @Sendable (Duration) async -> Void) {
        self.checker = checker
        self.paths = paths
        self.interactive = interactive
        self.sleep = sleep
    }

    // MARK: - unlock

    /// Hands the terminal to ssh at the address that turned MacMosh's key down, so the person types the
    /// password that unlocks the disk, then checks again until the Mac is no longer Locked.
    ///
    /// No key-file check here, unlike `restart`: the unlock signs in with a password, not MacMosh's
    /// key. The fresh check still needs the key, and without it reads "Your ssh key is locked", which
    /// stops the unlock below: without a check, nothing shows the host key is the pinned one.
    public func unlock(_ w: Workhorse, ui: Interaction) async -> Int32 {
        let r = await checker.check(w)
        switch r.state {
        case .cantVerify:
            // First, before anything else: a different key at an address means no password, ever.
            ui.say(StatusFormat.headline(r))
            return ui.finish(1, reason: StatusFormat.hint(r))
        case .ready, .waitingForLogin:
            ui.say(StatusFormat.headline(r))
            ui.say(Self.alreadyUnlocked)
            return 0
        default:
            break
        }
        guard r.workhorse.canUnlockOverSSH else {
            return ui.finish(1, reason: Self.olderMac)
        }
        guard r.state == .locked else {
            ui.say(StatusFormat.headline(r))
            return ui.finish(1, reason: StatusFormat.hint(r))
        }
        guard let address = Self.unlockAddress(r) else {
            let unreachable = Self.with(r, state: .cantReach(.nothingAnswers))
            ui.say(StatusFormat.headline(unreachable))
            return ui.finish(1, reason: StatusFormat.hint(unreachable))
        }

        ui.say(Self.typingIntoSSH)
        ui.say(Self.closesByItself)
        // ssh's own exit code says little here: the Mac closes the connection when the unlock
        // works, and a wrong password ends it too. The check that follows decides.
        _ = await interactive.runAttached(unlockArgv(for: w, address: address), environment: [:])

        // Up to 2 minutes: the time asked of `sleep` counts, and so does the clock, because each
        // check can itself take seconds when nothing answers. Whichever reaches 2 minutes first ends it.
        var last = r
        var waited: Duration = .zero
        let clock = ContinuousClock()
        let started = clock.now
        while waited < Self.recheckFor, clock.now - started < Self.recheckFor {
            await sleep(Self.recheckEvery)
            waited += Self.recheckEvery
            last = await checker.check(w)
            switch last.state {
            case .locked, .cantReach: continue
            default: return afterUnlock(last, ui: ui)
            }
        }
        ui.say(StatusFormat.headline(last))
        return ui.finish(1, reason: StatusFormat.hint(last))
    }

    /// Says what the Mac became after the unlock. Ready and Waiting for login are a success; any other
    /// state (a different key, a workhorse that needs setting up) keeps the tab open with its hint.
    private func afterUnlock(_ r: CheckResult, ui: Interaction) -> Int32 {
        ui.say(StatusFormat.headline(r))
        switch r.state {
        case .ready:
            return 0
        case .waitingForLogin:
            ui.say("Next: press Log in…, or run: macmosh screen \(r.workhorse.id)")
            return 0
        default:
            return ui.finish(1, reason: StatusFormat.hint(r))
        }
    }

    /// The address the password goes to: the one that answered the check, which for Locked is the one
    /// that turned the key down. The main address is normally the Tailscale name, and Tailscale only
    /// runs after login, so when the home address or the local name also turned the key down, the
    /// password goes there instead. nil when no address answered.
    static func unlockAddress(_ r: CheckResult) -> String? {
        guard let answered = r.answeredAt, !answered.isEmpty else { return nil }
        let w = r.workhorse
        guard answered == w.mainAddress else { return answered }
        let others: [(ProbeOutcome?, String?)] = [(r.probes.home, w.homeAddress), (r.probes.local, w.localName)]
        for case (.authDenied?, let address?) in others where !address.isEmpty && address != answered {
            return address
        }
        return answered
    }

    /// ssh with every host-key option (strict checking against the pinned key is what protects the
    /// password), password sign-in only, no batch mode and no remote command.
    public func unlockArgv(for w: Workhorse, address: String) -> [String] {
        SSHInvocation.argv(for: w, address: address, paths: paths, batch: false, tty: false,
                           extraOptions: ["-o", "PreferredAuthentications=password,keyboard-interactive",
                                          "-o", "PubkeyAuthentication=no"],
                           remote: [])
    }

    // MARK: - restart

    /// Restarts a workhorse that is up: lists the desks that will close, says what the restart will do,
    /// asks for the word `restart`, and only then hands the terminal to ssh with `sudo` and the command.
    public func restart(_ w: Workhorse, full: Bool, ui: Interaction) async -> Int32 {
        // Key first: with a missing `-i` file ssh would quietly try the user's own keys.
        guard KeyManager(paths: paths, runner: NoCommands()).identityState(for: w) == .usable else {
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
        guard let address = r.answeredAt, !address.isEmpty else {
            let unreachable = Self.with(r, state: .cantReach(.nothingAnswers))
            ui.say(StatusFormat.headline(unreachable))
            return ui.finish(1, reason: StatusFormat.hint(unreachable))
        }

        let desks = r.status?.desks.map(\.name.value) ?? []
        ui.say(desks.isEmpty ? Self.noDesks : "These desks will close: \(desks.joined(separator: ", ")).")
        let plan = Self.restartPlan(r.status, full: full, canUnlockOverSSH: r.workhorse.canUnlockOverSSH)
        ui.say(plan.sentence)

        let answer = ui.ask(Self.restartQuestion).trimmingCharacters(in: .whitespacesAndNewlines)
        guard answer == Self.restartWord else {
            return ui.finish(1, reason: "Nothing was restarted.")
        }

        ui.say(Self.sudoPrompt)
        if plan.authRestart { ui.say(Self.fdesetupPrompt) }
        let code = await interactive.runAttached(restartArgv(for: w, address: address, authRestart: plan.authRestart),
                                                 environment: [:])
        return ui.finish(code, reason: "ssh ended with exit code \(code). If the Mac isn't restarting, check the password and try again.")
    }

    /// The command and what to say about it, by the three cases in the plan. A report that doesn't say
    /// whether FileVault is on gets the cautious one: a plain restart, with the locked-disk warning.
    static func restartPlan(_ status: HostStatus?, full: Bool, canUnlockOverSSH: Bool)
        -> (authRestart: Bool, sentence: String) {
        if status?.fileVault == .no {
            return (false, "FileVault is off, so the Mac comes back to the login window by itself.")
        }
        // `fdesetup authrestart` needs FileVault on (`man fdesetup`).
        if status?.fileVault == .yes, status?.authRestart == .yes, !full {
            return (true, "The Mac restarts with its disk already unlocked.")
        }
        let unlockWith = canUnlockOverSSH ? "with Unlock disk…" : "at the Mac."
        return (false, "After this restart the disk will be locked. You unlock it \(unlockWith)")
    }

    /// ssh with a terminal (`sudo` asks for the password there) and the restart command.
    public func restartArgv(for w: Workhorse, address: String, authRestart: Bool) -> [String] {
        SSHInvocation.argv(for: w, address: address, paths: paths, batch: false, tty: true,
                           remote: [authRestart ? Self.authRestartCommand : Self.plainRestartCommand])
    }

    // MARK: - Screen Sharing

    /// `vnc://<user>@<address>`, with the address that answered the check. Built with `URLComponents`,
    /// so an odd user name stays inside the user part. nil when no address answered, and always when
    /// the host key differs: Screen Sharing asks for a password too.
    public static func screenSharingURL(for result: CheckResult) -> URL? {
        guard result.state != .cantVerify, let address = result.answeredAt, !address.isEmpty else { return nil }
        var parts = URLComponents()
        parts.scheme = "vnc"
        // Encoded here, not through `parts.user`: older Foundation leaves a `:` in the user as it
        // is, which would split the name into a user and a password (seen on CI's macOS 15 and 26).
        var allowed = CharacterSet.urlUserAllowed
        allowed.remove(charactersIn: ":")
        let user = result.workhorse.user
        if !user.isEmpty {
            guard let encoded = user.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
            parts.percentEncodedUser = encoded
        }
        parts.host = address
        return parts.url
    }

    /// Checks the workhorse, says the address, and opens Screen Sharing there with `open`.
    public func screen(_ w: Workhorse, runner: CommandRunner, ui: Interaction) async -> Int32 {
        let r = await checker.check(w)
        guard let url = Self.screenSharingURL(for: r), let address = r.answeredAt else {
            ui.say(StatusFormat.headline(r))
            return ui.finish(1, reason: StatusFormat.hint(r) ?? "No address answered, so there is nothing to open.")
        }
        ui.say("Opening Screen Sharing at \(address).")
        let result = await runner.run("/usr/bin/open", [url.absoluteString], environment: [:], stdin: nil,
                                      timeout: Self.openTimeLimit)
        guard result.exitCode == 0, !result.timedOut else {
            let said = result.stderr.split(whereSeparator: \.isNewline).last.map(String.init) ?? ""
            let reason = "Screen Sharing didn't open." + (said.isEmpty ? "" : " " + said)
            return ui.finish(result.exitCode == 0 ? 1 : result.exitCode, reason: reason)
        }
        return 0
    }

    // MARK: - Pieces

    /// The same result with another state, for the words of a state the check didn't name.
    private static func with(_ r: CheckResult, state: WorkhorseState) -> CheckResult {
        var copy = r
        copy.state = state
        return copy
    }
}

/// `KeyManager.identityState` only looks at the key file; this runner makes sure nothing else runs.
private struct NoCommands: CommandRunner {
    func run(_ executable: String, _ arguments: [String], environment: [String: String],
             stdin: Data?, timeout: Duration) async -> CommandResult {
        CommandResult(exitCode: 127, stdout: "", stderr: "not run", timedOut: false)
    }
}
