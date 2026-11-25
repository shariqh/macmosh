import Foundation
import Testing
@testable import MacMoshKit

/// A key press: the character AppKit reads with the modifiers ignored (Shift still applies), then the modifiers.
private func press(_ c: String, command: Bool = true, shift: Bool = false, option: Bool = false,
                   control: Bool = false) -> WindowKeys.Press {
    WindowKeys.Press(character: c, command: command, shift: shift, option: option, control: control)
}

/// The keys the MacMosh window answers in its text fields and for closing (issue #147): which key does what.
@Suite struct WindowKeysTests {
    // MARK: the table

    @Test func eachEditingKeyWithCommandIsItsAction() {
        #expect(WindowKeys.action(for: press("v")) == .paste)
        #expect(WindowKeys.action(for: press("c")) == .copy)
        #expect(WindowKeys.action(for: press("x")) == .cut)
        #expect(WindowKeys.action(for: press("a")) == .selectAll)
        #expect(WindowKeys.action(for: press("z")) == .undo)
        #expect(WindowKeys.action(for: press("w")) == .close)
    }

    /// Shift-Command-Z is Redo, whether AppKit hands over "Z" or "z" with Shift held.
    @Test func shiftCommandZIsRedo() {
        #expect(WindowKeys.action(for: press("Z", shift: true)) == .redo)
        #expect(WindowKeys.action(for: press("z", shift: true)) == .redo)
    }

    /// A capital letter from Caps Lock, with no Shift, is still the plain key.
    @Test func aCapitalWithoutShiftIsThePlainKey() {
        #expect(WindowKeys.action(for: press("V")) == .paste)
        #expect(WindowKeys.action(for: press("Z")) == .undo)
    }

    @Test func withoutCommandNoKeyIsOwned() {
        for c in ["v", "c", "x", "a", "z", "w", "q"] {
            #expect(WindowKeys.action(for: press(c, command: false)) == nil, "\(c)")
            #expect(WindowKeys.action(for: press(c, command: false, shift: true)) == nil, "shift \(c)")
        }
    }

    /// Option or Control with Command is another shortcut (Option-Command-V is Paste and Match Style elsewhere).
    @Test func optionOrControlWithCommandIsNotOwned() {
        for c in ["v", "c", "x", "a", "z", "w"] {
            #expect(WindowKeys.action(for: press(c, option: true)) == nil, "option \(c)")
            #expect(WindowKeys.action(for: press(c, control: true)) == nil, "control \(c)")
        }
    }

    /// Shift turns every key but Z into another shortcut: Shift-Command-V is not Paste.
    @Test func shiftWithAnotherKeyIsNotOwned() {
        for c in ["v", "c", "x", "a", "w"] {
            #expect(WindowKeys.action(for: press(c, shift: true)) == nil, "shift \(c)")
            #expect(WindowKeys.action(for: press(c.uppercased(), shift: true)) == nil, "shift \(c.uppercased())")
        }
    }

    /// Command-Q is not the window's: it keeps doing what it did before (issue #147). Nor are other letters,
    /// Command-H, Command-M, Command-comma or a plain Return.
    @Test func keysItMustNotOwn() {
        for c in ["q", "h", "m", "n", "o", "s", ",", "\r", "", "vv"] {
            #expect(WindowKeys.action(for: press(c)) == nil, "command \(c)")
        }
        #expect(WindowKeys.action(for: press("q", shift: true)) == nil)
        #expect(WindowKeys.action(for: press("q", option: true)) == nil)
    }

    /// The items the app's menu holds, built from the same table: one per action, each with its key, and the
    /// standard action each editing item sends to the first responder.
    @Test func theItemsAreTheTableInTheEditMenusOrder() {
        #expect(WindowKeys.items.map(\.action) == [.undo, .redo, .cut, .copy, .paste, .selectAll, .close])
        #expect(WindowKeys.items.map(\.title) == ["Undo", "Redo", "Cut", "Copy", "Paste", "Select All", "Close"])
        #expect(WindowKeys.items.map(\.selector) == ["undo:", "redo:", "cut:", "copy:", "paste:", "selectAll:",
                                                     "performClose:"])
        #expect(WindowKeys.items.map(\.key.character) == ["z", "z", "x", "c", "v", "a", "w"])
        #expect(WindowKeys.items.map(\.key.shift) == [false, true, false, false, false, false, false])
        // Every item's own key finds that item, so the menu and the table can't disagree.
        for item in WindowKeys.items {
            #expect(WindowKeys.action(for: press(item.key.character, shift: item.key.shift)) == item.action)
        }
        #expect(!WindowKeys.items.contains { $0.key.character == "q" })
    }

    // MARK: Command-W

    /// Command-W closes the main window only when nothing is open on it: with a sheet or a dialog open it closes
    /// nothing (Cancel or Escape closes the sheet), and never while a desk is being made.
    @Test func commandWClosesTheWindowOnlyWithNothingOpenOnIt() {
        #expect(WindowKeys.closes(sheetOpen: false, making: false))
        #expect(!WindowKeys.closes(sheetOpen: true, making: false))
        #expect(!WindowKeys.closes(sheetOpen: true, making: true))
        // A desk being made with its sheet already gone (it closes once the desk is made): still nothing.
        #expect(!WindowKeys.closes(sheetOpen: false, making: true))
    }

    // MARK: the log line

    @Test func theMainMenuLineNamesItsMenusAndKeys() {
        #expect(MenuLog.mainMenu(nil) == "main menu: none")
        #expect(MenuLog.mainMenu([]) == "main menu: empty")
        let menus = [WindowKeys.MenuSummary(title: "MacMosh", keys: ["cmd-q"]),
                     WindowKeys.MenuSummary(title: "Edit", keys: ["cmd-z", "shift-cmd-z", "cmd-v"]),
                     WindowKeys.MenuSummary(title: "", keys: [])]
        #expect(MenuLog.mainMenu(menus) == "main menu: MacMosh[cmd-q] Edit[cmd-z,shift-cmd-z,cmd-v] ?[]")
    }

    @Test func aKeyIsNamedWithItsModifiers() {
        #expect(WindowKeys.keyName("v", command: true, shift: false, option: false, control: false) == "cmd-v")
        #expect(WindowKeys.keyName("Z", command: true, shift: true, option: false, control: false) == "shift-cmd-z")
        #expect(WindowKeys.keyName("h", command: true, shift: false, option: true, control: false) == "opt-cmd-h")
        #expect(WindowKeys.keyName("f", command: true, shift: false, option: false, control: true) == "ctrl-cmd-f")
        #expect(WindowKeys.keyName("", command: false, shift: false, option: false, control: false) == "none")
    }
}
