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

/// What a new desk's first window is called (issue 163, script 0.12.0 `desk-new --window-name`). The window's New
/// desk form and the terminal's New desk questions both make one; Start again never does.
public enum FirstWindow: Sendable, Equatable {
    /// Nothing is sent, and tmux names the window after the program running in it, as before.
    case afterItsProgram
    /// The desk's own name.
    case deskName
    /// A name of its own, as typed.
    case named(String)

    /// Why `text` can't name the first window of the desk called `desk`, or nil when it can. The desk's own name always
    /// can, however long: a desk name can be 64 characters and a window name 32, so the script takes a desk's own name
    /// whole, and a desk name holds only characters a window name allows. Anything else keeps `WindowName`'s rule.
    public static func problem(_ text: String, desk: String) -> String? {
        text == desk ? nil : WindowName.problem(text)
    }

    /// What `desk-new --window-name` gets for this desk, or nil when nothing is sent.
    public func name(for desk: DeskName) -> String? {
        switch self {
        case .afterItsProgram: return nil
        case .deskName: return desk.value
        case .named(let text): return text
        }
    }
}
