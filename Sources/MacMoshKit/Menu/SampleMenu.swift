// Debug builds only. A release build has none of this, and `scripts/build-app.sh` checks that the
// release app does not even contain the variable's name.
#if DEBUG
import Foundation
import os

/// The sample menus CI takes pictures of (issue #113), and nothing else.
///
/// A debug build of the app started with `MACMOSH_SAMPLE_MENU=<name>` shows that sample instead of
/// checking any workhorse: no ssh, no network, no file read from the support folder. The menu is still
/// built by the real `MenuModel.build`, from report text read by the real `HostStatus.parse`, and goes
/// through the real `MenuRefresher`, `MenuOnScreen` and `HoldStill`, so the pictures show the real
/// drawing code and the real hold-still rule. A click on a line runs nothing: the menu's view writes
/// `sample row ran: <row id>`, and the stand-ins below write that no tab was opened and no command run.
/// Every name in here is made up.
public enum SampleMenu: String, CaseIterable, Sendable {
    /// One Ready laptop with six desks: one with three windows, and `garden`, a closed permanent desk.
    case sixDesks = "six-desks"
    /// The same, with sign-ins off.
    case signInsOff = "sign-ins-off"
    case locked
    case waitingForLogin = "waiting-for-login"
    /// The six-desk workhorse, Ready, and a second one, Locked.
    case twoWorkhorses = "two-workhorses"
    case noWorkhorses = "no-workhorses"
    /// The six-desk menu, changing every `changeEvery`: `api`'s title each time, and the desk
    /// `scratch` there on odd changes and gone on even ones. It exercises `HoldStill`.
    case changing
    /// A script-0.11.0 report with window details, views and labels, and stand-in tab records for it (issue
    /// #124): each desk past the gate has a line per window, and Name a window… (issue 144). `website` has a window in a tab this Mac can find,
    /// one open in a tab it can't, and one with no tab.
    case windows
    /// Look step 6: the workhorse can't be reached (nothing answers), for the menu bar's hollow mark.
    case cantReach = "cant-reach"
    /// Look step 6: the workhorse needs setting up (its script is missing), for the menu bar's wrench badge.
    case notSetUp = "not-set-up"
    /// Look step 6: the workhorse is still being checked at every look, for the menu bar's faint mark, which a
    /// real launch shows only for a moment.
    case stillChecking = "still-checking"

    /// The environment variable that names the sample.
    public static let variable = "MACMOSH_SAMPLE_MENU"
    /// How often the `changing` sample changes.
    public static let changeEvery: Double = 3
    /// How long the app waits between two looks at a sample, in place of `PollSchedule`.
    public static let lookEvery: Duration = .seconds(1)

    /// The name this process was started with, if any. It may not be a sample's name.
    public static var requested: String? { ProcessInfo.processInfo.environment[variable] }

    /// The line the app writes when it starts with a sample.
    public var startedLine: String { "sample menu: \(rawValue)" }

    /// A menu row's line or primary action ran. Written only when a sample is shown; the id holds
    /// only the made-up names of the sample.
    public static func rowRan(_ id: String) {
        if requested != nil { MenuLog.write("sample row ran: \(id)") }
    }

    /// The refresher for this sample: the real one, with the saved list and the checks replaced.
    @MainActor public func refresher() -> MenuRefresher {
        let sample = self
        let start = Date()
        let lastChange = OSAllocatedUnfairLock(initialState: -1)
        return MenuRefresher(
            load: { sample.workhorses },
            gather: { _ in
                let change = sample == .changing ? Int(Date().timeIntervalSince(start) / Self.changeEvery) : 0
                if sample == .changing {
                    let isNew = lastChange.withLock { last -> Bool in
                        defer { last = change }
                        return last != change
                    }
                    if isNew { MenuLog.write("sample changed: change=\(change)") }
                }
                return sample.gathered(change: change)
            },
            save: { _ in },
            tabRecords: sample == .windows ? Self.writeWindowRecords() : nil)
    }

    /// Writes the `windows` sample's stand-in records into the sample's own folder, and gives that folder.
    private static func writeWindowRecords() -> TabRecordStore {
        let store = records
        for record in windowRecords(openedAt: Date()) {
            do { try store.write(record) } catch { MenuLog.write("sample: a tab record was not written") }
        }
        return store
    }

    /// Does what a line asks the way the app does (`MenuActionRunner`), with a tab opener and a
    /// command runner that open and run nothing.
    public static var actions: MenuActionRunner {
        MenuActionRunner(macmoshPath: "/sample/macmosh", tabs: SampleNoTabs(), runner: SampleNoCommands(),
                         records: records)
    }

    /// The sample's tab records: a folder of the sample's own under the temporary folder, never the real
    /// support folder, with a stand-in that says every record's process is alive.
    static var records: TabRecordStore {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("macmosh-sample", isDirectory: true)
        return TabRecordStore(paths: Paths(supportDir: folder, sshDir: folder), probe: SampleAlive())
    }

    // MARK: The samples

    static let main = Workhorse(id: "workhorse", name: "Workhorse", user: "sample", mainAddress: "workhorse",
                                hostKey: "ssh-ed25519 SAMPLE-KEY-NOT-REAL", paired: true,
                                osVersion: "26.1", arch: "arm64")
    static let spare = Workhorse(id: "spare", name: "Spare", user: "sample", mainAddress: "spare",
                                 hostKey: "ssh-ed25519 SAMPLE-KEY-NOT-REAL", paired: true,
                                 osVersion: "26.1", arch: "arm64")

    var workhorses: [Workhorse] {
        switch self {
        case .noWorkhorses: return []
        case .twoWorkhorses: return [Self.main, Self.spare]
        default: return [Self.main]
        }
    }

    /// What the checks find, at the `change`-th change of the `changing` sample (0 for the others).
    func gathered(change: Int) -> [Gathered] {
        let ready = Self.result(Self.main, .ready(signIns: true), report: Self.report(change: nil), home: true)
        switch self {
        case .sixDesks:
            return [.checked(ready)]
        case .signInsOff:
            return [.checked(Self.result(Self.main, .ready(signIns: false),
                                         report: Self.report(signIns: false, change: nil), home: false))]
        case .locked:
            return [.checked(Self.result(Self.main, .locked, report: nil, home: nil))]
        case .waitingForLogin:
            return [.checked(Self.result(Self.main, .waitingForLogin, report: Self.waitingReport, home: true))]
        case .twoWorkhorses:
            return [.checked(ready), .checked(Self.result(Self.spare, .locked, report: nil, home: nil))]
        case .noWorkhorses:
            return []
        case .changing:
            return [.checked(Self.result(Self.main, .ready(signIns: true), report: Self.report(change: change),
                                         home: true))]
        case .windows:
            return [.checked(Self.result(Self.main, .ready(signIns: true), report: Self.windowsReport, home: true))]
        case .cantReach:
            return [.checked(Self.result(Self.main, .cantReach(.nothingAnswers), report: nil, home: nil))]
        case .notSetUp:
            return [.checked(Self.result(Self.main, .notSetUp(.hostScriptMissing), report: nil, home: nil))]
        case .stillChecking:
            return [.stillChecking(Self.main)]
        }
    }

    static func result(_ w: Workhorse, _ state: WorkhorseState, report: String?, home: Bool?) -> CheckResult {
        CheckResult(workhorse: w, state: state, status: report.flatMap { try? HostStatus.parse($0) },
                    probes: ProbeSet(), answeredAt: report == nil ? nil : w.mainAddress,
                    homeReachable: home, checkedAt: Date())
    }

    /// A workhorse script 0.8.0 report from a laptop on power. `website` has three windows, two of
    /// them in tabs, and is kept running and permanent; `garden` is permanent and closed. With a
    /// `change`, `api`'s second window is named after it, and `scratch` is there when it is odd.
    static func report(signIns: Bool = true, change: Int?) -> String {
        var lines = [
            "macmosh-host\t1\t0.8.0", "os\t26.1\tarm64", "console\tsample", "server\tup",
            "signins\t\(signIns ? "ok" : "off")", "agent\tinstalled", "power\tsleep=0\twomp=1",
            "battery\tpresent\tac\t82",
            "desk\twebsite\t3\t2", "window\twebsite\t0\tclaude", "window\twebsite\t1\tzsh", "window\twebsite\t2\tvim",
            "desk\tapi\t2\t0", "window\tapi\t0\tserver", "window\tapi\t1\t" + (change.map { "tests \($0)" } ?? "tests"),
            "desk\tnotes\t1\t1", "window\tnotes\t0\tzsh",
            "desk\tblog\t1\t0", "window\tblog\t0\tzsh",
            "desk\tshop\t2\t1", "window\tshop\t0\tweb", "window\tshop\t1\tdb",
        ]
        if let change, change % 2 == 1 {
            lines += ["desk\tscratch\t1\t0", "window\tscratch\t0\tzsh"]
        }
        lines += ["def\twebsite\t1\t1\t1\t/projects/website", "def\tgarden\t1\t0\t1\t/projects/garden", "end"]
        return lines.joined(separator: "\n") + "\n"
    }

    /// The labels of the `windows` sample's tabs this Mac can find: website's claude, notes, and shop's
    /// first web twice.
    static let claudeLabel = "5a3c9e1f7b2d4c60", notesLabel = "8e1f2a3b4c5d6e70"
    static let webLabel = "1b2c3d4e5f607182", webLabel2 = "9a8b7c6d5e4f3021"
    /// The start time the stand-in gives every process, and every stand-in record carries.
    static let standInStart: Int64 = 1_800_000_000_000_000

    /// The `windows` sample's records, as `macmosh connect` would have written them. A view line with no label
    /// (website's zsh) is a tab this Mac can't find, as one opened by an older app is.
    static func windowRecords(openedAt: Date) -> [TabRecord] {
        [(claudeLabel, "website", "@1", 300.0), (notesLabel, "notes", "@7", 400), (webLabel, "shop", "@9", 200),
         (webLabel2, "shop", "@9", 100)].enumerated().map { i, r in
            TabRecord(label: r.0, workhorse: main.id, desk: r.1, askedWindow: r.2, pid: Int32(100 + i), started: standInStart,
                      tty: "/dev/ttys00\(i + 1)", terminal: .iterm2, openedAt: openedAt.addingTimeInterval(-r.3))
        }
    }

    /// A workhorse script 0.11.0 report with window details (0.8.0's, and 0.11.0 names windows, issue 144):
    /// `website` (claude in a tab, zsh in a tab with no
    /// label, vim in none; kept running and permanent), `api` (two windows, no tab), `notes` (one window in a
    /// tab), `blog` (one window, no tab), `shop` (web in two tabs, a second web in none) and `garden`,
    /// permanent and closed.
    static let windowsReport = [
        "macmosh-host\t1\t0.11.0", "os\t26.1\tarm64", "console\tsample", "server\tup", "signins\tok",
        "agent\tinstalled", "power\tsleep=0\twomp=1", "battery\tpresent\tac\t82",
        "desk\twebsite\t3\t0", "window\twebsite\t0\tclaude", "window\twebsite\t1\tzsh", "window\twebsite\t2\tvim",
        "windowinfo\twebsite\t0\t@1\t1\t1", "windowinfo\twebsite\t1\t@2\t0\t1", "windowinfo\twebsite\t2\t@3\t0\t0",
        "view\twebsite\twebsite+101\t@1\t1\t\(claudeLabel)", "view\twebsite\twebsite+102\t@2\t1",
        "desk\tapi\t2\t0", "window\tapi\t0\tserver", "window\tapi\t1\ttests",
        "windowinfo\tapi\t0\t@5\t1\t0", "windowinfo\tapi\t1\t@6\t0\t0",
        "desk\tnotes\t1\t0", "window\tnotes\t0\tzsh", "windowinfo\tnotes\t0\t@7\t1\t1",
        "view\tnotes\tnotes+103\t@7\t1\t\(notesLabel)",
        "desk\tblog\t1\t0", "window\tblog\t0\tzsh", "windowinfo\tblog\t0\t@8\t1\t0",
        "desk\tshop\t2\t0", "window\tshop\t0\tweb", "window\tshop\t1\tweb",
        "windowinfo\tshop\t0\t@9\t1\t2", "windowinfo\tshop\t1\t@10\t0\t0",
        "view\tshop\tshop+104\t@9\t1\t\(webLabel)", "view\tshop\tshop+105\t@9\t1\t\(webLabel2)",
        "def\twebsite\t1\t1\t1\t/projects/website", "def\tgarden\t1\t0\t1\t/projects/garden", "end",
    ].joined(separator: "\n") + "\n"

    /// The report of a workhorse that answers with nobody logged in.
    static let waitingReport = [
        "macmosh-host\t1\t0.8.0", "os\t26.1\tarm64", "console\t", "server\tdown", "signins\tok",
        "agent\tinstalled", "battery\tpresent\tac\t82", "end",
    ].joined(separator: "\n") + "\n"
}

/// Opens no tab and brings none forward; says so in the log. Asked to bring a tab forward, it answers as
/// if it had, so the `windows` sample keeps its records and its picture after a click.
struct SampleNoTabs: TabOpening {
    func open(_ command: TabCommand, title: String) async throws -> String? {
        MenuLog.write("sample: no tab opened")
        return nil
    }

    func select(tty: String, terminal: TabRecord.Terminal) async throws -> TabSelection {
        MenuLog.write("sample: no tab brought forward")
        return .selected
    }
}

/// Says every process is alive and started at `SampleMenu.standInStart`, so the sample's records are live
/// without any real process.
struct SampleAlive: ProcessProbe {
    func exists(_ pid: Int32) -> Bool { pid > 0 }
    func startTime(of pid: Int32) -> Int64? { pid > 0 ? SampleMenu.standInStart : nil }
}

/// Runs no command; says so in the log and reports success.
struct SampleNoCommands: CommandRunner {
    func run(_ executable: String, _ arguments: [String], environment: [String: String],
             stdin: Data?, timeout: Duration) async -> CommandResult {
        MenuLog.write("sample: no command run")
        return CommandResult(exitCode: 0, stdout: "", stderr: "", timedOut: false)
    }
}
#endif
