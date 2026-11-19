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

public enum IdentityError: Error, Equatable {
    /// `ssh-keygen` didn't make the key; the text is the last line it printed.
    case createFailed(String)
    /// The `.pub` file next to the key is missing or isn't a public key.
    case noPublicKey(path: String)
}

extension KeyManager {
    /// Creates MacMosh's own key, `paths.defaultIdentity`, when nothing is there: ed25519, no
    /// passphrase, mode 0600, with the comment `macmosh@<this Mac's name>`. Creates the ssh folder at
    /// mode 0700 when it is missing. **Never overwrites:** if anything exists at the key's path or at
    /// its `.pub` path, even a file that can't be used, it does nothing. It only ever touches
    /// MacMosh's own key, never a key a workhorse's `identityFile` names.
    public func ensureIdentity() async throws {
        let key = paths.defaultIdentity
        let pub = key.appendingPathExtension("pub")
        if Self.somethingIsAt(key.path) || Self.somethingIsAt(pub.path) { return }
        if !Self.somethingIsAt(paths.sshDir.path) {
            try FileManager.default.createDirectory(at: paths.sshDir, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
        }
        // Standard input is /dev/null, so ssh-keygen can't be asked anything; were the file to
        // appear in the meantime, its overwrite question would get no answer and it would stop.
        let comment = Self.keyComment(hostName: ProcessInfo.processInfo.hostName)
        let result = await runner.run("ssh-keygen", ["-q", "-t", "ed25519", "-N", "", "-C", comment, "-f", key.path],
                                      environment: [:], stdin: nil, timeout: .seconds(30))
        guard result.exitCode == 0, !result.timedOut, Self.somethingIsAt(key.path) else {
            let said = result.stderr.split(whereSeparator: \.isNewline).last.map(String.init)
            throw IdentityError.createFailed(said ?? "ssh-keygen exited with code \(result.exitCode)")
        }
        chmod(key.path, 0o600)
    }

    /// The base64 field of `<identity>.pub`: the public key MacMosh installs on the workhorse and,
    /// when it is removed, the line it looks for in `authorized_keys`.
    public func publicKeyBlob(for w: Workhorse) throws -> String {
        let path = identityURL(for: w).path + ".pub"
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            throw IdentityError.noPublicKey(path: path)
        }
        let fields = text.split(whereSeparator: { $0 == " " || $0 == "\t" || $0.isNewline })
        guard fields.count >= 2, let blob = Data(base64Encoded: String(fields[1])), !blob.isEmpty else {
            throw IdentityError.noPublicKey(path: path)
        }
        return String(fields[1])
    }

    /// `macmosh@<name>`: the host name up to its first dot, keeping only ASCII letters, digits
    /// and `-`. `mac` when nothing is left.
    static func keyComment(hostName: String) -> String {
        let first = hostName.prefix { $0 != "." }
        let kept = first.unicodeScalars.filter { $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "-") }
        let name = String(String.UnicodeScalarView(kept))
        return "macmosh@" + (name.isEmpty ? "mac" : name)
    }

    /// True for anything at `path`, a dangling symbolic link included.
    static func somethingIsAt(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0
    }
}
