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
        if reason.hasSuffix("did not answer in time.") { return "tab did not open (no answer in time)" }
        if let number = errorNumber(in: reason) { return "tab did not open (error \(number))" }
        return "tab did not open"
    }

    private static func name(_ action: MenuAction) -> String {
        switch action {
        case .tab(let arguments): return (["tab"] + arguments.prefix(1)).joined(separator: " ")
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
