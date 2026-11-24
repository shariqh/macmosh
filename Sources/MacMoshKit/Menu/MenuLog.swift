import Foundation
import os

/// What the menu-bar app did, written to the Mac's system log so that a problem can be read
/// afterwards without a screenshot. To read the last hour on that Mac:
///
///     /usr/bin/log show --last 1h --predicate 'subsystem == "io.github.shariqh.macmosh"'
///
/// Every line is fixed words and numbers. A workhorse's name, address and user never go in, and
/// neither do the sentences the menu shows, because a failed command's last line can name the
/// workhorse. Of a menu action only the subcommand is kept (`connect`, not the desk).
public enum MenuLog {
    public static let subsystem = MacMoshInfo.bundleID
    private static let logger = Logger(subsystem: subsystem, category: "menu")

    /// Writes one line. It is marked public, which is safe because of the rule above.
    public static func write(_ line: String) {
        logger.log("\(line, privacy: .public)")
    }

    static let opened = "menu opened"
    static let listUnreadable = "menu refreshed: the saved list can't be read"

    /// The app's first line, so one run can be told from the next.
    public static func started(version: String) -> String {
        "MacMosh \(version) started"
    }

    /// `menu refreshed: symbol=plus.circle workhorses=0 lines=2`
    static func refreshed(_ menu: MenuLines, workhorses: Int) -> String {
        "menu refreshed: symbol=\(menu.symbol) workhorses=\(workhorses) lines=\(menu.items.count)"
    }

    /// `menu tracking: object=other`: which menu AppKit says began tracking. The app opens the
    /// menu-bar menu on every such notice, and once it has a window a pop-up in it would send one
    /// too; this line shows which object came, so the two can be told apart (main window design 7.3).
    public static func tracking(_ object: MenuTrackingObject) -> String {
        "menu tracking: object=\(object.rawValue)"
    }

    /// When a change was held back: the menu was open, or had just closed and the moment after the
    /// close had not passed yet (`HoldStill.Phase.closing`).
    enum HeldWhen: String {
        case open = "open with a submenu"
        case closing = "closing with a submenu"
    }

    /// The menu on screen had a submenu, and a different menu or notice was held back (`HoldStill`):
    /// `menu held a change: open with a submenu` or `menu held a change: closing with a submenu`.
    static func held(_ when: HeldWhen) -> String {
        "menu held a change: \(when.rawValue)"
    }

    /// When a held menu was shown: the moment after the menu closed had passed, or it began to open
    /// again (with no close heard, or before that moment had passed).
    enum HeldShown: String { case closed, opened }

    /// `menu showed the held change: closed`
    static func heldShown(_ when: HeldShown) -> String {
        "menu showed the held change: \(when.rawValue)"
    }

    /// `menu action: tab connect`
    static func asked(_ action: MenuAction) -> String {
        "menu action: \(name(action))"
    }

    /// `menu action done: tab connect: tab opened`
    static func finished(_ action: MenuAction, summary: String) -> String {
        "menu action done: \(name(action)): \(summary)"
    }

    /// A tab that didn't open, in fixed words. The reason is the terminal app's own text and can
    /// carry the command line, so only what it ends with is kept: AppleScript's error number.
    static func tabFailure(_ reason: String) -> String {
        failure("tab did not open", reason)
    }

    /// A tab that couldn't be brought forward, in fixed words, as `tabFailure` does.
    static func selectFailure(_ reason: String) -> String {
        failure("tab not selected", reason)
    }

    private static func failure(_ words: String, _ reason: String) -> String {
        if reason.hasSuffix("did not answer in time.") { return "\(words) (no answer in time)" }
        if let number = errorNumber(in: reason) { return "\(words) (error \(number))" }
        return words
    }

    /// A focus action that found its tab and brought it forward.
    static let tabSelected = "tab selected"

    /// Why a focus action counted its tab as gone.
    enum TabGone: String {
        case noRecord = "no record"
        case processEnded = "process ended"
        case noDevice = "no terminal device"
        case notInTerminal = "not in the terminal"
    }

    /// `tab gone (no record), opened a new one`: `then` says what came of the new tab.
    static func tabGone(_ why: TabGone, then: String) -> String {
        "tab gone (\(why.rawValue)), \(then)"
    }

    /// `tab records cleared: 2`: how many tab records the refresher removed after good reports.
    static func recordsCleared(_ count: Int) -> String {
        "tab records cleared: \(count)"
    }

    /// `tabs opened: 3`, or `tabs opened: 3 (another way: 1)` when some were opened with a command file.
    static func tabsOpened(_ count: Int, anotherWay: Int) -> String {
        anotherWay == 0 ? "tabs opened: \(count)" : "tabs opened: \(count) (another way: \(anotherWay))"
    }

    /// `tabs opened: 1 of 3, then tab did not open (error -1728)`: `then` is the failed tab's own summary.
    static func tabsStopped(opened: Int, of total: Int, then failure: String) -> String {
        "tabs opened: \(opened) of \(total), then \(failure)"
    }

    private static func name(_ action: MenuAction) -> String {
        switch action {
        case .tab(let arguments): return (["tab"] + arguments.prefix(1)).joined(separator: " ")
        case .tabs(let list): return (["tabs"] + (list.first ?? []).prefix(1)).joined(separator: " ")
        // Never the label: it is a word that names one tab.
        case .focus(_, let orOpen): return (["focus"] + orOpen.prefix(1)).joined(separator: " ")
        case .run(let arguments): return (["run"] + arguments.prefix(1)).joined(separator: " ")
        case .refresh: return "refresh"
        case .none: return "none"
        }
    }

    /// The number in a trailing `(-1719)`, the way osascript ends an error.
    private static func errorNumber(in reason: String) -> Int? {
        let text = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasSuffix(")"), let open = text.lastIndex(of: "(") else { return nil }
        return Int(text[text.index(after: open)..<text.index(before: text.endIndex)])
    }
}

/// The menu a `NSMenu.didBeginTrackingNotification` was sent for, in four fixed words, never a title.
/// Today only sameness with `NSApp.mainMenu` is used; `statusMenu` and `popUp` are picked once a real
/// Mac has shown how to tell them apart (main window design, step 3). Apple says the
/// object is "the main menu bar (`[NSApp mainMenu]`) or the root menu of a popup button"; how the
/// menu-bar item's own menu shows up is read on a real Mac later, and until then it is `other`.
public enum MenuTrackingObject: String, Sendable, CaseIterable {
    case mainMenu, statusMenu, popUp, other

    /// `mainMenu` when the notice's object is the app's main menu bar itself (the same object, not
    /// one with the same title), and `other` for anything else, a missing object included.
    public static func of(_ object: AnyObject?, mainMenu: AnyObject?) -> MenuTrackingObject {
        guard let object, let mainMenu, object === mainMenu else { return .other }
        return .mainMenu
    }
}
