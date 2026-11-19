import Foundation

/// Whether the ssh key MacMosh signs in with can be used.
public enum IdentityState: Sendable, Equatable {
    case usable
    case missing
    case badPermissions
}

/// MacMosh's own ssh key (`~/.ssh/macmosh_ed25519`), or the one a workhorse names instead.
public struct KeyManager: Sendable {
    public let paths: Paths
    let runner: CommandRunner

    public init(paths: Paths, runner: CommandRunner) {
        self.paths = paths
        self.runner = runner
    }

    /// The workhorse's own `identityFile` with a leading `~` expanded, or `paths.defaultIdentity`.
    public func identityURL(for w: Workhorse) -> URL {
        Self.identityURL(for: w, paths: paths)
    }

    /// `usable` when the file is a regular file with mode 0600 or 0400; ssh ignores a private key
    /// that others can read. A symbolic link is followed, as ssh does.
    public func identityState(for w: Workhorse) -> IdentityState {
        var info = stat()
        guard stat(identityURL(for: w).path, &info) == 0 else { return .missing }
        guard info.st_mode & S_IFMT == S_IFREG else { return .badPermissions }
        let mode = info.st_mode & 0o777
        return mode == 0o600 || mode == 0o400 ? .usable : .badPermissions
    }

    /// Shared with `SSHInvocation`, which builds the `-i` option without a runner.
    static func identityURL(for w: Workhorse, paths: Paths) -> URL {
        guard let file = w.identityFile, !file.isEmpty else { return paths.defaultIdentity }
        return URL(fileURLWithPath: (file as NSString).expandingTildeInPath)
    }
}
