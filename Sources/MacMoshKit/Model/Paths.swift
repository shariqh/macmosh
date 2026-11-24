import Foundation

/// Where MacMosh keeps its files on the daily Mac. Tests pass their own folders and never use `standard()`.
public struct Paths: Sendable {
    public var supportDir: URL            // ~/Library/Application Support/MacMosh
    public var sshDir: URL                // ~/.ssh

    public init(supportDir: URL, sshDir: URL) {
        self.supportDir = supportDir
        self.sshDir = sshDir
    }

    /// The real folders. `MACMOSH_SUPPORT_DIR`, when set and not empty, names the support folder
    /// instead (for trying the command without touching real settings); `~/.ssh` never moves.
    public static func standard() -> Paths {
        forHome(FileManager.default.homeDirectoryForCurrentUser, environment: ProcessInfo.processInfo.environment)
    }

    /// `standard()` for a given home folder and environment, so a test can check it without the real ones.
    static func forHome(_ home: URL, environment: [String: String]) -> Paths {
        let support: URL
        if let named = environment["MACMOSH_SUPPORT_DIR"], !named.isEmpty {
            support = URL(fileURLWithPath: named, isDirectory: true)
        } else {
            support = home.appendingPathComponent("Library/Application Support/MacMosh", isDirectory: true)
        }
        return Paths(supportDir: support, sshDir: home.appendingPathComponent(".ssh", isDirectory: true))
    }

    public var workhorsesFile: URL { supportDir.appendingPathComponent("workhorses.json") }
    public var settingsFile: URL { supportDir.appendingPathComponent("settings.json") }
    public var knownHostsFile: URL { supportDir.appendingPathComponent("known_hosts") }
    /// One record per terminal tab opened with a window option (menu design 8.1).
    public var tabsDir: URL { supportDir.appendingPathComponent("tabs", isDirectory: true) }
    public var defaultIdentity: URL { sshDir.appendingPathComponent("macmosh_ed25519") }
}
