import Foundation
@testable import MacMoshKit

extension HostStatus {
    /// A report from a workhorse where every check that can fail does: an old script and no login
    /// agent, the desk server down with somebody logged in, mosh and tmux missing (Homebrew there),
    /// Screen Sharing off, a desktop that sleeps and doesn't restart after a power cut, FileVault off
    /// and the firewall on. It still gives a home address, so the "record it" fix has something to save.
    static var everythingWrong: HostStatus {
        var s = HostStatus()
        s.scriptVersion = "0.0.1"
        s.osVersion = "15.6"
        s.arch = "arm64"
        s.consoleUser = "alex"
        s.serverUp = false
        s.signIns = .unknown
        s.fileVault = .no
        s.authRestart = .no
        s.firewall = .yes
        s.screenSharing = .no
        s.agentInstalled = false
        s.power = Power(sleepOnPower: 10, wakeForNetwork: 0, autoRestart: 0, disableSleep: nil)
        s.battery = Battery(present: false, onAC: nil, percent: nil)
        s.home = Home(address: "192.168.1.20", prefix: 24, localName: "workhorse.local")
        s.tools = [Tool(name: "brew", path: "/opt/homebrew/bin/brew", version: nil),
                   Tool(name: "mosh-server", path: nil, version: nil),
                   Tool(name: "tmux", path: nil, version: nil)]
        return s
    }

    /// A report where every check passes, from a desktop Mac with the built-in script.
    static var everythingRight: HostStatus {
        var s = HostStatus.sampleReady
        s.scriptVersion = HostScript.version
        s.fileVault = .yes
        s.authRestart = .yes
        s.firewall = .no
        s.screenSharing = .yes
        s.power = Power(sleepOnPower: 0, wakeForNetwork: 1, autoRestart: 1, disableSleep: nil)
        s.battery = Battery(present: false, onAC: nil, percent: nil)
        s.home = Home(address: "192.168.1.20", prefix: 24, localName: "workhorse.local")
        s.tools = [Tool(name: "brew", path: "/opt/homebrew/bin/brew", version: nil),
                   Tool(name: "mosh-server", path: "/opt/homebrew/bin/mosh-server", version: "1.4.0"),
                   Tool(name: "tmux", path: "/opt/homebrew/bin/tmux", version: "3.8")]
        return s
    }

    /// The report as the workhorse script prints it (protocol 1), so a test can feed it to the real
    /// `StatusChecker` through a `FakeRunner`.
    var reportText: String {
        func tri(_ t: Tri, _ yes: String, _ no: String) -> String {
            switch t {
            case .yes: return yes
            case .no: return no
            case .unknown: return "unknown"
            }
        }
        func number(_ n: Int?) -> String { n.map(String.init) ?? "-" }
        var lines = [
            "macmosh-host\t1\t\(scriptVersion)",
            "os\t\(osVersion)\t\(arch)",
            "console\t\(consoleUser ?? "")",
            "server\t\(serverUp ? "up" : "down")",
            "signins\t\(tri(signIns, "ok", "off"))",
            "filevault\t\(tri(fileVault, "on", "off"))",
            "authrestart\t\(tri(authRestart, "yes", "no"))",
            "power\tsleep=\(number(power.sleepOnPower))\twomp=\(number(power.wakeForNetwork))\tautorestart=\(number(power.autoRestart))\tdisablesleep=\(number(power.disableSleep))",
            "battery\t\(battery.present ? "present" : "absent")\t\(battery.onAC.map { $0 ? "ac" : "battery" } ?? "-")\t\(number(battery.percent))",
            "home\t\(home.address ?? "")\t\(home.prefix.map(String.init) ?? "")\t\(home.localName ?? "")",
            "firewall\t\(tri(firewall, "on", "off"))",
            "screensharing\t\(tri(screenSharing, "on", "off"))",
            "agent\t\(agentInstalled ? "installed" : "missing")",
        ]
        for tool in tools {
            lines.append("tool\t\(tool.name)\t\(tool.path ?? "-")\t\(tool.version ?? "-")")
        }
        for desk in desks {
            lines.append("desk\t\(desk.name.value)\t\(desk.windowCount)\t\(desk.attached)")
        }
        lines.append("end")
        return lines.joined(separator: "\n") + "\n"
    }

    /// The same report with open desks of these names.
    func withDesks(_ names: [String]) -> HostStatus {
        var s = self
        s.desks = names.compactMap { DeskName($0) }.map { HostStatus.Desk(name: $0, windows: [], windowCount: 1, attached: 0) }
        return s
    }
}

/// The daily Mac a checklist test sees: which programs exist, and nothing else.
func fakeLocalMac(programs: Set<String>, iTerm: Bool = true) -> LocalMac {
    LocalMac(isExecutable: { programs.contains($0) }, searchPath: "/usr/bin:/bin",
             iTermInstalled: { iTerm })
}

/// A `Checklist` over stand-ins: a real store in a temporary folder holding the workhorse, the real
/// `StatusChecker` over a `FakeRunner`, fixed hints, and a daily Mac where only the named programs exist.
///
/// The runner answers the status call with `report` (with no report, the shell can't find the script:
/// exit 127), the script's `version` call with the report's version, and every other call with success.
struct ChecklistFixture {
    let paths: Paths
    let store: WorkhorseStore
    let runner: FakeRunner
    let checklist: Checklist
    let workhorse: Workhorse

    init(report: HostStatus?, hints: Hints = .allFine,
         programs: Set<String> = ["/opt/homebrew/bin/brew", "/opt/homebrew/bin/mosh"],
         workhorse: Workhorse = .sample()) {
        let paths: Paths
        do { paths = try temporaryPaths() } catch { fatalError("could not make temporary paths: \(error)") }
        self.paths = paths
        self.workhorse = workhorse
        store = WorkhorseStore(paths: paths)
        do { try store.upsert(workhorse) } catch { fatalError("could not save the workhorse: \(error)") }
        let statusCall = SSHInvocation.hostCommand(["status"])
        let versionCall = SSHInvocation.hostCommand(["version"])
        runner = FakeRunner { argv in
            guard argv.first == "ssh" else { return FakeRunner.ok() }
            let remote = sshRemote(argv)
            if remote == statusCall || remote == versionCall {
                guard let report else {
                    return FakeRunner.failed(127, stderr: "zsh:1: no such file or directory: /Users/alex/.macmosh/macmosh-host\n")
                }
                return FakeRunner.ok(remote == statusCall ? report.reportText : report.scriptVersion + "\n")
            }
            return FakeRunner.ok()
        }
        let fixedHints = FixedHints(hints)
        checklist = Checklist(runner: runner, paths: paths, store: store,
                              checker: StatusChecker(runner: runner, paths: paths, hints: fixedHints),
                              keys: KeyManager(paths: paths, runner: runner), hints: fixedHints,
                              local: fakeLocalMac(programs: programs))
    }

    /// Every call's argv, one per line, for looking for words.
    var allCalls: String { runner.calls.map { $0.argv.joined(separator: " ") }.joined(separator: "\n") }
}

/// A check result a workhorse-side test starts from: the report read at the main address.
func answered(_ status: HostStatus, state: WorkhorseState = .ready(signIns: true),
              workhorse: Workhorse = .sample()) -> CheckResult {
    .sample(state, workhorse: workhorse, status: status, probes: ProbeSet(main: .ok(stdout: status.reportText)),
            answeredAt: workhorse.mainAddress)
}

/// Collects the lines a `progress` closure is given, from any thread.
final class ProgressLines: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []

    var all: [String] { lock.withLock { lines } }

    func add(_ line: String) { lock.withLock { lines.append(line) } }
}

/// One outcome out of a list, found by its id.
func outcome(_ id: CheckID, in list: [CheckOutcome]) -> CheckOutcome? {
    list.first { $0.id == id }
}
