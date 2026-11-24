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

    var workhorses: [Workhorse] { [SampleMenu.main] }

    /// What the `check`-th check finds (counting from 0).
    func gathered(check: Int) -> [Gathered] {
        if check == 0 {
            return [.checked(SampleMenu.result(SampleMenu.main, .ready(signIns: true),
                                               report: SampleMenu.report(change: nil), home: true))]
        }
        return [.checked(SampleMenu.result(SampleMenu.main, .locked, report: nil, home: nil))]
    }

    /// The real refresher, with the saved list and the checks replaced.
    @MainActor public func refresher() -> MenuRefresher {
        let sample = self
        let checks = OSAllocatedUnfairLock(initialState: 0)
        return MenuRefresher(
            load: { sample.workhorses },
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
    public let refresher: MenuRefresher
    public let actions: MenuActionRunner

    /// The sample with that name, or nil when there is none.
    public static func named(_ name: String) -> SampleRun? {
        if let menu = SampleMenu(rawValue: name) {
            return SampleRun(startedLine: menu.startedLine, workhorses: menu.workhorses, refresher: menu.refresher(),
                             actions: SampleMenu.actions)
        }
        if let window = SampleWindow(rawValue: name) {
            return SampleRun(startedLine: "sample menu: \(window.rawValue)", workhorses: window.workhorses,
                             refresher: window.refresher(), actions: SampleMenu.actions)
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
