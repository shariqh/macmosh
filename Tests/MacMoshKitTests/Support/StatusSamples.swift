import Foundation
@testable import MacMoshKit

/// The user@address an ssh call was made to: the argument after `--`.
func sshTarget(_ argv: [String]) -> String? {
    guard let dashes = argv.firstIndex(of: "--"), dashes + 1 < argv.count else { return nil }
    return argv[dashes + 1]
}

/// The remote command an ssh call ran: whatever follows the target.
func sshRemote(_ argv: [String]) -> [String] {
    guard let dashes = argv.firstIndex(of: "--"), dashes + 2 <= argv.count else { return [] }
    return Array(argv[(dashes + 2)...])
}

/// An answer from a workhorse that timed out.
let sshTimedOut = FakeRunner.failed(255, stderr: "ssh: connect to host x port 22: Operation timed out\n")

/// A runner that answers each ssh call by its target (`alex@workhorse` and so on); anything not
/// listed times out. Calls to other programs fail.
func sshRunner(_ answers: [String: CommandResult]) -> FakeRunner {
    FakeRunner { argv in
        guard argv.first == "ssh" else { return FakeRunner.failed(1) }
        return sshTarget(argv).flatMap { answers[$0] } ?? sshTimedOut
    }
}

extension CheckResult {
    /// A finished check, with only the parts a test names. The state is the one given, not worked out.
    static func sample(
        _ state: WorkhorseState,
        workhorse: Workhorse = .sample(),
        status: HostStatus? = nil,
        probes: ProbeSet = ProbeSet(),
        answeredAt: String? = nil,
        homeReachable: Bool? = nil,
        checkedAt: Date = Date(timeIntervalSince1970: 1_800_000_000)
    ) -> CheckResult {
        CheckResult(workhorse: workhorse, state: state, status: status, probes: probes,
                    answeredAt: answeredAt, homeReachable: homeReachable, checkedAt: checkedAt)
    }
}

/// A time zone and a "now" the format tests agree on: 2027-01-15 16:00 UTC, in UTC.
let formatZone = TimeZone(identifier: "UTC")!
let formatNow = utcDate(2027, 1, 15, 16, 0)

/// `components` in `formatZone`, so a test writes the time it means ("14:02 today").
func utcDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = formatZone
    return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}
