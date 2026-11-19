import Foundation

/// What ssh said at each of a workhorse's addresses during one check.
public struct ProbeSet: Sendable, Equatable {       // nil: that address wasn't tried
    public var main: ProbeOutcome?
    public var home: ProbeOutcome?
    public var local: ProbeOutcome?

    public init(main: ProbeOutcome? = nil, home: ProbeOutcome? = nil, local: ProbeOutcome? = nil) {
        self.main = main
        self.home = home
        self.local = local
    }

    /// The outcomes of the addresses that were tried: main, home, then the local name.
    public var all: [ProbeOutcome] { [main, home, local].compactMap { $0 } }
}

/// Works out a workhorse's state from one check. A pure function: no clock, no files, no commands.
public enum StateResolver {
    /// Applies the plan's rules in order; the first that matches wins. Where two readings could
    /// disagree, the order puts the cautious one first: a different host key at any address beats
    /// a perfect report from another, and a key this Mac can't use is never shown as Locked.
    public static func resolve(workhorse: Workhorse, probes: ProbeSet,
                               status: Result<HostStatus, HostStatusError>?,   // nil: no address answered with a report
                               hints: Hints, identityUsable: Bool) -> WorkhorseState {
        let all = probes.all

        // Rule 1: a different or unknown host key at any address. Stop; never offer a password.
        if all.contains(where: { $0 == .hostKeyChanged || $0 == .hostKeyUnknown }) {
            return .cantVerify
        }

        // Rule 2: the key on this Mac is missing or can't be used. "Your ssh key is locked", not Locked.
        if !identityUsable || all.contains(where: isIdentityUnusable) {
            return .notSetUp(.identityUnusable)
        }

        // Rule 3: the remote shell couldn't find or run the script.
        if all.contains(where: { remoteExitCode($0).map { $0 == 126 || $0 == 127 } ?? false }) {
            return .notSetUp(.hostScriptMissing)
        }

        // Rule 4: the script speaks another protocol.
        if case .failure(.unsupportedProtocol) = status {
            return .notSetUp(.hostScriptOutdated)
        }

        // Rule 4a: a report that was cut off or had no header, or the script failed another way.
        if case .failure(.truncated) = status { return .notSetUp(.unreadableReport) }
        if case .failure(.noHeader) = status { return .notSetUp(.unreadableReport) }
        if all.contains(where: { remoteExitCode($0) != nil }) {
            return .notSetUp(.unreadableReport)
        }

        // Rule 4b: ssh got through, but there is no report to read. Never guess a state.
        if status == nil, all.contains(where: isOK) {
            return .notSetUp(.unreadableReport)
        }

        if case .success(let report) = status {
            // Rule 5: a report, and nobody logged in at the screen.
            if report.consoleUser == nil { return .waitingForLogin }
            // Rule 6: somebody logged in, desk server down.
            if !report.serverUp { return .notSetUp(.deskServerDown) }
            // Rule 7: server up. Only a sign-in check that said "ok" counts as working.
            return .ready(signIns: report.signIns == .yes)
        }

        // Rule 8: an address that offers no key sign-in at all: the locked screen (design 7.6).
        if all.contains(where: { deniedMethods($0).map { !$0.contains("publickey") } ?? false }) {
            return .locked
        }

        // Rule 9: a refusal at a Tailscale main address. Tailscale only runs after login, so this
        // can't be the locked screen.
        if let main = probes.main, deniedMethods(main) != nil, hints.peerOnline != nil {
            return .notSetUp(.notPaired)
        }

        let refused = all.contains { deniedMethods($0) != nil }

        // Rule 10: any other refusal of a key that worked before: the fallback signal for Locked.
        if refused, workhorse.lastKeyAccepted != nil {
            return .locked
        }

        // Rule 11: any other refusal of a key that never worked.
        if refused {
            return .notSetUp(.notPaired)
        }

        // Rule 12: nothing answered.
        return .cantReach(reason(hints))
    }

    /// The reason shown under "Can't reach it": the first that applies.
    static func reason(_ hints: Hints) -> UnreachableReason {
        if hints.tailscaleRunning == false { return .tailscaleOff }
        if !hints.hasNetwork { return .noNetwork }
        if hints.otherVPN { return .otherVPN }
        if hints.peerOnline == false && hints.atHome == false { return .awayAndOffline }
        return .nothingAnswers
    }

    private static func isOK(_ outcome: ProbeOutcome) -> Bool {
        if case .ok = outcome { return true }
        return false
    }

    private static func isIdentityUnusable(_ outcome: ProbeOutcome) -> Bool {
        if case .identityUnusable = outcome { return true }
        return false
    }

    /// The remote command's exit code, when ssh signed in and the command failed.
    private static func remoteExitCode(_ outcome: ProbeOutcome) -> Int32? {
        if case .remoteFailed(let code, _) = outcome { return code }
        return nil
    }

    /// The sign-in methods offered, when the workhorse refused the key.
    private static func deniedMethods(_ outcome: ProbeOutcome) -> [String]? {
        if case .authDenied(let methods) = outcome { return methods }
        return nil
    }
}
