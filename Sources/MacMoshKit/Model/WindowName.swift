import Foundation

/// A name for one window of a desk (issue 144): the app's copy of the workhorse script's rule (0.11.0,
/// `mm_valid_window_name`), plus one rule of the app's own. The script's rule: 1 to 32 characters, each a
/// letter A-Z or a-z, a digit, a space, `-`, `_` or a full stop, and no space at either end. The app's own:
/// no `-` first, because the script reads `--auto` in the name's place as its switch, so a name is never sent
/// in that place looking like an option. Nothing is trimmed: the name is the text as typed.
/// `WindowNameRuleTests` lists the same names as the script's own tests, and pins the script's rule.
public struct WindowName: Sendable, Equatable {
    public static let maxLength = 32

    /// The rule in one sentence, for the window's help line and the terminal's question.
    public static let rule = "A window name is 1 to 32 letters, digits, spaces, -, _ and full stops. It can't start with a space or -, or end with a space."

    public let value: String

    public init?(_ text: String) {
        guard Self.problem(text) == nil else { return nil }
        value = text
    }

    /// The characters the script lists one by one.
    private static let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 ._-".unicodeScalars)

    /// The script's rule alone, without the app's rule about a leading `-`.
    static func keepsScriptRule(_ text: String) -> Bool {
        let scalars = text.unicodeScalars
        guard !scalars.isEmpty, scalars.count <= maxLength, scalars.allSatisfy(allowed.contains) else { return false }
        return scalars.first != " " && scalars.last != " "
    }

    /// Why `text` can't be a window's name, in one sentence; nil when it can.
    public static func problem(_ text: String) -> String? {
        let scalars = text.unicodeScalars
        if scalars.isEmpty { return "Type a name." }
        if !scalars.allSatisfy(allowed.contains) {
            return "A window name uses letters, digits, spaces, -, _ and full stops only."
        }
        if scalars.count > maxLength { return "A window name is \(maxLength) characters at most." }
        if scalars.first == " " || scalars.last == " " { return "A window name can't start or end with a space." }
        if scalars.first == "-" { return "A window name can't start with -." }
        return nil
    }
}
