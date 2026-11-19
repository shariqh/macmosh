import Foundation

/// Everything one check of one workhorse found.
public struct CheckResult: Sendable, Equatable {
    /// With its addresses, versions and times updated from the report. Without a report, as it was given.
    public var workhorse: Workhorse
    public var state: WorkhorseState
    /// nil: no report was read (nobody answered, or the answer wasn't a readable report).
    public var status: HostStatus?
    public var probes: ProbeSet
    /// The address that gave the report or, when Locked, the one that refused the key.
    public var answeredAt: String?
    /// Whether this Mac can reach the workhorse's home address. nil: no home address is known.
    public var homeReachable: Bool?
    public var checkedAt: Date

    public init(workhorse: Workhorse, state: WorkhorseState, status: HostStatus?, probes: ProbeSet,
                answeredAt: String?, homeReachable: Bool?, checkedAt: Date) {
        self.workhorse = workhorse
        self.state = state
        self.status = status
        self.probes = probes
        self.answeredAt = answeredAt
        self.homeReachable = homeReachable
        self.checkedAt = checkedAt
    }
}

/// Checks workhorses: the ssh status call at each address, then the state worked out from the answers.
public struct StatusChecker: Sendable {
    /// Every ssh call gets this long. ssh's own connect limit is 5 seconds (`SSHInvocation`).
    static let sshTimeLimit: Duration = .seconds(15)

    private let runner: CommandRunner
    private let paths: Paths
    private let hints: HintsProvider
    private let now: @Sendable () -> Date

    public init(runner: CommandRunner, paths: Paths, hints: HintsProvider,
                now: @escaping @Sendable () -> Date = Date.init) {
        self.runner = runner
        self.paths = paths
        self.hints = hints
        self.now = now
    }

    /// Which address a call went to, for telling the report's source apart.
    private enum Slot { case main, home, local }

    /// The key first: when the key can't be used, no ssh call is made at all (ssh would only warn,
    /// then quietly try the user's own keys). Then the main address, the home address and the local
    /// name, in that order. The check stops at the first address where ssh got through to the
    /// workhorse's shell (`.ok` or `.remoteFailed`), and goes on after any other outcome.
    public func check(_ w: Workhorse) async -> CheckResult {
        let checkedAt = now()
        guard KeyManager(paths: paths, runner: runner).identityState(for: w) == .usable else {
            return CheckResult(workhorse: w, state: .notSetUp(.identityUnusable), status: nil, probes: ProbeSet(),
                               answeredAt: nil, homeReachable: nil, checkedAt: checkedAt)
        }

        var probes = ProbeSet()
        var stoppedAt: (slot: Slot, address: String)?
        var tried: [String] = []
        for (slot, address) in addresses(of: w) {
            if tried.contains(address) { continue }          // the same address twice is one question
            tried.append(address)
            let outcome = await probe(w, address: address, remote: SSHInvocation.hostCommand(["status"]))
            switch slot {
            case .main: probes.main = outcome
            case .home: probes.home = outcome
            case .local: probes.local = outcome
            }
            if Self.gotThrough(outcome) {
                stoppedAt = (slot, address)
                break
            }
        }

        // A report is read only from an `.ok` answer; the parse result goes on whether or not it worked.
        var parsed: Result<HostStatus, HostStatusError>?
        if let stop = stoppedAt, let outcome = outcome(of: probes, slot: stop.slot), case .ok(let text) = outcome {
            parsed = Result { try HostStatus.parse(text) }.mapError { $0 as? HostStatusError ?? .noHeader }
        }
        var report: HostStatus?
        if case .success(let s)? = parsed { report = s }

        // The hints only matter when nothing gave a report (the reason for "Can't reach it", and
        // whether a refusal at a Tailscale address can be the locked screen), so they are asked only then.
        let found = parsed == nil
            ? await hints.hints(for: w)
            : Hints(tailscaleRunning: nil, peerOnline: nil, hasNetwork: true, otherVPN: false, atHome: nil)

        var updated = w
        if let report {
            Self.copy(report, into: &updated, at: checkedAt)
        }
        let state = StateResolver.resolve(workhorse: w, probes: probes, status: parsed, hints: found,
                                          identityUsable: true)
        let answeredAt = stoppedAt?.address ?? (state == .locked ? refusedAddress(probes, w) : nil)
        let homeReachable = await homeReachable(updated, probes: probes, hasReport: report != nil, stoppedAt: stoppedAt)
        return CheckResult(workhorse: updated, state: state, status: report, probes: probes,
                           answeredAt: answeredAt, homeReachable: homeReachable, checkedAt: checkedAt)
    }

    /// All the workhorses at the same time. The results come back in the order given.
    public func checkAll(_ list: [Workhorse]) async -> [CheckResult] {
        await withTaskGroup(of: (Int, CheckResult).self) { group in
            for (i, w) in list.enumerated() {
                group.addTask { (i, await self.check(w)) }
            }
            var results: [(Int, CheckResult)] = []
            for await pair in group { results.append(pair) }
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    // MARK: - Pieces

    /// The addresses in the order they are tried. Empty ones are left out.
    private func addresses(of w: Workhorse) -> [(Slot, String)] {
        var list: [(Slot, String)] = [(.main, w.mainAddress)]
        if let home = w.homeAddress, !home.isEmpty { list.append((.home, home)) }
        if let local = w.localName, !local.isEmpty { list.append((.local, local)) }
        return list
    }

    /// One ssh call, read into an outcome.
    private func probe(_ w: Workhorse, address: String, remote: [String]) async -> ProbeOutcome {
        let argv = SSHInvocation.argv(for: w, address: address, paths: paths, batch: true, tty: false, remote: remote)
        let result = await runner.run(argv[0], Array(argv.dropFirst()), environment: [:], stdin: nil,
                                      timeout: Self.sshTimeLimit)
        return SSHProbe.classify(result)
    }

    /// ssh signed in and the remote command ran, well or badly.
    private static func gotThrough(_ outcome: ProbeOutcome) -> Bool {
        switch outcome {
        case .ok, .remoteFailed: return true
        default: return false
        }
    }

    private func outcome(of probes: ProbeSet, slot: Slot) -> ProbeOutcome? {
        switch slot {
        case .main: return probes.main
        case .home: return probes.home
        case .local: return probes.local
        }
    }

    /// For Locked: the address that turned the key down. One that offers no key sign-in at all comes first.
    private func refusedAddress(_ probes: ProbeSet, _ w: Workhorse) -> String? {
        let named: [(ProbeOutcome?, String?)] = [(probes.main, w.mainAddress), (probes.home, w.homeAddress),
                                                 (probes.local, w.localName)]
        var firstRefusal: String?
        for case (.authDenied(let methods)?, let address?) in named {
            if !methods.contains("publickey") { return address }
            if firstRefusal == nil { firstRefusal = address }
        }
        return firstRefusal
    }

    /// The home-address light. When the report came from the home address or the local name it is
    /// yes. When it came from the main address, one more ssh call to the home address (the remote
    /// command `true`) tests it. With no readable report, the home address's own probe is read, if
    /// it was tried: a workhorse that answers there, even to turn the key down, is reachable.
    private func homeReachable(_ w: Workhorse, probes: ProbeSet, hasReport: Bool,
                               stoppedAt: (slot: Slot, address: String)?) async -> Bool? {
        guard let home = w.homeAddress, !home.isEmpty else { return nil }
        guard hasReport, let stop = stoppedAt else {
            guard let outcome = probes.home else { return nil }
            switch outcome {
            case .ok, .remoteFailed, .authDenied: return true
            default: return false
            }
        }
        if stop.slot != .main || stop.address == home { return true }
        if case .ok = await probe(w, address: home, remote: ["true"]) { return true }
        return false
    }

    /// What a report teaches about the workhorse. Something the report doesn't say keeps its saved value.
    private static func copy(_ report: HostStatus, into w: inout Workhorse, at time: Date) {
        if let v = report.home.address, !v.isEmpty { w.homeAddress = v }
        if let v = report.home.prefix { w.homePrefix = v }
        if let v = report.home.localName, !v.isEmpty { w.localName = v }
        if !report.osVersion.isEmpty { w.osVersion = report.osVersion }
        if !report.arch.isEmpty { w.arch = report.arch }
        w.lastSeen = time
        w.lastKeyAccepted = time
    }
}

extension Workhorse {
    /// Whether the unlock over ssh can work (macOS 26 or later on Apple silicon), by the saved
    /// version and chip. A workhorse not checked yet counts as able.
    public var canUnlockOverSSH: Bool {
        OSSupport.canUnlockOverSSH(osVersion: osVersion, arch: arch)
    }
}

extension WorkhorseStore {
    /// Saves what a check learned: the seven fields a report fills, and nothing else, through
    /// `update(id:)` so a change another process made in between survives. Nothing is saved when
    /// the check produced no report. A workhorse removed during the check is not brought back.
    public func absorb(_ result: CheckResult) throws {
        guard result.status != nil else { return }
        let learned = result.workhorse
        do {
            try update(id: learned.id) { saved in
                saved.homeAddress = learned.homeAddress
                saved.homePrefix = learned.homePrefix
                saved.localName = learned.localName
                saved.osVersion = learned.osVersion
                saved.arch = learned.arch
                saved.lastSeen = learned.lastSeen
                saved.lastKeyAccepted = learned.lastKeyAccepted
            }
        } catch StoreError.notFound {
            return
        }
    }
}
