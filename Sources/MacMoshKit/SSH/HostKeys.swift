import CryptoKit
import Foundation

public enum HostKeyError: Error, Equatable {
    /// Nothing at the address answered with a key (or the address could not be used at all).
    case noKey(address: String)
    /// Something answered, but not with an ed25519 key MacMosh can read.
    case malformed
}

/// Reading a workhorse's host key and showing its fingerprint.
///
/// **What establishes trust.** `scan` asks whatever answers at the address for its key, over a
/// network nobody has vouched for, so the key it returns proves nothing by itself. It is pinned
/// only so that every later ssh call can insist on that same key. Trust comes from the person
/// comparing the fingerprint MacMosh shows with what `compareCommand` prints at the workhorse,
/// before MacMosh's own key is installed there. MacMosh never takes a key from anywhere but that
/// one `ssh-keyscan` call, and never replaces a pinned key (`Pairing.add`).
public enum HostKeys {
    /// What the person runs at the workhorse to see its fingerprint.
    public static let compareCommand = "ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub"

    /// `ssh-keyscan` waits up to 5 seconds itself; this is the outer limit.
    static let scanTimeLimit: Duration = .seconds(10)

    /// Runs `ssh-keyscan -T 5 -t ed25519 [-p <port>] <address>` and returns `"ssh-ed25519 <base64>"`
    /// from the first line that isn't a comment. That line must name the type `ssh-ed25519` and carry
    /// a key that decodes as one; anything else throws `.malformed`. No key line throws `.noKey`.
    /// An empty address, one with spaces or one beginning with `-` (which `ssh-keyscan` would read
    /// as an option) throws `.noKey` without running anything.
    public static func scan(address: String, port: Int? = nil, runner: CommandRunner) async throws -> String {
        guard !address.isEmpty, !address.hasPrefix("-"),
              !address.contains(where: { $0.isWhitespace || $0.isNewline }) else {
            throw HostKeyError.noKey(address: address)
        }
        var arguments = ["-T", "5", "-t", "ed25519"]
        if let port {
            guard (1...65535).contains(port) else { throw HostKeyError.noKey(address: address) }
            arguments += ["-p", String(port)]
        }
        arguments.append(address)
        let result = await runner.run("ssh-keyscan", arguments, environment: [:], stdin: nil, timeout: scanTimeLimit)

        let lines = result.stdout.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        guard let line = lines.first else { throw HostKeyError.noKey(address: address) }
        // <host> <type> <base64 key>
        let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard fields.count >= 3, fields[1] == "ssh-ed25519", isEd25519(blob: String(fields[2])) else {
            throw HostKeyError.malformed
        }
        return "ssh-ed25519 " + fields[2]
    }

    /// The key's fingerprint as `ssh-keygen -lf` prints it: `SHA256:` and the base64 of the SHA-256
    /// of the decoded key, without padding. `hostKey` is `"<type> <base64>"`, as pinned.
    public static func fingerprint(of hostKey: String) throws -> String {
        let fields = hostKey.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard fields.count >= 2, let blob = Data(base64Encoded: String(fields[1])), !blob.isEmpty else {
            throw HostKeyError.malformed
        }
        var text = Data(SHA256.hash(data: blob)).base64EncodedString()
        while text.hasSuffix("=") { text.removeLast() }
        return "SHA256:" + text
    }

    /// The first two fields of a key line, for comparing two keys whatever their spacing or comment.
    static func normalized(_ hostKey: String) -> String {
        hostKey.split(whereSeparator: { $0 == " " || $0 == "\t" }).prefix(2).joined(separator: " ")
    }

    /// An ssh public-key blob for ed25519: the length-prefixed name `ssh-ed25519`, then a
    /// length-prefixed 32-byte key, and nothing after.
    static func isEd25519(blob base64: String) -> Bool {
        guard let blob = Data(base64Encoded: base64) else { return false }
        let bytes = [UInt8](blob)
        let name = Array("ssh-ed25519".utf8)
        let expected: [UInt8] = [0, 0, 0, UInt8(name.count)] + name + [0, 0, 0, 32]
        return bytes.count == expected.count + 32 && Array(bytes.prefix(expected.count)) == expected
    }
}
