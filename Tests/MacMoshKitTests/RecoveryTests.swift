import Foundation
import Testing
@testable import MacMoshKit

private let warnPassword = "You are about to type the Mac's password into ssh. MacMosh can't see it."
private let warnCloses = "When the unlock works, the connection closes by itself."
private let lockedAfter = "After this restart the disk will be locked."
private let sudoSentence = "ssh asks for the Mac's password, for sudo. You are typing into ssh; MacMosh can't see it."
private let fdesetupSentence = "Then fdesetup asks for a user name and password that can unlock the disk."

/// What ssh prints when the key at an address is not the pinned one.
private func changedKey() throws -> CommandResult {
    FakeRunner.failed(255, stderr: try fixture("ssh/changed-key.txt"))
}

/// What ssh prints at the locked screen: password sign-in only.
private func passwordOnly() throws -> CommandResult {
    FakeRunner.failed(255, stderr: try fixture("ssh/auth-denied-password-only.assumed.txt"))
}

@Suite struct RecoveryTests {
    // MARK: unlock

    @Test func unlockRefusesWhenTheKeyDiffers() async {
        let f = RecoveryFixture(state: .cantVerify)
        let code = await f.recovery.unlock(.sample(), ui: f.ui)
        #expect(code == 1 && f.interactive.calls.isEmpty)
        #expect(f.ui.said.contains { $0.contains("Don't type a password") })
    }

    @Test func unlockRefusesWhenTheHomeAddressHasAnotherKey() async throws {
        // The main address times out (Tailscale is down before login) and the home address offers a
        // different key. The real checker reads that as Can't verify it; unlock runs nothing.
        let runner = sshRunner(["alex@192.168.1.20": try changedKey()])
        let f = RealCheckRecovery(runner)
        let code = await f.recovery.unlock(.recoverySample(), ui: f.ui)
        #expect(code == 1)
        #expect(f.interactive.calls.isEmpty)
        #expect(f.ui.said.contains { $0.contains("Don't type a password") })
        #expect(!f.ui.said.contains(warnPassword))
        // Only the batch status probes ran: none of them can ask for a password.
        let sshCalls = runner.calls.map(\.argv).filter { $0.first == "ssh" }
        #expect(!sshCalls.isEmpty)
        #expect(sshCalls.allSatisfy { $0.contains("BatchMode=yes") })
    }

    @Test func unlockUsesPasswordSignInAtTheHomeAddress() {
        let argv = RecoveryFixture(state: .locked).recovery.unlockArgv(for: .sample(id: "mbp", user: "alex"), address: "192.168.1.20")
        #expect(argv.last == "alex@192.168.1.20")
        #expect(argv.contains("PubkeyAuthentication=no") && argv.contains("PreferredAuthentications=password,keyboard-interactive"))
        #expect(argv.contains("StrictHostKeyChecking=yes") && argv.contains("HostKeyAlias=macmosh-mbp"))
        #expect(!argv.contains("BatchMode=yes"))
    }

    @Test func unlockKeepsEveryHostKeyOption() {
        let w = Workhorse.sample(id: "mbp", user: "alex")
        let argv = RecoveryFixture(state: .locked).recovery.unlockArgv(for: w, address: "192.168.1.20")
        let pinned: [String] = SSHInvocation.hostKeyOptions(for: w, paths: .test)
        for option in pinned where option != "-o" {
            #expect(argv.contains(option))
        }
        #expect(!argv.contains("-t"))
        #expect(sshRemote(argv).isEmpty)
    }

    @Test func unlockSaysWhoIsAskingBeforeThePrompt() async {
        let f = RecoveryFixture(script: [.usual(.locked), .usual(.waitingForLogin)])
        let code = await f.recovery.unlock(.recoverySample(), ui: f.ui)
        #expect(code == 0)
        #expect(f.interactive.calls.count == 1)
        let run = f.ui.indexOfFirstRun
        let password = f.ui.indexOfSaid(warnPassword)
        let closes = f.ui.indexOfSaid(warnCloses)
        #expect(password != nil && closes != nil && run != nil)
        if let run, let password, let closes {
            #expect(password < run)
            #expect(closes < run)
        }
    }

    @Test func unlockGoesToTheAddressThatRefusedTheKey() async throws {
        // Real checker: the main address times out and the home address offers password sign-in only.
        let runner = sshRunner(["alex@192.168.1.20": try passwordOnly()])
        let f = RealCheckRecovery(runner)
        _ = await f.recovery.unlock(.recoverySample(), ui: f.ui)
        #expect(f.interactive.calls.count == 1)
        let argv = f.interactive.calls.first ?? []
        #expect(sshTarget(argv) == "alex@192.168.1.20")
        #expect(argv.contains("PubkeyAuthentication=no"))
    }

    @Test func unlockNeverGoesToTheMainAddressWhenAnotherRefused() async {
        let probes = ProbeSet(main: .authDenied(methods: ["password"]),
                              home: .authDenied(methods: ["password", "keyboard-interactive"]))
        let locked = ScriptedCheck(.locked, answeredAt: "workhorse", probes: probes)
        let f = RecoveryFixture(script: [locked, .usual(.waitingForLogin)])
        _ = await f.recovery.unlock(.recoverySample(), ui: f.ui)
        let target = f.interactive.calls.first.flatMap(sshTarget)
        #expect(target == "alex@192.168.1.20")
    }

    @Test func unlockStopsWhenNoAddressAnswered() async {
        let f = RecoveryFixture(script: [ScriptedCheck(.locked)])
        let code = await f.recovery.unlock(.recoverySample(), ui: f.ui)
        #expect(code == 1)
        #expect(f.interactive.calls.isEmpty)
        #expect(f.ui.said.contains { $0.contains("Can't reach it") })
        #expect(f.ui.waits == 1)
    }

    @Test func unlockStopsWhenNothingAnswers() async {
        let f = RecoveryFixture(state: .cantReach(.nothingAnswers))
        let code = await f.recovery.unlock(.recoverySample(), ui: f.ui)
        #expect(code == 1)
        #expect(f.interactive.calls.isEmpty)
        #expect(f.ui.said.contains { $0.contains("Nothing answers at either address") })
    }

    @Test func unlockIsNotOfferedOnAnOlderMac() async {
        let f = RecoveryFixture(state: .locked)
        let code = await f.recovery.unlock(.recoverySample(osVersion: "15.6"), ui: f.ui)
        #expect(code == 1)
        #expect(f.interactive.calls.isEmpty)
        let sentence = "This Mac can't be unlocked over the network: that needs Apple silicon and macOS 26 or later. Unlock it at the Mac."
        #expect(f.ui.said.contains(sentence))
        #expect(!f.ui.said.contains(warnPassword))
    }

    @Test func unlockIsNotOfferedOnAnIntelMac() async {
        let f = RecoveryFixture(state: .locked)
        let code = await f.recovery.unlock(.recoverySample(arch: "x86_64"), ui: f.ui)
        #expect(code == 1)
        #expect(f.interactive.calls.isEmpty)
    }

    @Test func cantVerifyComesBeforeTheOlderMacSentence() async {
        let f = RecoveryFixture(state: .cantVerify)
        _ = await f.recovery.unlock(.recoverySample(osVersion: "15.6"), ui: f.ui)
        #expect(f.ui.said.contains { $0.contains("Don't type a password") })
        #expect(!f.ui.said.contains { $0.contains("can't be unlocked over the network") })
    }

    @Test func unlockSaysWhatTheMacBecame() async {
        let f = RecoveryFixture(script: [.usual(.locked), .usual(.locked), .usual(.cantReach(.nothingAnswers)),
                                         .usual(.waitingForLogin)])
        let code = await f.recovery.unlock(.recoverySample(), ui: f.ui)
        #expect(code == 0)
        #expect(f.checker.checks == 4)
        let expectedSleeps: [Duration] = [.seconds(5), .seconds(5), .seconds(5)]
        #expect(f.sleeps.value == expectedSleeps)
        #expect(f.ui.said.contains("MacBook Pro · Waiting for login"))
        #expect(f.ui.said.contains("Next: press Log in…, or run: macmosh screen mbp"))
    }

    @Test func unlockStopsCheckingAfterTwoMinutes() async {
        let f = RecoveryFixture(state: .locked)
        let code = await f.recovery.unlock(.recoverySample(), ui: f.ui)
        #expect(code == 1)
        let total = f.sleeps.value.reduce(Duration.zero, +)
        #expect(total == .seconds(120))
        #expect(f.sleeps.value.allSatisfy { $0 == .seconds(5) })
        #expect(f.checker.checks == 25)
        #expect(f.ui.said.contains("MacBook Pro · Locked after a restart"))
        #expect(f.interactive.calls.count == 1)
    }

    @Test func anAlreadyUnlockedDiskIsNotAnError() async {
        for state in [WorkhorseState.ready(signIns: true), .waitingForLogin] {
            let f = RecoveryFixture(state: state)
            let code = await f.recovery.unlock(.recoverySample(), ui: f.ui)
            #expect(code == 0)
            #expect(f.interactive.calls.isEmpty)
            #expect(f.ui.said.contains("The disk is already unlocked."))
            #expect(f.ui.waits == 0)
        }
    }

    @Test func unlockStopsAtAWorkhorseThatIsNotSetUp() async {
        let f = RecoveryFixture(state: .notSetUp(.identityUnusable))
        let code = await f.recovery.unlock(.recoverySample(), ui: f.ui)
        #expect(code == 1)
        #expect(f.interactive.calls.isEmpty)
        #expect(f.ui.said.contains("MacBook Pro · Your ssh key is locked"))
    }

    // MARK: restart

    @Test func restartRunsNothingWithoutTheWord() async {
        let f = RecoveryFixture(state: .ready(signIns: true), answers: ["yes"])
        #expect(await f.recovery.restart(.sample(), full: false, ui: f.ui) == 1)
        #expect(f.interactive.calls.isEmpty)
    }

    @Test func restartTakesTheWordWithSpacesAround() async {
        let f = RecoveryFixture(state: .ready(signIns: true), answers: ["  restart \n"])
        #expect(await f.recovery.restart(.sample(), full: false, ui: f.ui) == 0)
        #expect(f.interactive.calls.count == 1)
        #expect(f.ui.asked == ["Type restart to go ahead: "])
    }

    @Test func restartRefusesAnotherSpelling() async {
        let f = RecoveryFixture(state: .ready(signIns: true), answers: ["Restart"])
        #expect(await f.recovery.restart(.sample(), full: false, ui: f.ui) == 1)
        #expect(f.interactive.calls.isEmpty)
    }

    @Test func restartListsTheDesksFirst() async {
        let f = RecoveryFixture(state: .ready(signIns: true), answers: ["restart"], desks: ["website", "api"])
        _ = await f.recovery.restart(.sample(), full: false, ui: f.ui)
        let desks = f.ui.indexOfSaid("These desks will close: website, api.")
        let question = f.ui.indexOfFirstQuestion
        #expect(desks != nil && question != nil)
        if let desks, let question { #expect(desks < question) }
        #expect(f.ui.said.first == "These desks will close: website, api.")
    }

    @Test func restartSaysWhenNoDesksAreOpen() async {
        let f = RecoveryFixture(state: .waitingForLogin, answers: ["restart"])
        #expect(await f.recovery.restart(.sample(), full: false, ui: f.ui) == 0)
        #expect(f.ui.said.contains("No desks are open."))
        #expect(f.interactive.calls.count == 1)
    }

    @Test func restartUsesAuthRestartWhenSupported() async {
        let f = RecoveryFixture(state: .ready(signIns: true), answers: ["restart"])
        #expect(await f.recovery.restart(.recoverySample(), full: false, ui: f.ui) == 0)
        let argv = f.interactive.calls.first ?? []
        #expect(sshRemote(argv) == ["sudo fdesetup authrestart"])
        #expect(argv.contains("-t"))
        #expect(f.ui.said.contains("The Mac restarts with its disk already unlocked."))
        let run = f.ui.indexOfFirstRun
        let sudo = f.ui.indexOfSaid(sudoSentence)
        let fdesetup = f.ui.indexOfSaid(fdesetupSentence)
        #expect(run != nil && sudo != nil && fdesetup != nil)
        if let run, let sudo, let fdesetup {
            #expect(sudo < run)
            #expect(fdesetup < run)
        }
    }

    @Test func fileVaultOffMeansAPlainRestartWithoutTheWarning() async {
        let report = HostStatus.recoveryReady(fileVault: .no, authRestart: .no)
        let check = ScriptedCheck(.ready(signIns: true), status: report, answeredAt: "workhorse")
        let f = RecoveryFixture(script: [check], answers: ["restart"])
        #expect(await f.recovery.restart(.recoverySample(), full: false, ui: f.ui) == 0)
        #expect(sshRemote(f.interactive.calls.first ?? []) == ["sudo shutdown -r now"])
        #expect(f.ui.said.contains("FileVault is off, so the Mac comes back to the login window by itself."))
        #expect(!f.ui.said.contains { $0.contains(lockedAfter) })
        #expect(!f.ui.said.contains(fdesetupSentence))
        #expect(f.ui.said.contains(sudoSentence))
    }

    @Test func aFullRestartWarnsAboutTheLockedDisk() async {
        let f = RecoveryFixture(state: .ready(signIns: true), answers: ["restart"])
        #expect(await f.recovery.restart(.recoverySample(), full: true, ui: f.ui) == 0)
        #expect(sshRemote(f.interactive.calls.first ?? []) == ["sudo shutdown -r now"])
        let sentence = "After this restart the disk will be locked. You unlock it with Unlock disk…"
        let warning = f.ui.indexOfSaid(sentence)
        let question = f.ui.indexOfFirstQuestion
        #expect(warning != nil && question != nil)
        if let warning, let question { #expect(warning < question) }
        #expect(!f.ui.said.contains(fdesetupSentence))
    }

    @Test func noAuthRestartSupportWarnsAboutTheLockedDisk() async {
        let report = HostStatus.recoveryReady(fileVault: .yes, authRestart: .no)
        let check = ScriptedCheck(.ready(signIns: true), status: report, answeredAt: "workhorse")
        let f = RecoveryFixture(script: [check], answers: ["restart"])
        _ = await f.recovery.restart(.recoverySample(), full: false, ui: f.ui)
        #expect(sshRemote(f.interactive.calls.first ?? []) == ["sudo shutdown -r now"])
        #expect(f.ui.said.contains("After this restart the disk will be locked. You unlock it with Unlock disk…"))
    }

    @Test func aLockedDiskOnAnOlderMacIsUnlockedAtTheMac() async {
        var report = HostStatus.recoveryReady()
        report.osVersion = "15.6"
        let check = ScriptedCheck(.ready(signIns: true), status: report, answeredAt: "workhorse")
        let f = RecoveryFixture(script: [check], answers: ["restart"])
        _ = await f.recovery.restart(.recoverySample(osVersion: "15.6"), full: true, ui: f.ui)
        #expect(f.ui.said.contains("After this restart the disk will be locked. You unlock it at the Mac."))
    }

    @Test func authRestartDoesNotWarnAboutALockedDisk() async {
        let f = RecoveryFixture(state: .ready(signIns: true), answers: ["restart"])
        _ = await f.recovery.restart(.recoverySample(), full: false, ui: f.ui)
        #expect(!f.ui.said.contains { $0.contains(lockedAfter) })
        #expect(!f.ui.said.contains { $0.contains("FileVault is off") })
    }

    @Test func restartArgvRunsTheCommandInATerminal() {
        let w = Workhorse.sample(id: "mbp", user: "alex")
        let recovery = RecoveryFixture(state: .ready(signIns: true)).recovery
        let auth = recovery.restartArgv(for: w, address: "workhorse", authRestart: true)
        let plain = recovery.restartArgv(for: w, address: "workhorse", authRestart: false)
        #expect(sshTarget(auth) == "alex@workhorse")
        #expect(sshRemote(auth) == ["sudo fdesetup authrestart"])
        #expect(sshRemote(plain) == ["sudo shutdown -r now"])
        #expect(auth.contains("-t") && auth.contains("StrictHostKeyChecking=yes"))
        #expect(!auth.contains("BatchMode=yes"))
    }

    @Test func restartNeedsAWorkhorseThatIsUp() async {
        let states: [WorkhorseState] = [.locked, .cantVerify, .cantReach(.nothingAnswers), .notSetUp(.deskServerDown)]
        for state in states {
            let f = RecoveryFixture(state: state, answers: ["restart"])
            let code = await f.recovery.restart(.recoverySample(), full: false, ui: f.ui)
            #expect(code == 1)
            #expect(f.interactive.calls.isEmpty)
            #expect(f.ui.asked.isEmpty)
            #expect(f.ui.said.first?.hasPrefix("MacBook Pro · ") == true)
        }
    }

    @Test func restartStopsWhenTheKeyIsMissing() async throws {
        let paths = try temporaryPathsWithoutKey()
        let f = RecoveryFixture(state: .ready(signIns: true), answers: ["restart"], paths: paths)
        let code = await f.recovery.restart(.recoverySample(), full: false, ui: f.ui)
        #expect(code == 1)
        #expect(f.checker.checks == 0)
        #expect(f.interactive.calls.isEmpty)
        #expect(f.ui.said.contains { $0.contains("Your ssh key is locked") })
    }

    @Test func aFailedRestartLeavesTheTabOpen() async {
        let f = RecoveryFixture(state: .ready(signIns: true), answers: ["restart"], sshExitCodes: [1])
        let code = await f.recovery.restart(.recoverySample(), full: false, ui: f.ui)
        #expect(code == 1)
        #expect(f.ui.waits == 1)
    }

    // MARK: screen

    @Test func screenSharingGoesToTheAddressThatAnswered() {
        let w = Workhorse.recoverySample()
        let r = CheckResult.sample(.waitingForLogin, workhorse: w, answeredAt: "192.168.1.20")
        #expect(Recovery.screenSharingURL(for: r)?.absoluteString == "vnc://alex@192.168.1.20")
        let fromLocal = CheckResult.sample(.ready(signIns: true), workhorse: w, answeredAt: "workhorse.local")
        #expect(Recovery.screenSharingURL(for: fromLocal)?.absoluteString == "vnc://alex@workhorse.local")
    }

    @Test func screenSharingKeepsAnOddUserNameInItsPlace() throws {
        let w = Workhorse.sample(user: "a@b/c d:e")
        let r = CheckResult.sample(.waitingForLogin, workhorse: w, answeredAt: "192.168.1.20")
        let url = try #require(Recovery.screenSharingURL(for: r))
        let parts = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(parts.scheme == "vnc")
        #expect(parts.host == "192.168.1.20")
        #expect(parts.user == "a@b/c d:e")
        #expect(parts.path.isEmpty)
    }

    @Test func screenSharingNeedsAnAddressThatAnswered() {
        #expect(Recovery.screenSharingURL(for: .sample(.cantReach(.nothingAnswers))) == nil)
        let changed = CheckResult.sample(.cantVerify, answeredAt: "192.168.1.20")
        #expect(Recovery.screenSharingURL(for: changed) == nil)
    }

    @Test func screenOpensTheURLAndSaysWhere() async {
        let f = RecoveryFixture(state: .waitingForLogin)
        let opener = FakeRunner { _ in FakeRunner.ok() }
        let code = await f.recovery.screen(.recoverySample(), runner: opener, ui: f.ui)
        #expect(code == 0)
        let argv: [String] = opener.calls.first?.argv ?? []
        #expect(argv == ["/usr/bin/open", "vnc://alex@192.168.1.20"])
        #expect(f.ui.said.contains { $0.contains("192.168.1.20") })
    }

    @Test func screenOpensNothingWhenTheKeyDiffers() async {
        let f = RecoveryFixture(state: .cantVerify)
        let opener = FakeRunner { _ in FakeRunner.ok() }
        let code = await f.recovery.screen(.recoverySample(), runner: opener, ui: f.ui)
        #expect(code == 1)
        #expect(opener.calls.isEmpty)
        #expect(f.ui.said.contains { $0.contains("Don't type a password") })
        #expect(f.ui.waits == 1)
    }
}
