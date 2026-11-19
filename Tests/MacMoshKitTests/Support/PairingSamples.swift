import Foundation
@testable import MacMoshKit

/// A fresh, empty folder in the system's temporary folder.
func temporaryFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("macmosh-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    return url
}

/// Like `temporaryPaths()`, but with no ssh folder and no key yet, so `ensureIdentity()` has
/// something to create. Never the real `~/.ssh`.
func temporaryPathsWithoutKey() throws -> Paths {
    let root = try temporaryFolder()
    return Paths(supportDir: root.appendingPathComponent("support"), sshDir: root.appendingPathComponent("ssh"))
}

/// A thread-safe box a `@Sendable` closure can write into.
final class Box<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value

    init(_ value: Value) { stored = value }

    var value: Value {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

enum PairingSamples {
    /// A made-up host key in the real ed25519 shape: the length-prefixed name `ssh-ed25519`, then a
    /// length-prefixed 32-byte key whose every byte is `fill`. Not anybody's key.
    static func hostKey(fill: UInt8) -> String {
        var blob = Data([0, 0, 0, 11])
        blob.append(Data("ssh-ed25519".utf8))
        blob.append(Data([0, 0, 0, 32]))
        blob.append(Data(repeating: fill, count: 32))
        return "ssh-ed25519 " + blob.base64EncodedString()
    }

    static let hostKey = hostKey(fill: 1)
    static let otherHostKey = hostKey(fill: 2)
    static let computerName = "Spare MacBook Pro"
}

/// A `Pairing` over a fresh temporary folder with no key in it. `ssh-keyscan` answers with
/// `scannedKey`, the key-works check (`ssh`) answers with `probe`, and `ssh-copy-id` exits with
/// `copyExitCodes` (0 once they run out). Only `ssh-keygen` runs for real, in the temporary folder.
struct PairingFixture {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    let paths: Paths
    let store: WorkhorseStore
    let runner: FakeRunner
    let interactive: FakeInteractive
    let keys: KeyManager
    let ui: ScriptedInteraction
    let pairing: Pairing

    init(answers: [String], scannedKey: String = PairingSamples.hostKey, copyExitCodes: [Int32] = [],
         probe: CommandResult = FakeRunner.ok(PairingSamples.computerName + "\n"),
         onCopy: (@Sendable ([String]) -> Void)? = nil) throws {
        paths = try temporaryPathsWithoutKey()
        store = WorkhorseStore(paths: paths)
        runner = FakeRunner { argv in
            switch argv.first ?? "" {
            case "ssh-keyscan":
                return FakeRunner.ok("# \(argv.last ?? ""):22 SSH-2.0-OpenSSH_10.5\n\(argv.last ?? "") \(scannedKey)\n")
            case "ssh":
                return probe
            default:
                return FakeRunner.failed(127, stderr: "not expected in this test: \(argv.first ?? "")\n")
            }
        }
        interactive = FakeInteractive(exitCodes: copyExitCodes, onRun: onCopy)
        keys = KeyManager(paths: paths, runner: ProcessRunner())
        ui = ScriptedInteraction(answers: answers)
        pairing = Pairing(store: store, paths: paths, runner: runner, interactive: interactive, keys: keys,
                          now: { PairingFixture.now })
    }

    /// The `ssh` calls made so far (the key-works check).
    var sshCalls: [[String]] { runner.calls.map(\.argv).filter { $0.first == "ssh" } }
}
