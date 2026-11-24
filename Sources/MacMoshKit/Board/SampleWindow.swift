// Debug builds only, like `SampleMenu`. A release build has none of this, and `scripts/build-app.sh`
// checks that the release app does not even contain the sample variable's name.
#if DEBUG
import Foundation
import os

/// The samples CI opens the MacMosh window on that the menu's samples don't cover (main window design,
/// section 8, step 3). Kept apart from `SampleMenu`, whose file another branch changes. Every name in
/// here is made up.
public enum SampleWindow: String, CaseIterable, Sendable {
    /// The six-desk workhorse of `SampleMenu.sixDesks`, Ready at the first check and Locked after a
    /// restart from the second on, so the window shows the greyed list of its last Ready check.
    case readyThenLocked = "ready-then-locked"
    /// A Ready workhorse with two desks: `website-redesign`, made by MacMosh in a long folder, kept when
    /// it exits and not brought back after a restart, and `notes`, made by hand. Their second lines carry
    /// every unusual fact, whatever the folder's length.
    case longFolder = "long-folder"
    /// A saved list that can't be read: the menu shows the store's sentence, and so does the window, in
    /// place of the Add a Mac page.
    case unreadableList = "unreadable-list"

    var workhorses: [Workhorse] { self == .unreadableList ? [] : [SampleMenu.main] }

    /// Reads the sample's saved list. The unreadable one throws what a damaged file throws.
    func load() throws -> [Workhorse] {
        if self == .unreadableList { throw StoreError.unreadable("workhorses.json: not JSON") }
        return workhorses
    }

    /// What the `check`-th check finds (counting from 0).
    func gathered(check: Int) -> [Gathered] {
        switch self {
        case .readyThenLocked:
            if check == 0 {
                return [.checked(SampleMenu.result(SampleMenu.main, .ready(signIns: true),
                                                   report: SampleMenu.report(change: nil), home: true))]
            }
            return [.checked(SampleMenu.result(SampleMenu.main, .locked, report: nil, home: nil))]
        case .longFolder:
            return [.checked(SampleMenu.result(SampleMenu.main, .ready(signIns: true), report: Self.longFolderReport,
                                               home: true))]
        case .unreadableList:
            return []
        }
    }

    /// A workhorse script 0.8.0 report with the two desks of `longFolder`. The `def` fields are the
    /// name, reopen, keep, permanent and the folder.
    static let longFolderReport = [
        "macmosh-host\t1\t0.8.0", "os\t26.1\tarm64", "console\tsample", "server\tup", "signins\tok",
        "agent\tinstalled", "power\tsleep=0\twomp=1", "battery\tpresent\tac\t82",
        "desk\twebsite-redesign\t1\t1", "window\twebsite-redesign\t0\tzsh",
        "desk\tnotes\t1\t0", "window\tnotes\t0\tzsh",
        "def\twebsite-redesign\t0\t0\t1\t/Users/sample/Development/clients/acme/website-redesign",
        "end",
    ].joined(separator: "\n") + "\n"

    /// The real refresher, with the saved list and the checks replaced.
    @MainActor public func refresher() -> MenuRefresher {
        let sample = self
        let checks = OSAllocatedUnfairLock(initialState: 0)
        return MenuRefresher(
            load: { try sample.load() },
            gather: { _ in
                let check = checks.withLock { n -> Int in
                    defer { n += 1 }
                    return n
                }
                return sample.gathered(check: check)
            },
            save: { _ in })
    }
}

/// What the app uses when it starts with a sample (`MACMOSH_SAMPLE_MENU`), the menu's or the window's:
/// the refresher, the actions that open and run nothing, the saved list the window reads, and the
/// app's first line about it.
@MainActor public struct SampleRun {
    public let startedLine: String
    public let workhorses: [Workhorse]
    /// Reads the sample's saved list, for the window: the workhorses, or the error of an unreadable one.
    public let load: @Sendable () throws -> [Workhorse]
    public let refresher: MenuRefresher
    public let actions: MenuActionRunner

    /// The sample with that name, or nil when there is none.
    public static func named(_ name: String) -> SampleRun? {
        if let menu = SampleMenu(rawValue: name) {
            let list = menu.workhorses
            return SampleRun(startedLine: menu.startedLine, workhorses: list, load: { list },
                             refresher: menu.refresher(), actions: SampleMenu.actions)
        }
        if let window = SampleWindow(rawValue: name) {
            return SampleRun(startedLine: "sample menu: \(window.rawValue)", workhorses: window.workhorses,
                             load: { try window.load() }, refresher: window.refresher(), actions: SampleMenu.actions)
        }
        return nil
    }

    /// A window button ran this action: `sample window ran: tab connect workhorse api`. Written only when a
    /// sample is shown; the words hold only the sample's made-up names.
    public nonisolated static func windowRan(_ action: MenuAction) {
        if SampleMenu.requested != nil { MenuLog.write(ranLine(action)) }
    }

    nonisolated static func ranLine(_ action: MenuAction) -> String {
        let kind: String
        switch action {
        case .tab: kind = "tab"
        case .tabs: kind = "tabs"
        case .focus: kind = "focus"
        case .run: kind = "run"
        case .refresh: kind = "refresh"
        case .none: kind = "none"
        }
        return (["sample window ran:", kind] + action.words).joined(separator: " ")
    }
}
#endif
