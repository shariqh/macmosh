import Foundation

/// The keys the MacMosh window answers itself (issue #147): Command-V, C, X, A, Z and Shift-Command-Z in its text
/// fields, and Command-W to close it. The app has no Dock icon and no menu bar of its own, and on GitHub's
/// runners a posted Command-V left a text field empty although typed keys reached it, even with an Edit menu in the
/// app's main menu (main window design, "Changes since approval", item 7). This is the rule; the app's key monitor
/// (`WindowKeysMonitor`) reads each press, asks `action(for:)` and `closes(sheetOpen:making:)`, and sends the item's
/// standard action to the first responder.
///
/// Command-Q is not one of them: it keeps doing what it did before.
public enum WindowKeys {
    public enum Action: String, Sendable, CaseIterable {
        case undo, redo, cut, copy, paste, selectAll, close
    }

    /// A key, always with Command: its character in lower case, and whether Shift is part of it.
    public struct Key: Sendable, Equatable {
        public let character: String
        public let shift: Bool
    }

    /// One of the window's keys: what it does, the title an Edit menu gives it, its key, and the standard action it
    /// sends to the first responder (the field that has the keyboard). Close's action is the window's own
    /// `performClose:`, which the app sends to the MacMosh window itself, and only when `closes` says so.
    public struct Item: Sendable, Equatable {
        public let action: Action
        public let title: String
        public let key: Key
        /// The Objective-C selector's name, as `NSSelectorFromString` takes it.
        public let selector: String
    }

    /// In the order of a Mac's Edit menu, then Close.
    public static let items: [Item] = [
        Item(action: .undo, title: "Undo", key: Key(character: "z", shift: false), selector: "undo:"),
        Item(action: .redo, title: "Redo", key: Key(character: "z", shift: true), selector: "redo:"),
        Item(action: .cut, title: "Cut", key: Key(character: "x", shift: false), selector: "cut:"),
        Item(action: .copy, title: "Copy", key: Key(character: "c", shift: false), selector: "copy:"),
        Item(action: .paste, title: "Paste", key: Key(character: "v", shift: false), selector: "paste:"),
        Item(action: .selectAll, title: "Select All", key: Key(character: "a", shift: false), selector: "selectAll:"),
        Item(action: .close, title: "Close", key: Key(character: "w", shift: false), selector: "performClose:"),
    ]

    /// A key press as AppKit reports it: the character with the modifiers ignored except Shift
    /// (`charactersIgnoringModifiers`), and which modifiers were held.
    public struct Press: Sendable, Equatable {
        public var character: String
        public var command: Bool
        public var shift: Bool
        public var option: Bool
        public var control: Bool

        public init(character: String, command: Bool, shift: Bool, option: Bool, control: Bool) {
            self.character = character
            self.command = command
            self.shift = shift
            self.option = option
            self.control = control
        }
    }

    /// What a press asks of the window, or nil when it is not one of its keys, which then goes on as before:
    /// Command must be held, Option and Control must not, and Shift must be as the key has it.
    public static func action(for press: Press) -> Action? {
        guard press.command, !press.option, !press.control, press.character.count == 1 else { return nil }
        let character = press.character.lowercased()
        return items.first { $0.key.character == character && $0.key.shift == press.shift }?.action
    }

    /// Whether Command-W closes the main window now: only when no sheet or dialog is open on it and no desk is
    /// being made. With a form open it closes nothing, neither the form (whose Cancel and Escape do that, and
    /// lose what was typed only when asked) nor the window under it.
    public static func closes(sheetOpen: Bool, making: Bool) -> Bool {
        !sheetOpen && !making
    }

    // MARK: what the app's main menu holds, for the log

    /// One top-level menu of the app's main menu: its title and its items' keys (`keyName`).
    public struct MenuSummary: Sendable, Equatable {
        public let title: String
        public let keys: [String]

        public init(title: String, keys: [String]) {
            self.title = title
            self.keys = keys
        }
    }

    /// `cmd-v`, `shift-cmd-z`, `opt-cmd-h`; `none` for an item with no key.
    public static func keyName(_ character: String, command: Bool, shift: Bool, option: Bool, control: Bool) -> String {
        guard !character.isEmpty else { return "none" }
        var parts: [String] = []
        if control { parts.append("ctrl") }
        if option { parts.append("opt") }
        if shift { parts.append("shift") }
        if command { parts.append("cmd") }
        return (parts + [character.lowercased()]).joined(separator: "-")
    }
}

extension MenuLog {
    /// `main menu: none`, or `main menu: MacMosh[cmd-q] Edit[cmd-z,shift-cmd-z]`: what `NSApp.mainMenu` holds,
    /// its top-level titles (the app's own and AppKit's fixed words) and their items' keys. Debug builds write it
    /// when the window opens (issue #147).
    public static func mainMenu(_ menus: [WindowKeys.MenuSummary]?) -> String {
        guard let menus else { return "main menu: none" }
        if menus.isEmpty { return "main menu: empty" }
        return "main menu: " + menus.map { "\($0.title.isEmpty ? "?" : $0.title)[\($0.keys.joined(separator: ","))]" }
            .joined(separator: " ")
    }
}
