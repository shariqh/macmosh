import Foundation

/// What an ssh call's result means.
public enum ProbeOutcome: Sendable, Equatable {
    /// ssh signed in and the remote command exited 0.
    case ok(stdout: String)
    /// The workhorse turned the key down. `methods` are the sign-in methods it offers, in its order.
    case authDenied(methods: [String])
    /// The workhorse offered a key different from the pinned one.
    case hostKeyChanged
    /// No key is pinned for this workhorse in MacMosh's key file.
    case hostKeyUnknown
    case timedOut
    case refused
    case unresolved
    /// ssh gave up for another reason; `detail` is the last line it printed.
    case unreachable(detail: String)
    /// ssh signed in, and the remote command exited with a code other than 0.
    case remoteFailed(exitCode: Int32, stderr: String)
    /// The key on the daily Mac can't be used; `detail` is ssh's line saying why.
    case identityUnusable(detail: String)
}

/// Reads ssh's answer. Only ssh's standard error and exit code count: the remote command's
/// standard output may say anything.
public enum SSHProbe {
    /// Checks the signs in a fixed order and returns the first that matches. A changed key comes
    /// first, so it wins over every other reading; `.ok` needs exit code 0 and none of the signs.
    public static func classify(_ result: CommandResult) -> ProbeOutcome {
        let stderr = result.stderr
        if stderr.contains("REMOTE HOST IDENTIFICATION HAS CHANGED")
            || stderr.contains("has changed and you have requested strict checking") {
            return .hostKeyChanged
        }
        if stderr.contains("host key is known for") {
            return .hostKeyUnknown
        }
        if result.timedOut || stderr.contains("Operation timed out") || stderr.contains("Connection timed out") {
            return .timedOut
        }
        if stderr.contains("Connection refused") {
            return .refused
        }
        if stderr.contains("Could not resolve hostname") {
            return .unresolved
        }
        if let line = lines(of: stderr).last(where: { line in identitySigns.contains { line.contains($0) } }) {
            return .identityUnusable(detail: line)
        }
        if let methods = deniedMethods(in: stderr) {
            return .authDenied(methods: methods)
        }
        switch result.exitCode {
        case 0: return .ok(stdout: result.stdout)
        case 255: return .unreachable(detail: lines(of: stderr).last ?? "")
        default: return .remoteFailed(exitCode: result.exitCode, stderr: stderr)
        }
    }

    private static let identitySigns = ["no such identity", "UNPROTECTED PRIVATE KEY FILE", "bad permissions", "incorrect passphrase"]
    private static let deniedSign = "Permission denied ("

    /// The non-empty lines of `text`, trimmed, whether they end in `\n` or `\r\n`.
    private static func lines(of text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// The names inside the brackets of the last `Permission denied (…)`, which is the line ssh
    /// exited on. Nil when the sign is absent. Spaces and empty names are dropped.
    private static func deniedMethods(in stderr: String) -> [String]? {
        guard let start = stderr.range(of: deniedSign, options: .backwards) else { return nil }
        let rest = stderr[start.upperBound...]
        let inside = rest.prefix { $0 != ")" && !$0.isNewline }
        return inside.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
