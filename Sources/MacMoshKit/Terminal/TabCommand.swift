import Foundation

public enum TabCommandError: Error, Equatable {
    /// The text is empty or has a character outside `A-Z a-z 0-9 @ % + = : , . / _ -`.
    case unsafeArgument(String)
}

/// What a terminal tab runs: MacMosh's own path, then its arguments.
///
/// Every element must match `^[A-Za-z0-9@%+=:,./_-]+$`. Workhorse ids, desk names and `user@address`
/// all fit, so the line never needs quoting, whether it goes into an AppleScript argument or a file.
public struct TabCommand: Sendable, Equatable {
    public let argv: [String]

    public init(macmoshPath: String, arguments: [String]) throws {
        let all = [macmoshPath] + arguments
        for element in all where !Self.isSafe(element) {
            throw TabCommandError.unsafeArgument(element)
        }
        self.argv = all
    }

    /// `argv` joined with single spaces.
    public var line: String { argv.joined(separator: " ") }

    /// Checked one scalar at a time, so a trailing newline can't slip through the way it does
    /// with a `$` in a pattern, and look-alike letters outside ASCII are refused.
    static func isSafe(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        return text.unicodeScalars.allSatisfy { scalar in
            switch scalar {
            case "A"..."Z", "a"..."z", "0"..."9": return true
            case "@", "%", "+", "=", ":", ",", ".", "/", "_", "-": return true
            default: return false
            }
        }
    }
}
