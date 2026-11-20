import Foundation

/// The four kinds of fix in design 7.5.
public enum FixKind: String, Sendable, Codable {
    /// MacMosh does it, after saying so (`prepare --fix`).
    case auto
    /// A terminal tab runs a `macmosh` command; the person types any password into ssh or `sudo` there.
    case passwordTab
    /// A switch only the person can flip, at the workhorse.
    case atWorkhorse
    /// Nothing to fix.
    case info
}

public enum CheckSide: String, Sendable, Codable { case dailyMac, workhorse }

/// Every check, in the design's order (7.5): the daily Mac's first, then the workhorse's.
public enum CheckID: String, Sendable, Codable, CaseIterable {
    case moshInstalled, terminalChosen, identityExists, opensTerminalTabs, reachesHomeNetwork, tailscaleConnected
    case remoteLoginOn, screenSharingOn, keyAccepted, osAndChip, toolsInstalled, hostScriptCurrent,
         deskServerAndSignIns, staysAwake, restartsAfterPowerCut, fileVaultStatus, homeAddressRecorded,
         firewall, protectedFolders
}

/// What to do about a check.
public enum FixAction: Sendable, Codable, Equatable {
    /// `prepare --fix` does it.
    case automatic
    /// `macmosh` arguments for a terminal tab.
    case tab([String])
    /// Numbered instructions.
    case steps([String])

    private enum CodingKeys: String, CodingKey { case kind, arguments, steps }

    /// `{"kind": "automatic"}`, `{"kind": "tab", "arguments": [...]}` or `{"kind": "steps", "steps": [...]}`.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .automatic:
            try c.encode("automatic", forKey: .kind)
        case .tab(let arguments):
            try c.encode("tab", forKey: .kind)
            try c.encode(arguments, forKey: .arguments)
        case .steps(let steps):
            try c.encode("steps", forKey: .kind)
            try c.encode(steps, forKey: .steps)
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .kind) {
        case "automatic": self = .automatic
        case "tab": self = .tab(try c.decode([String].self, forKey: .arguments))
        case "steps": self = .steps(try c.decode([String].self, forKey: .steps))
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: c, debugDescription: "unknown fix kind \(other)")
        }
    }
}

/// One line of the checklist.
public struct CheckOutcome: Sendable, Codable, Equatable {
    public var id: CheckID
    public var side: CheckSide
    /// nil: information only, or MacMosh couldn't tell.
    public var passed: Bool?
    public var fix: FixKind
    public var title: String
    public var detail: String
    public var action: FixAction?

    public init(id: CheckID, side: CheckSide, passed: Bool?, fix: FixKind, title: String, detail: String,
                action: FixAction?) {
        self.id = id
        self.side = side
        self.passed = passed
        self.fix = fix
        self.title = title
        self.detail = detail
        self.action = action
    }
}

/// What the daily Mac's checks look at besides MacMosh's own files: which programs exist, and
/// whether iTerm2 is installed. Tests pass a stand-in.
struct LocalMac: Sendable {
    var isExecutable: @Sendable (String) -> Bool
    var searchPath: String?
    var iTermInstalled: @Sendable () -> Bool

    static let iTermPath = "/Applications/iTerm.app"

    static var real: LocalMac {
        LocalMac(isExecutable: { FileManager.default.isExecutableFile(atPath: $0) },
                 searchPath: ProcessInfo.processInfo.environment["PATH"],
                 iTermInstalled: { FileManager.default.fileExists(atPath: LocalMac.iTermPath) })
    }
}

/// `macmosh prepare` (design 7.5): every check on the daily Mac and the workhorse, the automatic
/// fixes, and the two terminal-tab flows the checklist points to.
///
/// What `--fix` may do by itself is fixed here: install mosh on this Mac with Homebrew, create MacMosh's
/// own key when none is there, install mosh and tmux on the workhorse with its Homebrew, put the script
/// and its login agent there, ask the login agent to start a stopped desk server, and save the home
/// address. It never runs `sudo`, never changes a power, sharing or security setting, and never restarts
/// the desk server (that closes desks, so it waits for the person to type `restart`).
public struct Checklist: Sendable {
    /// Homebrew's own install command, copied from https://brew.sh on 2026-11-20 ("Install Homebrew").
    public static let homebrewInstallCommand =
        "/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
    /// The workhorse's tools, with Homebrew's folders added to the end of `PATH` as the script does.
    static let workhorseBrewCommand = "PATH=\"$PATH:/opt/homebrew/bin:/usr/local/bin\"; brew install mosh tmux"
    /// Asks macOS to run the login agent now, in the login session. Without `-k`, so a running agent is left alone.
    static let kickstartCommand = "launchctl kickstart \"gui/$(id -u)/\(MacMoshInfo.agentLabel)\""
    /// Homebrew can take minutes to build or download.
    static let brewTimeLimit: Duration = .seconds(600)
    /// The short ssh calls: the script's version, the kickstart, the desk server's restart.
    static let shortTimeLimit: Duration = .seconds(30)

    static let restartQuestion = "Type restart to go ahead: "
    static let restartWord = "restart"
    static let yesQuestion = "Type yes to run it: "
    static let yesWord = "yes"

    private let runner: CommandRunner
    private let paths: Paths
    private let store: WorkhorseStore
    private let checker: StatusChecker
    private let keys: KeyManager
    private let hints: HintsProvider
    private let local: LocalMac

    public init(runner: CommandRunner, paths: Paths, store: WorkhorseStore, checker: StatusChecker,
                keys: KeyManager, hints: HintsProvider) {
        self.init(runner: runner, paths: paths, store: store, checker: checker, keys: keys, hints: hints, local: .real)
    }

    init(runner: CommandRunner, paths: Paths, store: WorkhorseStore, checker: StatusChecker,
         keys: KeyManager, hints: HintsProvider, local: LocalMac) {
        self.runner = runner
        self.paths = paths
        self.store = store
        self.checker = checker
        self.keys = keys
        self.hints = hints
        self.local = local
    }

    // MARK: - Looking

    /// Everything one look found: the outcomes, and what the fixes need to act on them.
    private struct Look {
        var workhorse: Workhorse
        var outcomes: [CheckOutcome]
        var result: CheckResult
        var brewPath: String?
    }

    /// Runs every check and changes nothing. The outcomes come in `CheckID`'s order.
    public func run(for w: Workhorse) async -> [CheckOutcome] {
        await look(w).outcomes
    }

    /// iTerm2 when it is installed, otherwise Terminal, unless the setting names one.
    static func chosenTerminal(setting: TerminalApp?, iTermInstalled: Bool) -> TerminalApp {
        setting ?? (iTermInstalled ? .iterm2 : .appleTerminal)
    }

    private func look(_ given: Workhorse) async -> Look {
        // The saved copy, when there is one: a fix may just have saved something new about it.
        let w = (try? store.find(given.id)).flatMap { $0.id == given.id ? $0 : nil } ?? given
        let setting = (try? store.loadSettings())?.terminal
        let mosh = ToolFinder.find("mosh", path: local.searchPath, isExecutable: local.isExecutable)
        let brew = ToolFinder.find("brew", path: local.searchPath, isExecutable: local.isExecutable)
        async let found = hints.hints(for: w)
        async let checked = checker.check(w)
        let facts = DailyMacFacts(
            moshPath: mosh, brewPath: brew,
            terminal: Self.chosenTerminal(setting: setting, iTermInstalled: local.iTermInstalled()),
            terminalFromSetting: setting != nil,
            identity: keys.identityState(for: w),
            ownKey: w.identityFile?.isEmpty ?? true,
            identityPath: (w.identityFile?.isEmpty ?? true) ? "~/.ssh/macmosh_ed25519" : w.identityFile ?? "",
            tailscaleRunning: await found.tailscaleRunning)
        let result = await checked
        let installed = await installedScript(w, result)
        let outcomes = DailyMacChecks.outcomes(facts)
            + WorkhorseChecks.outcomes(result, saved: w, installed: installed, builtIn: HostScript.version)
        return Look(workhorse: w, outcomes: outcomes, result: result, brewPath: brew)
    }

    /// The script on the workhorse, as far as one check can tell. A report gives its version. When ssh
    /// signed in but the report couldn't be read, the script is asked for its version once, so a newer
    /// script is never mistaken for an old one.
    private func installedScript(_ w: Workhorse, _ r: CheckResult) async -> InstalledScript {
        if let report = r.status { return .version(report.scriptVersion) }
        guard let address = WorkhorseChecks.signedInAddress(r) else { return .unreadable }
        switch r.state {
        case .notSetUp(.hostScriptMissing):
            return .absent
        case .notSetUp(.hostScriptOutdated), .notSetUp(.unreadableReport):
            let result = await ssh(w, address, SSHInvocation.hostCommand(["version"]), timeout: Self.shortTimeLimit)
            guard case .ok(let out) = SSHProbe.classify(result) else { return .unreadable }
            let version = out.split(whereSeparator: \.isNewline).first.map(String.init)?
                .trimmingCharacters(in: .whitespaces) ?? ""
            let looksRight = !version.isEmpty && version.allSatisfy { $0.isASCII && ($0.isNumber || $0 == ".") }
            return looksRight ? .version(version) : .unreadable
        default:
            return .unreadable
        }
    }

    // MARK: - Fixing

    /// Says each automatic fix through `progress`, then does it, in the checklist's order. Then looks
    /// again and returns the fresh outcomes. A fix that fails is said and the rest go on.
    public func applyAutomaticFixes(for w: Workhorse, progress: @Sendable (String) -> Void) async -> [CheckOutcome] {
        let before = await look(w)
        let name = before.workhorse.name
        var fixed = 0
        for outcome in before.outcomes where outcome.passed == false && outcome.action == .automatic {
            fixed += 1
            switch outcome.id {
            case .moshInstalled:
                guard let brew = before.brewPath else { continue }
                progress("Installing mosh on this Mac with Homebrew: brew install mosh")
                let r = await runner.run(brew, ["install", "mosh"], environment: [:], stdin: nil, timeout: Self.brewTimeLimit)
                if r.exitCode != 0 || r.timedOut { progress(Self.failed(r)) }
            case .identityExists:
                progress("Creating MacMosh's own ssh key: ~/.ssh/macmosh_ed25519")
                do { try await keys.ensureIdentity() } catch { progress("That didn't work: \(error)") }
            case .toolsInstalled:
                guard let address = WorkhorseChecks.signedInAddress(before.result) else { continue }
                progress("Installing mosh and tmux on \(name) with its Homebrew: brew install mosh tmux. This can take a few minutes.")
                let r = await ssh(before.workhorse, address, [Self.workhorseBrewCommand], timeout: Self.brewTimeLimit)
                if r.exitCode != 0 || r.timedOut { progress(Self.failed(r)) }
            case .hostScriptCurrent:
                guard let address = WorkhorseChecks.signedInAddress(before.result) else { continue }
                progress("Installing macmosh-host \(HostScript.version) and its login agent on \(name).")
                do {
                    try await HostInstaller(runner: runner, paths: paths).install(on: before.workhorse, address: address)
                } catch let error as HostInstallerError {
                    progress("That didn't work. " + error.message)
                } catch {
                    progress("That didn't work: \(error)")
                }
            case .deskServerAndSignIns:
                guard let address = WorkhorseChecks.signedInAddress(before.result) else { continue }
                progress("Starting the desk server on \(name) through its login agent.")
                let r = await ssh(before.workhorse, address, [Self.kickstartCommand], timeout: Self.shortTimeLimit)
                if r.exitCode != 0 || r.timedOut { progress(Self.failed(r)) }
            case .homeAddressRecorded:
                progress("Saving \(name)'s home address.")
                do { try store.absorb(before.result) } catch {
                    progress("That didn't work: \(StatusFormat.storeMessage(error))")
                }
            default:
                fixed -= 1
            }
        }
        if fixed == 0 { progress("Nothing to fix automatically.") }
        return await look(before.workhorse).outcomes
    }

    private static func failed(_ r: CommandResult) -> String {
        if r.timedOut { return "That didn't finish in time." }
        let last = r.stderr.split(whereSeparator: \.isNewline).last.map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        return "That didn't work (exit code \(r.exitCode))" + (last.isEmpty ? "." : ": \(last)")
    }

    private func ssh(_ w: Workhorse, _ address: String, _ remote: [String], timeout: Duration) async -> CommandResult {
        let argv = SSHInvocation.argv(for: w, address: address, paths: paths, batch: true, tty: false, remote: remote)
        return await runner.run(argv[0], Array(argv.dropFirst()), environment: [:], stdin: nil, timeout: timeout)
    }

    // MARK: - Restarting the desk server

    /// For a desk server whose sign-ins don't work: lists the open desks, says they will close, asks
    /// for the word `restart`, and only then runs `macmosh-host restart-server --yes`. True when it ran.
    public func restartDeskServer(for w: Workhorse, ui: Interaction) async -> Bool {
        let r = await checker.check(w)
        let canRestart: Bool
        switch r.state {
        case .ready, .notSetUp(.deskServerDown): canRestart = true
        default: canRestart = false
        }
        guard canRestart, let address = WorkhorseChecks.signedInAddress(r) else {
            ui.say(StatusFormat.headline(r))
            if let hint = StatusFormat.hint(r) { ui.say(hint) }
            return false
        }
        let desks = r.status?.desks.map(\.name.value) ?? []
        ui.say(desks.isEmpty ? "No desks are open."
                             : "Restarting the desk server closes these desks: \(desks.joined(separator: ", ")).")
        let answer = ui.ask(Self.restartQuestion).trimmingCharacters(in: .whitespacesAndNewlines)
        guard answer == Self.restartWord else {
            ui.say("Nothing was restarted.")
            return false
        }
        let result = await ssh(w, address, SSHInvocation.hostCommand(["restart-server", "--yes"]),
                               timeout: Self.shortTimeLimit)
        guard case .ok = SSHProbe.classify(result) else {
            ui.say("The desk server didn't restart. " + Self.failed(result))
            return false
        }
        let after = await checker.check(w)
        ui.say(StatusFormat.headline(after))
        return true
    }

    // MARK: - Installing Homebrew

    /// The password tab for a workhorse with no Homebrew (design 7.5): shows Homebrew's own install
    /// command, says what it does, asks for `yes`, and hands the terminal to ssh with `-t`. The
    /// password `sudo` asks for is typed into ssh, never into MacMosh. Returns the exit code.
    public func installHomebrew(for w: Workhorse, interactive: InteractiveRunner, ui: Interaction) async -> Int32 {
        let r = await checker.check(w)
        guard r.state != .cantVerify, let address = WorkhorseChecks.signedInAddress(r) else {
            ui.say(StatusFormat.headline(r))
            return ui.finish(1, reason: StatusFormat.hint(r) ?? "MacMosh couldn't sign in to \(w.name).")
        }
        if r.status?.tools.contains(where: { $0.name == "brew" && $0.path != nil }) == true {
            ui.say("Homebrew is already installed on \(w.name).")
            return 0
        }
        ui.say("This runs on \(w.name):")
        ui.say(Self.homebrewInstallCommand)
        ui.say("It downloads Homebrew's installer from GitHub and runs it on \(w.name). The installer explains what it will do and pauses before it does it.")
        ui.say("sudo on \(w.name) will ask for the Mac's password. You are typing into ssh; MacMosh can't see it.")
        let answer = ui.ask(Self.yesQuestion).trimmingCharacters(in: .whitespacesAndNewlines)
        guard answer == Self.yesWord else {
            return ui.finish(1, reason: "Nothing was installed.")
        }
        let argv = SSHInvocation.argv(for: w, address: address, paths: paths, batch: false, tty: true,
                                      remote: [Self.homebrewInstallCommand])
        let code = await interactive.runAttached(argv, environment: [:])
        guard code == 0 else {
            return ui.finish(code, reason: "ssh ended with exit code \(code). Homebrew may not be installed; run this again to try once more.")
        }
        ui.say("Homebrew is installed. Next, install mosh and tmux with: macmosh prepare \(w.id) --fix")
        return 0
    }
}
