import Foundation

/// Quotes text so a POSIX shell reads it back exactly as written.
public enum ShellQuote {
    /// Text made only of letters, digits and `@%+=:,./-` stays bare; anything else goes
    /// in single quotes, with each `'` written as `'\''`. Empty text becomes `''`.
    public static func posix(_ s: String) -> String {
        if s.isEmpty { return "''" }
        if s.unicodeScalars.allSatisfy(isBare) { return s }
        return "'" + s.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    /// Each argument quoted by `posix`, separated by single spaces.
    public static func join(_ argv: [String]) -> String {
        argv.map(posix).joined(separator: " ")
    }

    private static func isBare(_ c: Unicode.Scalar) -> Bool {
        switch c {
        case "a"..."z", "A"..."Z", "0"..."9": true
        case "@", "%", "+", "=", ":", ",", ".", "/", "-": true
        default: false
        }
    }
}
