import Foundation
@testable import MacMoshKit

/// One thing that happened in front of the person, in order: a line said, a question asked, a
/// wait for a key, or the terminal handed to a program.
enum RecoveryEvent: Equatable {
    case said(String)
    case asked(String)
    case waited
    case ran([String])
}

/// A stand-in `Interaction` like `ScriptedInteraction`, that also keeps one log of everything in
/// the order it happened, so a test can tell a warning came before a question or a password prompt.
final class RecoveryInteraction: Interaction, @unchecked Sendable {
    private let lock = NSLock()
    private var answers: [String]
    private var log: [RecoveryEvent] = []

    init(answers: [String] = []) {
        self.answers = answers
    }

    /// Everything, oldest first.
    var events: [RecoveryEvent] { lock.withLock { log } }
    /// Every line passed to `say`, oldest first.
    var said: [String] { events.compactMap { if case .said(let s) = $0 { return s } else { return nil } } }
    /// Every prompt passed to `ask`, oldest first.
    var asked: [String] { events.compactMap { if case .asked(let s) = $0 { return s } else { return nil } } }
    /// How many times `waitForKey` was called.
    var waits: Int { events.filter { $0 == .waited }.count }

    /// Records that the terminal was handed to `argv`.
    func noteRun(_ argv: [String]) {
        lock.withLock { log.append(.ran(argv)) }
    }

    func say(_ line: String) {
        lock.withLock { log.append(.said(line)) }
    }

    func ask(_ prompt: String) -> String {
        lock.withLock {
            log.append(.asked(prompt))
            return answers.isEmpty ? "" : answers.removeFirst()
        }
    }

    func waitForKey(_ prompt: String) {
        lock.withLock { log.append(.waited) }
    }

    /// The position of the first event that matches, or nil.
    func firstIndex(where match: (RecoveryEvent) -> Bool) -> Int? {
        events.firstIndex(where: match)
    }

    /// The position of the first line said that contains `text`.
    func indexOfSaid(_ text: String) -> Int? {
        firstIndex { if case .said(let s) = $0 { return s.contains(text) } else { return false } }
    }

    /// The position of the first question asked.
    var indexOfFirstQuestion: Int? {
        firstIndex { if case .asked = $0 { return true } else { return false } }
    }

    /// The position of the first time the terminal was handed over.
    var indexOfFirstRun: Int? {
        firstIndex { if case .ran = $0 { return true } else { return false } }
    }
}

/// One scripted answer of a check: the state, the report and the address that answered.
struct ScriptedCheck: Sendable {
    var state: WorkhorseState
    var status: HostStatus?
    var answeredAt: String?
    var probes: ProbeSet

    init(_ state: WorkhorseState, status: HostStatus? = nil, answeredAt: String? = nil, probes: ProbeSet = ProbeSet()) {
        self.state = state
        self.status = status
        self.answeredAt = answeredAt
        self.probes = probes
    }

    /// The usual answer for a state: a report for Ready and Waiting for login, the main address
    /// for a workhorse that answered, the home address (192.168.1.20) for Locked, nothing otherwise.
    static func usual(_ state: WorkhorseState, desks: [String] = []) -> ScriptedCheck {
        switch state {
        case .ready:
            return ScriptedCheck(state, status: .recoveryReady(desks: desks), answeredAt: "workhorse")
        case .waitingForLogin:
            return ScriptedCheck(state, status: .recoveryWaiting, answeredAt: "192.168.1.20")
        case .locked:
            return ScriptedCheck(state, answeredAt: "192.168.1.20",
                                 probes: ProbeSet(main: .timedOut, home: .authDenied(methods: ["password", "keyboard-interactive"])))
        case .notSetUp:
            return ScriptedCheck(state, answeredAt: "workhorse")
        case .cantVerify:
            return ScriptedCheck(state, probes: ProbeSet(main: .hostKeyChanged))
        case .cantReach:
            return ScriptedCheck(state)
        }
    }
}

/// A stand-in `WorkhorseChecking`: answers each check with the next scripted answer, and keeps
/// giving the last one once the list runs out. Runs no ssh. The workhorse in the result is the one asked about.
final class ScriptedChecker: WorkhorseChecking, @unchecked Sendable {
    private let lock = NSLock()
    private var script: [ScriptedCheck]
    private var count = 0

    init(_ script: [ScriptedCheck]) {
        precondition(!script.isEmpty, "a scripted checker needs at least one answer")
        self.script = script
    }

    /// How many checks were made.
    var checks: Int { lock.withLock { count } }

    func check(_ w: Workhorse) async -> CheckResult {
        let next: ScriptedCheck = lock.withLock {
            count += 1
            return script.count > 1 ? script.removeFirst() : script[0]
        }
        return CheckResult(workhorse: w, state: next.state, status: next.status, probes: next.probes,
                           answeredAt: next.answeredAt, homeReachable: nil,
                           checkedAt: Date(timeIntervalSince1970: 1_800_000_000))
    }
}

/// A `Recovery` with stand-ins for everything: a scripted checker, a fake terminal hand-over that
/// logs into the interaction, and a sleep that returns at once and records how long it was asked for.
struct RecoveryFixture {
    let paths: Paths
    let checker: ScriptedChecker
    let interactive: FakeInteractive
    let ui: RecoveryInteraction
    let sleeps: Box<[Duration]>
    let recovery: Recovery

    init(state: WorkhorseState, answers: [String] = [], desks: [String] = [], paths: Paths = .test,
         sshExitCodes: [Int32] = []) {
        self.init(script: [.usual(state, desks: desks)], answers: answers, paths: paths, sshExitCodes: sshExitCodes)
    }

    init(script: [ScriptedCheck], answers: [String] = [], paths: Paths = .test, sshExitCodes: [Int32] = []) {
        self.init(checker: ScriptedChecker(script), answers: answers, paths: paths, sshExitCodes: sshExitCodes)
    }

    init(checker scripted: ScriptedChecker, answers: [String] = [], paths: Paths = .test, sshExitCodes: [Int32] = []) {
        self.paths = paths
        checker = scripted
        let ui = RecoveryInteraction(answers: answers)
        self.ui = ui
        interactive = FakeInteractive(exitCodes: sshExitCodes, onRun: { argv in ui.noteRun(argv) })
        let sleeps = Box<[Duration]>([])
        self.sleeps = sleeps
        recovery = Recovery(checker: scripted, paths: paths, interactive: interactive,
                            sleep: { d in sleeps.value.append(d) })
    }
}

/// A `Recovery` whose checker is the real `StatusChecker` over a `FakeRunner`, for the tests that
/// start from what ssh says at each address.
struct RealCheckRecovery {
    let runner: FakeRunner
    let interactive: FakeInteractive
    let ui: RecoveryInteraction
    let recovery: Recovery

    init(_ runner: FakeRunner, paths: Paths = .test, hints: Hints = .allFine) {
        self.runner = runner
        let ui = RecoveryInteraction()
        self.ui = ui
        interactive = FakeInteractive(onRun: { argv in ui.noteRun(argv) })
        let checker = StatusChecker(runner: runner, paths: paths, hints: FixedHints(hints))
        recovery = Recovery(checker: checker, paths: paths, interactive: interactive, sleep: { _ in })
    }
}

extension HostStatus {
    /// A Ready report with these desks open, FileVault on and authrestart supported, from macOS 27.3 on arm64.
    static func recoveryReady(desks: [String] = [], fileVault: Tri = .yes, authRestart: Tri = .yes) -> HostStatus {
        var s = HostStatus.sampleReady
        s.fileVault = fileVault
        s.authRestart = authRestart
        s.desks = desks.compactMap { DeskName($0) }.map { HostStatus.Desk(name: $0, windows: [], windowCount: 1, attached: 0) }
        return s
    }

    /// A report with nobody logged in at the screen.
    static var recoveryWaiting: HostStatus {
        var s = HostStatus.recoveryReady()
        s.consoleUser = nil
        s.serverUp = false
        s.signIns = .unknown
        return s
    }
}

extension Workhorse {
    /// The workhorse the recovery tests use: main address `workhorse`, home address 192.168.1.20,
    /// local name `workhorse.local`, macOS 27.3 on Apple silicon.
    static func recoverySample(osVersion: String? = "27.3", arch: String? = "arm64") -> Workhorse {
        .sample(id: "mbp", name: "MacBook Pro", user: "alex", mainAddress: "workhorse", homeAddress: "192.168.1.20",
                homePrefix: 24, localName: "workhorse.local", osVersion: osVersion, arch: arch,
                lastSeen: Date(timeIntervalSince1970: 1_799_000_000),
                lastKeyAccepted: Date(timeIntervalSince1970: 1_799_000_000))
    }
}
