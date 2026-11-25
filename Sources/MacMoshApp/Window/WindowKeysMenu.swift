import AppKit
import MacMoshKit

/// The AppKit side of `WindowKeys` (issue #147). Every rule is in `WindowKeys`, where it is tested; this only
/// reads `NSApp.mainMenu` for the log.
@MainActor enum WindowKeysMenu {
    /// What the main menu holds: nil when there is none. Apple, NSApplication `mainMenu`
    /// (https://developer.apple.com/documentation/appkit/nsapplication/mainmenu): "The app's main menu bar."
    static func summary(_ menu: NSMenu?) -> [WindowKeys.MenuSummary]? {
        guard let menu else { return nil }
        return menu.items.map { top in
            WindowKeys.MenuSummary(title: top.submenu?.title ?? top.title,
                                   keys: (top.submenu?.items ?? []).filter { !$0.keyEquivalent.isEmpty }.map(keyName))
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
    /// Debug builds: one log line with what the main menu holds now, and another a moment later, in case the
    /// menu comes once the app is active.
    static func logMainMenu() {
        MenuLog.write(MenuLog.mainMenu(summary(NSApp.mainMenu)))
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            MenuLog.write(MenuLog.mainMenu(summary(NSApp.mainMenu)))
        }
    }
    #endif
}
