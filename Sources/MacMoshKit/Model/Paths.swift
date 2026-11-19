import Foundation

/// Where MacMosh keeps its files on the daily Mac. Tests pass their own folders and never use `standard()`.
public struct Paths: Sendable {
    public var supportDir: URL            // ~/Library/Application Support/MacMosh
    public var sshDir: URL                // ~/.ssh

    public init(supportDir: URL, sshDir: URL) {
        self.supportDir = supportDir
        self.sshDir = sshDir
    }

    public static func standard() -> Paths {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return Paths(
            supportDir: home.appendingPathComponent("Library/Application Support/MacMosh", isDirectory: true),
            sshDir: home.appendingPathComponent(".ssh", isDirectory: true))
    }

    public var workhorsesFile: URL { supportDir.appendingPathComponent("workhorses.json") }
    public var settingsFile: URL { supportDir.appendingPathComponent("settings.json") }
    public var knownHostsFile: URL { supportDir.appendingPathComponent("known_hosts") }
    public var defaultIdentity: URL { sshDir.appendingPathComponent("macmosh_ed25519") }
}
