import Foundation
import Testing
@testable import MacMoshKit

/// The moment every check in these tests happens.
private let checkTime = Date(timeIntervalSince1970: 1_800_000_000)

private func checker(_ runner: CommandRunner, paths: Paths = .test, hints: Hints = .allFine) -> StatusChecker {
    StatusChecker(runner: runner, paths: paths, hints: FixedHints(hints), now: { checkTime })
}

/// The full example report: macOS 27.3, arm64, home 192.168.1.20/24, "workhorse.local".
private func fullReport() throws -> CommandResult {
    FakeRunner.ok(try fixture("status/full.txt"))
}

private let fullyNamed = Workhorse.sample(mainAddress: "workhorse", homeAddress: "192.168.1.20",
                                          homePrefix: 24, localName: "workhorse.local")

@Suite struct StatusCheckerTests {
    // MARK: the plan's named tests

    @Test func triesTheMainAddressThenHomeThenTheLocalName() async {
        let runner = FakeRunner { argv in argv.first == "ssh" ? FakeRunner.failed(255, stderr: "ssh: connect to host x port 22: Operation timed out\n") : FakeRunner.failed(1) }
        let w = Workhorse.sample(mainAddress: "workhorse", homeAddress: "192.168.1.20", localName: "workhorse.local")
        _ = await StatusChecker(runner: runner, paths: .test, hints: FixedHints(.allFine)).check(w)
        let targets = runner.calls.filter { $0.argv.first == "ssh" }.compactMap { $0.argv.first { $0.contains("@") } }
        #expect(targets == ["alex@workhorse", "alex@192.168.1.20", "alex@workhorse.local"])
    }

    @Test func everyProbeHasATimeLimit() async {
        let runner = FakeRunner { _ in CommandResult(exitCode: -1, stdout: "", stderr: "", timedOut: true) }
        let r = await StatusChecker(runner: runner, paths: .test, hints: FixedHints(.allFine)).check(.sample())
        #expect(runner.calls.allSatisfy { $0.timeout <= .seconds(15) })
        #expect(r.state == .cantReach(.nothingAnswers))
    }

    @Test func stopsAtTheFirstAddressThatAnswers() async {
        // An unreadable report from the main address ends the check there.
        let runner = sshRunner(["alex@workhorse": FakeRunner.ok("Welcome\nnot a report\n")])
        let r = await checker(runner).check(fullyNamed)
        #expect(runner.calls.count == 1)
        #expect(r.probes.main == .ok(stdout: "Welcome\nnot a report\n"))
        #expect(r.probes.home == nil && r.probes.local == nil)
        #expect(r.status == nil)
        #expect(r.state == .notSetUp(.unreadableReport))
        #expect(r.answeredAt == "workhorse")
    }

    @Test func aFailingScriptAlsoEndsTheCheck() async {
        // exit 127: the remote shell has no such script. ssh got through, so the next address isn't tried.
        let runner = sshRunner(["alex@workhorse": FakeRunner.failed(127, stderr: "zsh: no such file\n")])
        let r = await checker(runner).check(fullyNamed)
        #expect(runner.calls.count == 1)
        #expect(r.state == .notSetUp(.hostScriptMissing))
    }

    @Test func goesOnAfterAnyOtherOutcome() async throws {
        let runner = sshRunner([
            "alex@workhorse": FakeRunner.failed(255, stderr: "alex@workhorse: Permission denied (publickey,password).\n"),
            "alex@192.168.1.20": FakeRunner.failed(255, stderr: "ssh: connect to host x port 22: Connection refused\n"),
            "alex@workhorse.local": try fullReport(),
        ])
        let r = await checker(runner).check(fullyNamed)
        #expect(r.state == .ready(signIns: true))
        #expect(r.answeredAt == "workhorse.local")
        #expect(r.probes.main == .authDenied(methods: ["publickey", "password"]))
        #expect(r.probes.home == .refused)
    }

    @Test func savesOnlyTheReportsFields() async throws {
        // The record on disk changed while the check ran: that change is kept.
        let paths = try temporaryPaths()
        let store = WorkhorseStore(paths: paths)
        try store.save([.sample(id: "mbp", name: "MacBook Pro")])
        let report = try fixture("status/full.txt")
        let runner = FakeRunner { _ in
            try? store.update(id: "mbp") { $0.name = "Renamed meanwhile"; $0.projectsFolder = "~/Development" }
            return FakeRunner.ok(report)
        }
        let r = await checker(runner, paths: paths).check(try store.find("mbp"))
        try store.absorb(r)
        let saved = try store.find("mbp")
        #expect(saved.name == "Renamed meanwhile" && saved.projectsFolder == "~/Development")
        #expect(saved.homeAddress == "192.168.1.20" && saved.homePrefix == 24)
        #expect(saved.localName == "workhorse.local")
        #expect(saved.osVersion == "27.3" && saved.arch == "arm64")
        #expect(saved.lastSeen == checkTime && saved.lastKeyAccepted == checkTime)
        // Nothing else moved.
        var expected = saved
        expected.homeAddress = nil; expected.homePrefix = nil; expected.localName = nil
        expected.osVersion = nil; expected.arch = nil; expected.lastSeen = nil; expected.lastKeyAccepted = nil
        var original = Workhorse.sample(id: "mbp", name: "Renamed meanwhile")
        original.projectsFolder = "~/Development"
        #expect(expected == original)
    }

    @Test func aReportUpdatesTheWorkhorse() async throws {
        let runner = sshRunner(["alex@workhorse": try fullReport()])
        let r = await checker(runner).check(.sample(mainAddress: "workhorse"))
        let w = r.workhorse
        #expect(w.homeAddress == "192.168.1.20" && w.homePrefix == 24 && w.localName == "workhorse.local")
        #expect(w.osVersion == "27.3" && w.arch == "arm64")
        #expect(w.lastSeen == checkTime && w.lastKeyAccepted == checkTime)
        #expect(r.checkedAt == checkTime)
        #expect(r.status?.serverUp == true)
        #expect(r.state == .ready(signIns: true))
        #expect(r.answeredAt == "workhorse")
    }

    @Test func homeReachableComesFromAnSSHCallToTheHomeAddress() async throws {
        let reachable = sshRunner(["alex@workhorse": try fullReport(), "alex@192.168.1.20": FakeRunner.ok()])
        let yes = await checker(reachable).check(fullyNamed)
        #expect(yes.homeReachable == true)
        // One report call, then one call to the home address with the remote command `true`.
        #expect(reachable.calls.count == 2)
        #expect(sshTarget(reachable.calls[1].argv) == "alex@192.168.1.20")
        #expect(sshRemote(reachable.calls[1].argv) == ["true"])

        let away = sshRunner(["alex@workhorse": try fullReport()])        // the home address times out
        let no = await checker(away).check(fullyNamed)
        #expect(no.homeReachable == false)
        #expect(no.state == .ready(signIns: true))
    }

    @Test func theHomeCallIsMadeWithTheSameKeyOptionsAndATimeLimit() async throws {
        let runner = sshRunner(["alex@workhorse": try fullReport(), "alex@192.168.1.20": FakeRunner.ok()])
        _ = await checker(runner).check(fullyNamed)
        let expected = SSHInvocation.argv(for: fullyNamed, address: "192.168.1.20", paths: .test, batch: true,
                                          tty: false, remote: ["true"])
        #expect(runner.calls[1].argv == expected)
        #expect(runner.calls.allSatisfy { $0.timeout <= .seconds(15) })
    }

    @Test func homeReachableIsTrueWhenTheReportCameFromHome() async throws {
        let runner = sshRunner(["alex@192.168.1.20": try fullReport()])
        let r = await checker(runner).check(fullyNamed)
        #expect(r.homeReachable == true)
        #expect(r.answeredAt == "192.168.1.20")
        #expect(runner.calls.count == 2)                // main timed out, then home answered: no extra call
        let local = sshRunner(["alex@workhorse.local": try fullReport()])
        let viaLocal = await checker(local).check(fullyNamed)
        #expect(viaLocal.homeReachable == true)
        #expect(local.calls.count == 3)
    }

    @Test func noHomeAddressKnownMeansNoAnswerAboutIt() async {
        // The report has a home address in it, so give a report without one.
        let report = "macmosh-host\t1\t0.1.0\nos\t27.3\tarm64\nconsole\talex\nserver\tup\nsignins\tok\nend\n"
        let runner = sshRunner(["alex@workhorse": FakeRunner.ok(report)])
        let r = await checker(runner).check(.sample())
        #expect(r.homeReachable == nil)
        #expect(runner.calls.count == 1)
    }

    @Test func aRefusedKeyAtTheHomeAddressIsLockedAndSaysWhereItWasRefused() async {
        let denied = FakeRunner.failed(255, stderr: "alex@192.168.1.20: Permission denied (password,keyboard-interactive).\n")
        let runner = sshRunner(["alex@192.168.1.20": denied])
        let r = await checker(runner).check(fullyNamed)
        #expect(r.state == .locked)
        #expect(r.answeredAt == "192.168.1.20")
        #expect(r.status == nil)
        #expect(r.homeReachable == true)            // the home address answered, even if it turned the key down
    }

    @Test func unreachableUsesTheHints() async {
        let off = Hints(tailscaleRunning: false, peerOnline: nil, hasNetwork: true, otherVPN: false, atHome: nil)
        let r = await checker(sshRunner([:]), hints: off).check(fullyNamed)
        #expect(r.state == .cantReach(.tailscaleOff))
        #expect(r.answeredAt == nil)
        #expect(r.homeReachable == false)
        #expect(r.workhorse == fullyNamed)           // nothing learned, nothing changed
    }

    @Test func checkAllKeepsTheOrder() async throws {
        let report = try fixture("status/full.txt")
        let runner = sshRunner([
            "alex@one": FakeRunner.ok(report),
            "alex@three": FakeRunner.failed(255, stderr: "alex@three: Permission denied (publickey).\n"),
        ])
        let list = [Workhorse.sample(id: "one", mainAddress: "one"),
                    Workhorse.sample(id: "two", mainAddress: "two"),
                    Workhorse.sample(id: "three", mainAddress: "three")]
        let results = await checker(runner).checkAll(list)
        #expect(results.map(\.workhorse.id) == ["one", "two", "three"])
        let states = results.map(\.state)
        let expected: [WorkhorseState] = [.ready(signIns: true), .cantReach(.nothingAnswers), .notSetUp(.notPaired)]
        #expect(states == expected)
        #expect(await checker(runner).checkAll([]).isEmpty)
    }

    @Test func aBadKeyFileSkipsTheProbes() async {
        let runner = sshRunner([:])
        var w = fullyNamed
        w.identityFile = "/nonexistent/macmosh_test_key"
        #expect(KeyManager(paths: .test, runner: runner).identityState(for: w) == .missing)
        let r = await checker(runner).check(w)
        #expect(r.state == .notSetUp(.identityUnusable))
        #expect(runner.calls.isEmpty)
        #expect(r.status == nil && r.probes == ProbeSet() && r.answeredAt == nil && r.homeReachable == nil)
    }

    @Test func aKeyWithBadPermissionsSkipsTheProbesToo() async throws {
        let paths = try temporaryPaths()
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: paths.defaultIdentity.path)
        let runner = sshRunner([:])
        let r = await checker(runner, paths: paths).check(.sample())
        #expect(r.state == .notSetUp(.identityUnusable))
        #expect(runner.calls.isEmpty)
    }

    @Test func aHostKeyThatDiffersWinsOverAReportElsewhere() async throws {
        let changed = FakeRunner.failed(255, stderr: "@    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @\nHost key verification failed.\n")
        let runner = sshRunner(["alex@workhorse": changed, "alex@192.168.1.20": try fullReport()])
        let r = await checker(runner).check(fullyNamed)
        #expect(r.state == .cantVerify)
    }

    // MARK: absorb

    @Test func absorbSavesNothingWithoutAReport() async throws {
        let paths = try temporaryPaths()
        let store = WorkhorseStore(paths: paths)
        try store.save([.sample(id: "mbp")])
        let r = await checker(sshRunner([:]), paths: paths).check(try store.find("mbp"))
        let before = try Data(contentsOf: paths.workhorsesFile)
        try store.absorb(r)
        #expect(try Data(contentsOf: paths.workhorsesFile) == before)
    }

    @Test func absorbDoesNotBringBackAWorkhorseRemovedDuringTheCheck() async throws {
        let paths = try temporaryPaths()
        let store = WorkhorseStore(paths: paths)
        try store.save([.sample(id: "mbp"), .sample(id: "mini", name: "Mini")])
        let report = try fixture("status/full.txt")
        let runner = FakeRunner { _ in
            try? store.remove(id: "mbp")
            return FakeRunner.ok(report)
        }
        let r = await checker(runner, paths: paths).check(try store.find("mbp"))
        #expect(r.status != nil)
        try store.absorb(r)                                  // does not throw
        #expect(try store.load().map(\.id) == ["mini"])
    }

    // MARK: Workhorse.canUnlockOverSSH

    @Test func unlockOverSSHFollowsTheSavedVersionAndChip() {
        #expect(Workhorse.sample(osVersion: "27.3", arch: "arm64").canUnlockOverSSH)
        #expect(Workhorse.sample(osVersion: "26.0", arch: "arm64").canUnlockOverSSH)
        #expect(!Workhorse.sample(osVersion: "15.6", arch: "arm64").canUnlockOverSSH)
        #expect(!Workhorse.sample(osVersion: "27.3", arch: "x86_64").canUnlockOverSSH)
        #expect(Workhorse.sample().canUnlockOverSSH)         // nothing saved yet counts as able
    }
}
