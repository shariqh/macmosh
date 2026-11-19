import Foundation
@testable import MacMoshKit

/// What a stand-in private key file holds. Made-up text, not a key.
private let standInKey = """
-----BEGIN STAND-IN KEY (made up for tests, not a real key)-----
bWFjbW9zaC10ZXN0LXN0YW5kLWluLW5vdC1hLXJlYWwta2V5
-----END STAND-IN KEY-----

"""

/// A fresh folder in the system's temporary folder. `Paths.supportDir` is not created yet
/// (the store makes it); `sshDir` exists and holds a stand-in `macmosh_ed25519` with mode 0600.
/// Tests never touch the real `~/.ssh` or the real Application Support folder.
func temporaryPaths(withSpaceInPath: Bool = false) throws -> Paths {
    let fm = FileManager.default
    var root = fm.temporaryDirectory.appendingPathComponent("macmosh-test-\(UUID().uuidString)")
    if withSpaceInPath { root = root.appendingPathComponent("Application Support") }
    let ssh = root.appendingPathComponent("ssh")
    try fm.createDirectory(at: ssh, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let key = ssh.appendingPathComponent("macmosh_ed25519")
    try Data(standInKey.utf8).write(to: key)
    try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: key.path)
    return Paths(supportDir: root.appendingPathComponent("support"), sshDir: ssh)
}

extension Paths {
    /// Made once per test run. Tests that write use `temporaryPaths()` instead.
    static let test: Paths = {
        do { return try temporaryPaths() } catch { fatalError("could not make Paths.test: \(error)") }
    }()
}

extension Workhorse {
    /// Every field is optional so a test names only the ones it cares about.
    static func sample(
        id: String = "mbp",
        name: String = "MacBook Pro",
        user: String = "alex",
        mainAddress: String = "workhorse",
        homeAddress: String? = nil,
        homePrefix: Int? = nil,
        localName: String? = nil,
        hostKey: String = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMadeUpKeyForTestsOnly",
        paired: Bool = true,
        mode: ConnectionMode = .mosh,
        prediction: Prediction = .adaptive,
        projectsFolder: String? = nil,
        identityFile: String? = nil,
        osVersion: String? = nil,
        arch: String? = nil,
        lastSeen: Date? = nil,
        lastKeyAccepted: Date? = nil,
        powerChanges: [String] = []
    ) -> Workhorse {
        Workhorse(id: id, name: name, user: user, mainAddress: mainAddress, homeAddress: homeAddress,
                  homePrefix: homePrefix, localName: localName, hostKey: hostKey, paired: paired,
                  mode: mode, prediction: prediction, projectsFolder: projectsFolder,
                  identityFile: identityFile, osVersion: osVersion, arch: arch, lastSeen: lastSeen,
                  lastKeyAccepted: lastKeyAccepted, powerChanges: powerChanges)
    }
}

/// The repository's root folder, worked out from this file's own path.
func repoRoot(file: String = #filePath) -> URL {
    URL(fileURLWithPath: file)
        .deletingLastPathComponent()   // Support
        .deletingLastPathComponent()   // MacMoshKitTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // the repository
}

/// Reads `Tests/MacMoshKitTests/Fixtures/<name>` from the source tree.
func fixture(_ name: String, file: String = #filePath) throws -> String {
    let url = repoRoot(file: file).appendingPathComponent("Tests/MacMoshKitTests/Fixtures/\(name)")
    return try String(contentsOf: url, encoding: .utf8)
}
