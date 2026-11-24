import Foundation
@testable import MacMoshKit

/// A runner whose every call takes `duration` (or until the call is cancelled), then reports a timeout.
/// It sleeps without blocking a thread, so cancelling the task ends it, as cancelling `ProcessRunner` ends ssh.
struct SleepingRunner: CommandRunner {
    let duration: Duration

    func run(_ executable: String, _ arguments: [String], environment: [String: String],
             stdin: Data?, timeout: Duration) async -> CommandResult {
        try? await Task.sleep(for: duration)
        return CommandResult(exitCode: -1, stdout: "", stderr: "", timedOut: true)
    }
}

extension FakeRunner {
    /// A stand-in for an ssh that hangs: every call takes `duration`.
    static func sleeping(_ duration: Duration) -> SleepingRunner { SleepingRunner(duration: duration) }
}

extension HostStatus {
    /// Ready, with the desk `website` (two windows, `zsh` and `vim`, one tab attached), on power at 82%.
    static var sampleWithDesk: HostStatus {
        var s = HostStatus.sampleReady
        s.power = Power(sleepOnPower: 0, wakeForNetwork: 1, autoRestart: nil, disableSleep: nil)
        s.battery = Battery(present: true, onAC: true, percent: 82)
        s.desks = [
            Desk(name: DeskName("website")!,
                 windows: [Window(index: 0, name: "zsh"), Window(index: 1, name: "vim")],
                 windowCount: 2, attached: 1),
        ]
        return s
    }
}

extension CheckResult {
    /// A workhorse that is Ready, with the sample desk and the home address reachable.
    static func sampleReady(id: String = "mbp", name: String = "MacBook Pro") -> CheckResult {
        .sample(.ready(signIns: true), workhorse: .sample(id: id, name: name), status: .sampleWithDesk,
                homeReachable: true)
    }
}

/// What one sample menu is built from, so a test can build the window's board from the same checks.
struct SampleMenuInput {
    var gathered: [Gathered]
    var waitingForDeskServer: Set<String> = []
    /// This Mac's live tab records and where its tabs open (issue #124); none by default.
    var tabs = TabsOnThisMac()
    var now = Date()
    var timeZone = TimeZone.current

    var menu: MenuLines {
        MenuModel.build(gathered, waitingForDeskServer: waitingForDeskServer, tabs: tabs, now: now, timeZone: timeZone)
    }
}

/// The report of the menu design's example (section 6.1 (a)), from Attic: `Fixtures/status/desks-windows.txt`.
func windowsReport(version: String = "0.8.0") -> HostStatus {
    var s = try! HostStatus.parse(fixture("status/desks-windows.txt"))
    s.scriptVersion = version
    return s
}

/// The live records of the design's example: website's claude and zsh, and notes, each in a tab this Mac opened.
let windowsRecords = [atticRecord("3f9a2c71e5b7d4a6", minutesAgo: 20), atticRecord("b04e5d12c3a4f5e6", minutesAgo: 10),
                      atticRecord("c1d2e3f4a5b6c7d8", minutesAgo: 30)]

/// Menus with a line per window (issue #124), and the same report where the gate keeps today's shape. Their
/// stored copy is `Fixtures/menu/windows-menu.txt`.
func windowSampleInputs() -> [SampleMenuInput] {
    func attic(_ status: HostStatus, mode: ConnectionMode = .mosh) -> Gathered {
        .checked(.sample(.ready(signIns: true), workhorse: .sample(id: "attic", name: "Attic", mode: mode), status: status,
                         homeReachable: true))
    }
    let here = TabsOnThisMac(records: windowsRecords, terminal: .iterm2)
    // A tab opened on api's server a minute ago, not in the report yet.
    let fresh = TabsOnThisMac(records: windowsRecords + [atticRecord("9f3a1c2e5b7d4a60", asked: "@5", minutesAgo: 1)],
                              terminal: .iterm2)
    return [
        SampleMenuInput(gathered: [attic(windowsReport())], tabs: here, now: windowsNow),
        SampleMenuInput(gathered: [attic(windowsReport(), mode: .tabs)], tabs: here, now: windowsNow),
        SampleMenuInput(gathered: [attic(windowsReport(version: "0.7.0"))], tabs: here, now: windowsNow),
        SampleMenuInput(gathered: [attic(windowsReport(), mode: .tabs)],
                        tabs: TabsOnThisMac(records: windowsRecords, terminal: .appleTerminal), now: windowsNow),
        SampleMenuInput(gathered: [attic(windowsReport())], tabs: fresh, now: windowsNow),
        SampleMenuInput(gathered: [attic(windowsReport()), .checked(.sampleReady(id: "spare", name: "Spare"))],
                        tabs: here, now: windowsNow),
    ]
}

/// One menu for every state the design names, and one with no workhorses, for tests that look at all of them.
func everySampleMenu() -> [MenuLines] { everySampleInput().map(\.menu) }

/// What `everySampleMenu()` is built from, in its order.
func everySampleInput() -> [SampleMenuInput] {
    let able = Workhorse.sample(osVersion: "27.3", arch: "arm64")
    let readyOff = CheckResult.sample(.ready(signIns: false), status: .sampleWithDesk, homeReachable: false)
    let results: [CheckResult] = [
        .sampleReady(),
        readyOff,
        .sample(.waitingForLogin),
        .sample(.locked, workhorse: able),
        .sample(.cantVerify),
        .sample(.cantReach(.tailscaleOff)),
        .sample(.notSetUp(.notPaired)),
        .sample(.notSetUp(.hostScriptMissing)),
    ]
    var inputs = results.map { SampleMenuInput(gathered: [.checked($0)]) }
    inputs.append(SampleMenuInput(gathered: [.stillChecking(.sample())]))
    inputs.append(SampleMenuInput(gathered: []))
    inputs.append(SampleMenuInput(gathered: results.map(Gathered.checked)))
    return inputs
}
