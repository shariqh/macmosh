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

/// One menu for every state the design names, and one with no workhorses, for tests that look at all of them.
func everySampleMenu() -> [MenuLines] {
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
    var menus = results.map { MenuModel.build([.checked($0)]) }
    menus.append(MenuModel.build([.stillChecking(.sample())]))
    menus.append(MenuModel.build([]))
    menus.append(MenuModel.build(results.map(Gathered.checked)))
    return menus
}
