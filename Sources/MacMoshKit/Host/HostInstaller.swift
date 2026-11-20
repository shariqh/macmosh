import Foundation

/// Why the script or its login agent didn't install. The text is plain words for a person.
public enum HostInstallerError: Error, Equatable {
    /// MacMosh's key can't be used, so no ssh call was made.
    case identityUnusable
    /// The copy of the script failed. `message` is ssh's or the shell's last line.
    case copyFailed(String)
    /// The script is there, but `install-agent` failed.
    case agentFailed(String)
}

/// Puts the built-in workhorse script on a workhorse and loads its login agent (design 7.5, 7.11).
///
/// Sitting 1, item 1 (2026-11-20) showed this works over ssh: `install-agent` loads the agent in the
/// login session, and the agent starts the desk server there with sign-ins working.
public struct HostInstaller: Sendable {
    public enum Decision: Equatable, Sendable { case install, replace, keep, tooNew }

    /// The remote command of the first call: the script arrives on standard input, goes to a new
    /// file, and replaces the old one only once it is complete. `~` is left for the remote shell.
    static let copyCommand = "mkdir -p ~/.macmosh && cat > ~/.macmosh/macmosh-host.new && chmod 755 ~/.macmosh/macmosh-host.new && mv ~/.macmosh/macmosh-host.new ~/.macmosh/macmosh-host"
    /// The remote command of the second call.
    static let agentCommand = SSHInvocation.remoteScript + " install-agent"
    /// Each call is short; ssh's own connect limit is 5 seconds.
    static let timeLimit: Duration = .seconds(30)

    private let runner: CommandRunner
    private let paths: Paths

    public init(runner: CommandRunner, paths: Paths) {
        self.runner = runner
        self.paths = paths
    }

    /// Whether to put the built-in script on a workhorse that has `installed` (nil: none). Versions
    /// are compared number by number, so 0.10.0 is newer than 0.9.0. A newer script on the workhorse
    /// is never replaced by an older one: that is `.tooNew`. An empty version counts as none.
    public static func decide(installed: String?, builtIn: String) -> Decision {
        guard let installed, !installed.isEmpty else { return .install }
        let have = numbers(installed), want = numbers(builtIn)
        let count = max(have.count, want.count)
        for i in 0..<count {
            let a = i < have.count ? have[i] : 0
            let b = i < want.count ? want[i] : 0
            if a < b { return .replace }
            if a > b { return .tooNew }
        }
        return .keep
    }

    /// The numbers of a dotted version. A part that doesn't start with digits counts as 0.
    private static func numbers(_ version: String) -> [Int] {
        version.split(separator: ".", omittingEmptySubsequences: false).map { part in
            Int(part.prefix { $0.isASCII && $0.isNumber }) ?? 0
        }
    }

    /// Two batch ssh calls to `address`: the script, then its login agent. Key first: with MacMosh's
    /// key unusable no ssh runs (ssh would only warn, then quietly try the user's own keys).
    public func install(on w: Workhorse, address: String) async throws {
        guard KeyManager(paths: paths, runner: runner).identityState(for: w) == .usable else {
            throw HostInstallerError.identityUnusable
        }
        let copy = await ssh(w, address, Self.copyCommand, stdin: Data(HostScript.source.utf8))
        guard copy.exitCode == 0, !copy.timedOut else {
            throw HostInstallerError.copyFailed(Self.reason(copy))
        }
        let agent = await ssh(w, address, Self.agentCommand, stdin: nil)
        guard agent.exitCode == 0, !agent.timedOut else {
            throw HostInstallerError.agentFailed(Self.reason(agent))
        }
    }

    private func ssh(_ w: Workhorse, _ address: String, _ remote: String, stdin: Data?) async -> CommandResult {
        let argv = SSHInvocation.argv(for: w, address: address, paths: paths, batch: true, tty: false, remote: [remote])
        return await runner.run(argv[0], Array(argv.dropFirst()), environment: [:], stdin: stdin, timeout: Self.timeLimit)
    }

    /// The last line ssh or the remote shell printed, or the exit code when it printed nothing.
    private static func reason(_ r: CommandResult) -> String {
        if r.timedOut { return "the workhorse didn't answer within \(Int(timeLimit.components.seconds)) seconds" }
        let last = r.stderr.split(whereSeparator: \.isNewline).last.map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        return last.isEmpty ? "exit code \(r.exitCode)" : last
    }
}

extension HostInstallerError {
    /// The error in plain words.
    public var message: String {
        switch self {
        case .identityUnusable: return "MacMosh can't use its ssh key, so nothing was installed."
        case .copyFailed(let why): return "The script couldn't be copied: \(why)."
        case .agentFailed(let why): return "The script is there, but its login agent didn't load: \(why)."
        }
    }
}
