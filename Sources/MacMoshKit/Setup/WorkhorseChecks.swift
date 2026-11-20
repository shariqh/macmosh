import Foundation

/// The script on a workhorse, as far as a check could tell.
enum InstalledScript: Sendable, Equatable {
    /// ssh signed in, and the shell couldn't find or run the script.
    case absent
    case version(String)
    /// MacMosh couldn't tell: nothing signed in, or the script didn't say its version.
    case unreadable
}

/// The thirteen checks on the workhorse (design 7.5), worked out from one status check. A pure
/// function: the fixes themselves are run by `Checklist`.
///
/// Two rules keep it safe. A different host key at any address (`cantVerify`) means no report is
/// trusted, no fix is automatic and no password tab is offered. And a fix that changes power,
/// sharing or security settings, or closes desks, is never `.automatic`.
enum WorkhorseChecks {
    static func outcomes(_ r: CheckResult, saved: Workhorse, installed: InstalledScript, builtIn: String) -> [CheckOutcome] {
        let c = Context(r: r, saved: saved)
        return [remoteLogin(c), screenSharing(c), keyAccepted(c), osAndChip(c), tools(c),
                script(c, installed: installed, builtIn: builtIn), deskServer(c), staysAwake(c),
                restartsAfterPowerCut(c), fileVault(c), homeAddress(c), firewall(c), protectedFolders(c)]
    }

    /// The address where ssh signed in with MacMosh's key during the check: it gave the report, or ran
    /// the remote command and got an error back. nil when nothing signed in, and always when a
    /// different host key answered anywhere.
    static func signedInAddress(_ r: CheckResult) -> String? {
        guard r.state != .cantVerify, let address = r.answeredAt, !address.isEmpty else { return nil }
        let w = r.workhorse
        let named: [(ProbeOutcome?, String?)] = [(r.probes.main, w.mainAddress), (r.probes.home, w.homeAddress),
                                                 (r.probes.local, w.localName)]
        for case (let outcome?, address?) in named {
            switch outcome {
            case .ok, .remoteFailed: return address
            default: continue
            }
        }
        return nil
    }

    private struct Context {
        let r: CheckResult
        let saved: Workhorse
        var id: String { saved.id }
        var name: String { saved.name }
        /// The report, unless a different host key answered somewhere: then nothing in it is trusted.
        var report: HostStatus? { r.state == .cantVerify ? nil : r.status }
        var signedIn: Bool { signedInAddress(r) != nil }
        /// Said where a check needs a report and there is none.
        var couldNotCheck: String { "MacMosh couldn't check this: \(StatusFormat.headline(r))." }
    }

    private static func outcome(_ id: CheckID, _ passed: Bool?, _ fix: FixKind, _ title: String, _ detail: String,
                                _ action: FixAction? = nil) -> CheckOutcome {
        CheckOutcome(id: id, side: .workhorse, passed: passed, fix: fix, title: title, detail: detail, action: action)
    }

    /// The outcome for a check that needs something the check didn't get.
    private static func unknown(_ id: CheckID, _ title: String, _ c: Context) -> CheckOutcome {
        outcome(id, nil, .info, title, c.couldNotCheck)
    }

    // MARK: - The checks

    private static func remoteLogin(_ c: Context) -> CheckOutcome {
        let title = "Remote Login is on"
        let all = c.r.probes.all
        guard !all.isEmpty else { return unknown(.remoteLoginOn, title, c) }
        let answered = all.contains { outcome in
            switch outcome {
            case .timedOut, .refused, .unresolved, .unreachable, .identityUnusable: return false
            default: return true
            }
        }
        if answered { return outcome(.remoteLoginOn, true, .atWorkhorse, title, "The workhorse answers ssh.") }
        let hint = StatusFormat.hint(c.r) ?? "Nothing answered ssh."
        return outcome(.remoteLoginOn, false, .atWorkhorse, title,
                       "Nothing answered ssh. \(hint)",
                       .steps(["At the workhorse, turn on System Settings > General > Sharing > Remote Login."]))
    }

    private static func screenSharing(_ c: Context) -> CheckOutcome {
        let title = "Screen Sharing is on"
        guard let s = c.report else { return unknown(.screenSharingOn, title, c) }
        switch s.screenSharing {
        case .yes:
            return outcome(.screenSharingOn, true, .atWorkhorse, title, "Screen Sharing is on.")
        case .no:
            return outcome(.screenSharingOn, false, .atWorkhorse, title,
                           "Screen Sharing is off, so Log in… and restart recovery can't show the workhorse's screen.",
                           .steps(["At the workhorse, turn on System Settings > General > Sharing > Screen Sharing."]))
        case .unknown:
            return outcome(.screenSharingOn, nil, .atWorkhorse, title,
                           "MacMosh couldn't tell. Look in System Settings > General > Sharing.")
        }
    }

    private static func keyAccepted(_ c: Context) -> CheckOutcome {
        let title = "MacMosh's ssh key is accepted"
        if c.signedIn { return outcome(.keyAccepted, true, .passwordTab, title, "MacMosh's key signs in.") }
        switch c.r.state {
        case .notSetUp(.notPaired):
            return outcome(.keyAccepted, false, .passwordTab, title,
                           "The workhorse turned MacMosh's key down. Pairing installs it; you type the workhorse's password into ssh once.",
                           .tab(["pair", c.id]))
        case .cantVerify:
            // Never a password tab here: something else may be answering at the address.
            return outcome(.keyAccepted, false, .info, title, StatusFormat.hint(c.r) ?? c.couldNotCheck)
        case .notSetUp(.identityUnusable):
            return outcome(.keyAccepted, nil, .info, title,
                           "MacMosh couldn't check this: it can't use its own key on this Mac (see above).")
        default:
            return unknown(.keyAccepted, title, c)
        }
    }

    private static func osAndChip(_ c: Context) -> CheckOutcome {
        let title = "macOS version and chip"
        let version = c.report.map(\.osVersion).flatMap { $0.isEmpty ? nil : $0 } ?? c.saved.osVersion
        let arch = c.report.map(\.arch).flatMap { $0.isEmpty ? nil : $0 } ?? c.saved.arch
        guard let version, !version.isEmpty else { return unknown(.osAndChip, title, c) }
        let chip: String
        switch arch {
        case "arm64"?: chip = " on Apple silicon"
        case "x86_64"?: chip = " on an Intel chip"
        case let other?: chip = " (\(other))"
        case nil: chip = ""
        }
        let recovery = OSSupport.canUnlockOverSSH(osVersion: version, arch: arch)
            ? "Restart recovery over ssh is offered."
            : "Restart recovery over ssh needs macOS 26 or later on Apple silicon, so after a restart you unlock it at the Mac."
        return outcome(.osAndChip, nil, .info, title, "macOS \(version)\(chip). \(recovery)")
    }

    private static func tools(_ c: Context) -> CheckOutcome {
        let title = "Homebrew, mosh and tmux are installed"
        guard let s = c.report else { return unknown(.toolsInstalled, title, c) }
        func tool(_ name: String) -> HostStatus.Tool? { s.tools.first { $0.name == name && $0.path != nil } }
        let missing = ["mosh-server", "tmux"].filter { tool($0) == nil }
        if missing.isEmpty {
            let list = ["mosh-server", "tmux"].compactMap(tool).map { t in t.version.map { "\(t.name) \($0)" } ?? t.name }
            return outcome(.toolsInstalled, true, .auto, title, list.joined(separator: " and ") + ".")
        }
        let names = missing.joined(separator: " and ")
        if tool("brew") != nil {
            return outcome(.toolsInstalled, false, .auto, title,
                           "\(names) \(missing.count == 1 ? "isn't" : "aren't") installed on \(c.name). MacMosh installs them with its Homebrew.",
                           .automatic)
        }
        return outcome(.toolsInstalled, false, .passwordTab, title,
                       "\(names) \(missing.count == 1 ? "isn't" : "aren't") installed on \(c.name), and neither is Homebrew. Homebrew's installer runs in a tab and asks for the Mac's password; then --fix installs the rest.",
                       .tab(["prepare", c.id, "--install-homebrew"]))
    }

    private static func script(_ c: Context, installed: InstalledScript, builtIn: String) -> CheckOutcome {
        let title = "macmosh-host and the login agent are installed and current"
        guard c.signedIn else { return unknown(.hostScriptCurrent, title, c) }
        let version: String?
        switch installed {
        case .unreadable:
            return outcome(.hostScriptCurrent, false, .info, title,
                           "MacMosh couldn't read the version of the script on \(c.name), so it leaves the script alone.")
        case .absent: version = nil
        case .version(let v): version = v
        }
        switch HostInstaller.decide(installed: version, builtIn: builtIn) {
        case .tooNew:
            return outcome(.hostScriptCurrent, false, .info, title,
                           "This MacMosh is older than the script on the workhorse. Update MacMosh.")
        case .install:
            return outcome(.hostScriptCurrent, false, .auto, title,
                           "The script isn't on \(c.name) yet. MacMosh installs version \(builtIn) and its login agent.",
                           .automatic)
        case .replace:
            return outcome(.hostScriptCurrent, false, .auto, title,
                           "\(c.name) has version \(version ?? "?"). MacMosh replaces it with \(builtIn) and loads its login agent again.",
                           .automatic)
        case .keep:
            if c.report?.agentInstalled == true {
                return outcome(.hostScriptCurrent, true, .auto, title, "Version \(builtIn), with its login agent.")
            }
            let why = c.report == nil ? "Its status report couldn't be read" : "Its login agent isn't installed"
            return outcome(.hostScriptCurrent, false, .auto, title,
                           "\(why). MacMosh installs the script and its login agent again; that is safe to repeat.",
                           .automatic)
        }
    }

    private static func deskServer(_ c: Context) -> CheckOutcome {
        let title = "The desk server is running and sign-ins work"
        guard let s = c.report else { return unknown(.deskServerAndSignIns, title, c) }
        if s.serverUp {
            if s.signIns == .yes { return outcome(.deskServerAndSignIns, true, .auto, title, "Running, with sign-ins working.") }
            // Restarting closes every desk, so it is never automatic: the person types `restart`.
            return outcome(.deskServerAndSignIns, false, .passwordTab, title,
                           "The desk server is running, but tools that keep logins in the keychain look signed out in it. Restarting it through the login agent fixes that, and closes the open desks.",
                           .tab(["prepare", c.id, "--restart-desk-server"]))
        }
        if s.consoleUser != nil {
            return outcome(.deskServerAndSignIns, false, .auto, title,
                           "The desk server isn't running. MacMosh asks the login agent to start it.", .automatic)
        }
        return outcome(.deskServerAndSignIns, false, .atWorkhorse, title,
                       "Nobody is logged in at \(c.name), so the desk server can't start.",
                       .steps(["Log in at the Mac or with Log in…"]))
    }

    private static func staysAwake(_ c: Context) -> CheckOutcome {
        let title = "It stays awake on power and wakes for network access"
        guard let s = c.report else { return unknown(.staysAwake, title, c) }
        if s.power.sleepOnPower == 0 && s.power.wakeForNetwork == 1 {
            return outcome(.staysAwake, true, .passwordTab, title, "Sleep on power: 0 · Wake for network access: 1")
        }
        return outcome(.staysAwake, false, .passwordTab, title,
                       PowerPlanner.valuesLine(s) + ". The tab shows the exact pmset command; you type the Mac's password into ssh.",
                       .tab(["power", c.id, "awake"]))
    }

    private static func restartsAfterPowerCut(_ c: Context) -> CheckOutcome {
        let title = "It restarts after a power cut"
        guard let s = c.report else { return unknown(.restartsAfterPowerCut, title, c) }
        if s.isLaptop {
            return outcome(.restartsAfterPowerCut, nil, .info, title,
                           "This is a laptop: it carries on from its battery, so this setting is for desktop Macs.")
        }
        if s.power.autoRestart == 1 {
            return outcome(.restartsAfterPowerCut, true, .passwordTab, title, "Restart after a power cut: 1")
        }
        return outcome(.restartsAfterPowerCut, false, .passwordTab, title,
                       "Restart after a power cut: \(s.power.autoRestart.map(String.init) ?? "not listed"). The tab shows the exact pmset command; you type the Mac's password into ssh.",
                       .tab(["power", c.id, "autorestart"]))
    }

    private static func fileVault(_ c: Context) -> CheckOutcome {
        let title = "FileVault"
        guard let s = c.report else { return unknown(.fileVaultStatus, title, c) }
        let state: String
        switch s.fileVault {
        case .yes: state = "FileVault is on: after a restart the disk stays locked until someone types the Mac's password."
        case .no: state = "FileVault is off."
        case .unknown: state = "MacMosh couldn't tell whether FileVault is on."
        }
        return outcome(.fileVaultStatus, nil, .info, title, state + " MacMosh never changes it.")
    }

    private static func homeAddress(_ c: Context) -> CheckOutcome {
        let title = "The home address is recorded"
        if let saved = c.saved.homeAddress, !saved.isEmpty {
            return outcome(.homeAddressRecorded, true, .auto, title, saved)
        }
        guard let s = c.report else { return unknown(.homeAddressRecorded, title, c) }
        if let reported = s.home.address, !reported.isEmpty {
            return outcome(.homeAddressRecorded, false, .auto, title,
                           "Not saved yet. MacMosh saves \(reported); every status check keeps it up to date.", .automatic)
        }
        return outcome(.homeAddressRecorded, false, .info, title,
                       "\(c.name) didn't report a home address. It may not be on a home network right now.")
    }

    private static func firewall(_ c: Context) -> CheckOutcome {
        let title = "The macOS firewall"
        guard let s = c.report else { return unknown(.firewall, title, c) }
        let detail: String
        switch s.firewall {
        case .yes:
            detail = "The firewall is on, so mosh may be blocked. If a desk won't open with mosh, use Plain ssh for this workhorse, or allow mosh-server in the firewall's options at the workhorse. MacMosh never changes the firewall."
        case .no: detail = "The firewall is off."
        case .unknown: detail = "MacMosh couldn't tell whether the firewall is on."
        }
        return outcome(.firewall, nil, .info, title, detail)
    }

    private static func protectedFolders(_ c: Context) -> CheckOutcome {
        let tmux = c.report?.tools.first { $0.name == "tmux" }?.path ?? "/opt/homebrew/bin/tmux"
        return outcome(.protectedFolders, nil, .atWorkhorse, "Desks can open protected folders",
                       "Optional. If a desk can't open a folder macOS protects, give tmux Full Disk Access.",
                       .steps(["At the workhorse, open System Settings > Privacy & Security > Full Disk Access.",
                               "Add tmux (\(tmux)) to the list and turn it on."]))
    }
}
