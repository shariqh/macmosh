import AppKit
import MacMoshKit

/// The AppKit side of `WindowKeys` (issue #147): a main menu for the app with the standard Edit items and Close,
/// built from `WindowKeys.items`. Every rule is in `WindowKeys`, where it is tested; this only builds the items
/// and asks it.
///
/// Why a menu. Apple's Event Handling Guide, "Handling Key Events" (archived,
/// https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/HandlingKeyEvents/HandlingKeyEvents.html):
/// "If no object in the view hierarchy handles the key equivalent, NSApp then sends performKeyEquivalent: to the
/// menus in the menu bar." Apple, NSMenu `performKeyEquivalent(with:)`
/// (https://developer.apple.com/documentation/appkit/nsmenu/performkeyequivalent(with:)): "Performs the action
/// for the menu item that corresponds to the given key equivalent." On GitHub's macOS 15 and 26 runners (run
/// 45541029198) the app already had a main menu when its window opened, SwiftUI's, with an Edit menu holding
/// Command-Z, Shift-Command-Z, X, C, V and A, yet a posted Command-V left a field empty, and the menu bar on screen
/// was Finder's while MacMosh was the active app. This adds the standard items with the standard actions sent to the
/// first responder, to see whether those reach the field.
///
/// Nothing shows on screen: the app stays an accessory app. Apple, `NSApplication.ActivationPolicy.accessory`
/// (https://developer.apple.com/documentation/appkit/nsapplication/activationpolicy-swift.enum/accessory): "The
/// application doesn't appear in the Dock and doesn't have a menu bar, but it may be activated programmatically
/// or by clicking on one of its windows."
@MainActor final class WindowKeysMenu: NSObject, NSMenuItemValidation {
    static let shared = WindowKeysMenu()

    /// Marks the menus this adds, so it adds them once.
    private static let tag = 147
    /// Whether a desk is being made (`WindowActionRunner.making`); Command-W closes nothing then.
    private var making: () -> Bool = { false }
    private var watching = false

    /// Gives the app its Edit and Close items, once: into the main menu there is, or a new one when there is
    /// none. Called when the window opens and when one of the app's windows becomes key, in case the main menu
    /// was replaced meanwhile.
    func install(making: @escaping () -> Bool) {
        self.making = making
        installIfMissing()
        guard !watching else { return }
        watching = true
        // Apple, NSWindow `didBecomeKeyNotification`
        // (https://developer.apple.com/documentation/appkit/nswindow/didbecomekeynotification).
        NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { WindowKeysMenu.shared.installIfMissing() }
        }
    }

    private func installIfMissing() {
        let main = NSApp.mainMenu ?? NSMenu(title: "Main")
        guard !main.items.contains(where: { $0.tag == Self.tag }) else { return }
        main.addItem(top("Edit", WindowKeys.items.filter { $0.action != .close }.map(editItem)))
        main.addItem(top("File", WindowKeys.items.filter { $0.action == .close }.map(closeItem)))
        if NSApp.mainMenu == nil { NSApp.mainMenu = main }
        #if DEBUG
        MenuLog.write(MenuLog.mainMenu(Self.summary(NSApp.mainMenu)))
        #endif
    }

    private func top(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let menu = NSMenu(title: title)
        items.forEach(menu.addItem)
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        item.tag = Self.tag
        return item
    }

    /// An editing item: its standard action, sent to the first responder (no target), which is the field that
    /// has the keyboard. Apple, NSMenuItem `keyEquivalentModifierMask`
    /// (https://developer.apple.com/documentation/appkit/nsmenuitem/keyequivalentmodifiermask): "a lowercase
    /// character with NSShiftKeyMask is interpreted the same as the uppercase character without that mask."
    private func editItem(_ item: WindowKeys.Item) -> NSMenuItem {
        let menuItem = NSMenuItem(title: item.title, action: NSSelectorFromString(item.selector),
                                  keyEquivalent: item.key.character)
        menuItem.keyEquivalentModifierMask = item.key.shift ? [.command, .shift] : [.command]
        return menuItem
    }

    private func closeItem(_ item: WindowKeys.Item) -> NSMenuItem {
        let menuItem = NSMenuItem(title: item.title, action: #selector(closeWindow(_:)), keyEquivalent: item.key.character)
        menuItem.keyEquivalentModifierMask = [.command]
        menuItem.target = self
        return menuItem
    }

    /// The MacMosh window, when it or a sheet on it has the keyboard.
    private func keyWindow() -> (window: NSWindow, sheetOpen: Bool)? {
        guard let key = NSApp.keyWindow else { return nil }
        if key.title == WindowWords.title { return (key, key.attachedSheet != nil) }
        if let parent = key.sheetParent, parent.title == WindowWords.title { return (parent, true) }
        return nil
    }

    /// Close is on only when `WindowKeys.closes` says so. Off, AppKit does not take Command-W, which goes on as
    /// before. Apple, `validateMenuItem(_:)`
    /// (https://developer.apple.com/documentation/appkit/nsmenuitemvalidation/validatemenuitem(_:)): "true to
    /// enable menuItem, false to disable it."
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard menuItem.action == #selector(closeWindow(_:)) else { return true }
        guard let found = keyWindow() else { return false }
        return WindowKeys.closes(sheetOpen: found.sheetOpen, making: making())
    }

    /// Apple, NSWindow `performClose(_:)` (https://developer.apple.com/documentation/appkit/nswindow/performclose(_:)):
    /// "Simulates the user clicking the close button by momentarily highlighting the button and then closing the
    /// window."
    @objc func closeWindow(_ sender: Any?) {
        guard let found = keyWindow(), WindowKeys.closes(sheetOpen: found.sheetOpen, making: making()) else { return }
        found.window.performClose(sender)
    }

    // MARK: the log

    /// What the main menu holds: nil when there is none. Apple, NSApplication `mainMenu`
    /// (https://developer.apple.com/documentation/appkit/nsapplication/mainmenu): "The app's main menu bar."
    /// Each key is followed by its item's action: `cmd-v>paste:`.
    static func summary(_ menu: NSMenu?) -> [WindowKeys.MenuSummary]? {
        guard let menu else { return nil }
        return menu.items.map { top in
            WindowKeys.MenuSummary(title: top.submenu?.title ?? top.title,
                                   keys: (top.submenu?.items ?? []).filter { !$0.keyEquivalent.isEmpty }.map { item in
                                       keyName(item) + (item.action.map { ">" + NSStringFromSelector($0) } ?? "")
                                   })
        }
    }

    /// An item's key as `WindowKeys.keyName` writes it. A capital letter as the key means Shift is part of it.
    private static func keyName(_ item: NSMenuItem) -> String {
        let mask = item.keyEquivalentModifierMask
        let key = item.keyEquivalent
        let capital = key.count == 1 && key != key.lowercased()
        return WindowKeys.keyName(key, command: mask.contains(.command), shift: mask.contains(.shift) || capital,
                                  option: mask.contains(.option), control: mask.contains(.control))
    }

    #if DEBUG
    /// Debug builds: one log line with what the main menu holds now, before the app's items go in, and another
    /// a moment later, in case the menu changes once the app is active.
    static func logMainMenu() {
        MenuLog.write(MenuLog.mainMenu(summary(NSApp.mainMenu)))
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            MenuLog.write(MenuLog.mainMenu(summary(NSApp.mainMenu)))
        }
    }
    #endif
}
