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
    /// A Ready workhorse with three desks: `website-redesign`, made by MacMosh in a long folder, kept when
    /// it exits and not brought back after a restart, and `notes`, made by hand. Their second lines carry
    /// every unusual fact, whatever the folder's length. And (look step 1) a desk with a very long name and nine
    /// windows, two of them in a tab: its name is cut, never wrapped, and its tile shows five cells and the plus.
    case longFolder = "long-folder"
    /// A saved list that can't be read: the menu shows the store's sentence, and so does the window, in
    /// place of the Add a Mac page.
    case unreadableList = "unreadable-list"
    /// Step 4: Attic, Ready, with no projects folder saved, whose desks the window's New desk, Rename and
    /// Remove change through a stand-in ssh (`SampleForms`).
    case forms = "window-forms"
    /// Issue 163: the `window-forms` sample with a workhorse script older than 0.12.0, so the New desk form shows no
    /// first-window line and sends nothing about the window (`SampleForms.olderDesks`).
    case formsOlderScript = "window-forms-0.11"
    /// Step 5: Attic, Ready, whose desks end at the first click on Check now, so the window lists them under
    /// Ended (`SampleEnded`).
    case ended = "window-ended"
    /// Issue 157: Attic and Spare, Ready, whose settings the Settings page saves into a stand-in store of its own
    /// (`SampleSettings`).
    case settings = "window-settings"
    /// Look step 3: Macs in each kind of state, for the sidebar's pictures and checks. Workhorse, Ready with six desks;
    /// Attic, Ready with one; Spare, Locked after a restart; Den, Can't reach it; Loft, which never answers, so it is
    /// still checking. Look step 4 adds Workhorse-in-the-attic-by-the-window, a name too long for its row, Ready with
    /// one desk, and Shed, Ready with sign-ins off.
    case sidebar = "window-sidebar"

    var workhorses: [Workhorse] {
        switch self {
        case .unreadableList: return []
        case .forms, .formsOlderScript, .ended: return [SampleForms.attic]
        case .settings: return [SampleSettings.attic, SampleSettings.spare]
        case .sidebar: return [SampleMenu.main, Self.attic, SampleMenu.spare, Self.den, Self.loft, Self.annex, Self.shed]
        default: return [SampleMenu.main]
        }
    }

    /// Reads the sample's saved list. The unreadable one throws what a damaged file throws; the forms one reads
    /// its own saved list, so a projects folder saved from the form shows.
    func load() throws -> [Workhorse] {
        if self == .unreadableList { throw StoreError.unreadable("workhorses.json: not JSON") }
        if self == .forms || self == .formsOlderScript { return try WorkhorseStore(paths: SampleForms.paths).load() }
        if self == .settings { return try WorkhorseStore(paths: SampleSettings.paths).load() }
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
        case .forms:
            return [.checked(SampleForms.result(SampleForms.attic))]
        case .formsOlderScript:
            return [.checked(SampleForms.result(SampleForms.attic, desks: SampleForms.olderDesks))]
        case .ended:
            return [.checked(SampleEnded.result(SampleForms.attic))]
        case .settings:
            return workhorses.map { .checked(SampleForms.result($0)) }
        case .sidebar:
            // Loft has no entry, so it never answers.
            return [.checked(SampleMenu.result(SampleMenu.main, .ready(signIns: true), report: SampleMenu.report(change: nil),
                                               home: true)),
                    .checked(SampleMenu.result(Self.attic, .ready(signIns: true), report: Self.oneDeskReport, home: true)),
                    .checked(SampleMenu.result(SampleMenu.spare, .locked, report: nil, home: nil)),
                    .checked(SampleMenu.result(Self.den, .cantReach(.nothingAnswers), report: nil, home: nil)),
                    .checked(SampleMenu.result(Self.annex, .ready(signIns: true), report: Self.oneDeskReport, home: true)),
                    .checked(SampleMenu.result(Self.shed, .ready(signIns: false), report: Self.oneDeskReport, home: true))]
        }
    }

    /// The `sidebar` sample's other Macs, made as `SampleMenu.main` is, with the id as the address.
    private static func sample(_ id: String, _ name: String) -> Workhorse {
        Workhorse(id: id, name: name, user: "sample", mainAddress: id, hostKey: "ssh-ed25519 SAMPLE-KEY-NOT-REAL",
                  paired: true, osVersion: "26.1", arch: "arm64")
    }
    private static let attic = sample("attic", "Attic")
    private static let den = sample("den", "Den")
    private static let loft = sample("loft", "Loft")
    private static let annex = sample("annex", "Workhorse-in-the-attic-by-the-window")
    private static let shed = sample("shed", "Shed")

    /// The long-named desk of `longFolder`: 45 characters.
    static let longName = "garden-planner-for-the-allotment-by-the-river"

    /// A workhorse script 0.8.0 report with the three desks of `longFolder`. The `def` fields are the
    /// name, reopen, keep, permanent and the folder. The long-named desk has nine windows and two tabs, and no
    /// `windowinfo` lines, so its cells light from the first.
    static let longFolderReport = ([
        "macmosh-host\t1\t0.8.0", "os\t26.1\tarm64", "console\tsample", "server\tup", "signins\tok",
        "agent\tinstalled", "power\tsleep=0\twomp=1", "battery\tpresent\tac\t82",
        "desk\twebsite-redesign\t1\t1", "window\twebsite-redesign\t0\tzsh",
        "desk\tnotes\t1\t0", "window\tnotes\t0\tzsh",
        "desk\t\(longName)\t9\t2",
    ] + ["zsh", "server", "tests", "logs", "notes", "vim", "claude", "db", "web"].enumerated().map {
        "window\t\(longName)\t\($0.offset)\t\($0.element)"
    } + [
        "def\twebsite-redesign\t0\t0\t1\t/Users/sample/Development/clients/acme/website-redesign",
        "def\t\(longName)\t1\t1\t1\t/Users/sample/Development/\(longName)",
        "end",
    ]).joined(separator: "\n") + "\n"

    /// A workhorse script 0.8.0 report with one desk, notes, and no `def` line: Attic's in the `sidebar` sample ("Ready ·
    /// 1 desk"). A report that failed to parse would read "Ready · No desks".
    static let oneDeskReport = ["macmosh-host\t1\t0.8.0", "os\t26.1\tarm64", "console\tsample", "server\tup", "signins\tok",
        "agent\tinstalled", "power\tsleep=0\twomp=1", "battery\tpresent\tac\t82",
        "desk\tnotes\t1\t0", "window\tnotes\t0\tzsh", "end"].joined(separator: "\n") + "\n"

    /// The real refresher, with the saved list and the checks replaced.
    @MainActor public func refresher() -> MenuRefresher {
        if self == .forms { return SampleForms.refresher() }
        if self == .formsOlderScript { return SampleForms.refresher(desks: SampleForms.olderDesks) }
        if self == .ended { return SampleEnded.refresher() }
        if self == .settings { return SampleSettings.refresher() }
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
    /// What the window's desk actions run ssh with, and the folders they use: the forms sample's stand-in,
    /// which answers as the script would; for any other sample, a runner that runs nothing.
    public let ssh: CommandRunner
    public let paths: Paths
    /// The saved list and settings the Settings page reads and saves (issue 157): the settings sample's own
    /// stand-in, the forms sample's saved list for that sample, or for any other a folder of its own with the
    /// sample's workhorses (`SampleSettings.paths(forSample:list:)`). Never the person's.
    public let settingsPaths: Paths

    /// The sample with that name, or nil when there is none.
    public static func named(_ name: String) -> SampleRun? {
        if let menu = SampleMenu(rawValue: name) {
            let list = menu.workhorses
            return SampleRun(startedLine: menu.startedLine, workhorses: list, load: { list },
                             refresher: menu.refresher(), actions: SampleMenu.actions, ssh: SampleNoCommands(),
                             paths: SampleForms.paths,
                             settingsPaths: SampleSettings.paths(forSample: menu.rawValue, list: list))
        }
        if let window = SampleWindow(rawValue: name) {
            let paths = window == .settings ? SampleSettings.paths : SampleForms.paths
            let settingsPaths: Paths
            switch window {
            case .settings, .forms, .formsOlderScript: settingsPaths = paths
            case .unreadableList: settingsPaths = SampleSettings.paths(forSample: window.rawValue, list: nil)
            default: settingsPaths = SampleSettings.paths(forSample: window.rawValue, list: window.workhorses)
            }
            return SampleRun(startedLine: "sample menu: \(window.rawValue)", workhorses: window.workhorses,
                             load: { try window.load() }, refresher: window.refresher(), actions: SampleMenu.actions,
                             ssh: Self.ssh(window), paths: paths, settingsPaths: settingsPaths)
        }
        return nil
    }

    /// The stand-in ssh of a window sample: the forms' and the ended desks' answer as the script would.
    private static func ssh(_ window: SampleWindow) -> CommandRunner {
        switch window {
        case .forms: return SampleSSH()
        case .formsOlderScript: return SampleSSH(desks: SampleForms.olderDesks)
        case .ended: return SampleSSH(desks: SampleEnded.desks)
        default: return SampleNoCommands()
        }
    }

    /// A window button ran this action: `sample window ran: tab connect workhorse api`. Written only when a
    /// sample is shown; the words hold only the sample's made-up names. In the `window-ended` sample, the first
    /// Check now also ends the stand-in's shells (`SampleEnded`).
    public nonisolated static func windowRan(_ action: MenuAction) {
        guard let name = SampleMenu.requested else { return }
        MenuLog.write(ranLine(action))
        if name == SampleWindow.ended.rawValue, case .refresh = action { SampleEnded.checkNowClicked() }
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
