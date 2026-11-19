import Foundation
@testable import MacMoshKit

extension HostStatus {
    /// A Ready report from a laptop: a battery, on power.
    static var sampleLaptop: HostStatus {
        var s = HostStatus.sampleReady
        s.battery = Battery(present: true, onAC: true, percent: 82)
        s.power = Power(sleepOnPower: 0, wakeForNetwork: 1, autoRestart: nil, disableSleep: nil)
        return s
    }

    /// A Ready report from a desktop Mac: no battery, and it sleeps on power.
    static var sampleDesktop: HostStatus {
        var s = HostStatus.sampleReady
        s.battery = Battery(present: false, onAC: nil, percent: nil)
        s.power = Power(sleepOnPower: 10, wakeForNetwork: 0, autoRestart: 0, disableSleep: nil)
        return s
    }
}

/// The public key line a stand-in key file has: the base64 field is what `uninstall` is given.
/// Made-up base64 with its padding, which `Data(base64Encoded:)` needs. (The plan's sample has none, so `publicKeyBlob` refuses it.)
let sampleKeyBlob = "AAAAC3NzaC1lZDI1NTE5AAAAIHk0aW5nZXhhbXBsZWtleWJsb2JleGFtcGxla2V5YmxvYg=="

/// Writes `<identity>.pub` next to the stand-in key `temporaryPaths()` made.
func writePublicKey(blob: String, in paths: Paths) throws {
    let pub = paths.defaultIdentity.appendingPathExtension("pub")
    try Data("ssh-ed25519 \(blob) macmosh@test-mac\n".utf8).write(to: pub)
}

/// A `PowerFlow` over stand-ins: a scripted checker, a fake terminal hand-over that logs into the
/// interaction, and a real store in a temporary folder that holds the workhorse.
struct PowerFixture {
    let paths: Paths
    let store: WorkhorseStore
    let checker: ScriptedChecker
    let interactive: FakeInteractive
    let ui: RecoveryInteraction
    let flow: PowerFlow
    let workhorse: Workhorse

    /// `script` is what the checks say, in order: before the change, and after it.
    init(script: [ScriptedCheck] = [.usual(.ready(signIns: true)), .usual(.ready(signIns: true))],
         answers: [String] = [], sshExitCodes: [Int32] = [], workhorse: Workhorse = .recoverySample()) throws {
        let paths = try temporaryPaths()
        self.paths = paths
        self.workhorse = workhorse
        store = WorkhorseStore(paths: paths)
        try store.upsert(workhorse)
        checker = ScriptedChecker(script)
        let ui = RecoveryInteraction(answers: answers)
        self.ui = ui
        interactive = FakeInteractive(exitCodes: sshExitCodes, onRun: { argv in ui.noteRun(argv) })
        flow = PowerFlow(checker: checker, store: store, paths: paths, interactive: interactive,
                         keys: KeyManager(paths: paths, runner: FakeRunner { _ in FakeRunner.failed(127) }))
    }

    /// A check that finds a desktop Mac, Ready.
    static func desktop() -> ScriptedCheck {
        ScriptedCheck(.ready(signIns: true), status: .sampleDesktop, answeredAt: "workhorse")
    }

    func savedPowerChanges() throws -> [String] {
        try store.find(workhorse.id).powerChanges
    }
}

/// A `Removal` over stand-ins: a scripted checker, a fake ssh, and a real store in a temporary
/// folder that holds the workhorse. The public key file holds `publicKeyBlob`.
struct RemovalFixture {
    let paths: Paths
    let store: WorkhorseStore
    let runner: FakeRunner
    let checker: ScriptedChecker
    let ui: RecoveryInteraction
    let removal: Removal

    init(answers: [String] = [], publicKeyBlob: String = sampleKeyBlob,
         check: ScriptedCheck = .usual(.ready(signIns: true)),
         ssh: CommandResult = FakeRunner.ok(), workhorse: Workhorse = .sample(id: "mbp"),
         writePublicKeyFile: Bool = true, breakTheKey: Bool = false) throws {
        let paths = try temporaryPaths()
        self.paths = paths
        if writePublicKeyFile { try writePublicKey(blob: publicKeyBlob, in: paths) }
        if breakTheKey { chmod(paths.defaultIdentity.path, 0o644) }
        store = WorkhorseStore(paths: paths)
        try store.upsert(workhorse)
        runner = FakeRunner { _ in ssh }
        checker = ScriptedChecker([check])
        ui = RecoveryInteraction(answers: answers)
        removal = Removal(store: store, paths: paths, runner: runner,
                          keys: KeyManager(paths: paths, runner: runner), checker: checker)
    }

    var stillListed: Bool { (try? store.find("mbp")) != nil }
}
