import Foundation
import Testing
@testable import MacMoshKit

/// A refusal that still offers keys, as a workhorse that is up and logged in answers.
private let keysOffered = ["publickey", "password", "keyboard-interactive"]

/// The time a key last worked. Only whether it is set matters to the resolver.
private let someTimeAgo = Date(timeIntervalSince1970: 1_800_000_000)

private func resolve(_ probes: ProbeSet,
                     status: Result<HostStatus, HostStatusError>? = nil,
                     workhorse: Workhorse = .sample(),
                     hints: Hints = .allFine,
                     identityUsable: Bool = true) -> WorkhorseState {
    StateResolver.resolve(workhorse: workhorse, probes: probes, status: status,
                          hints: hints, identityUsable: identityUsable)
}

/// Nothing answered at either address.
private let silence = ProbeSet(main: .timedOut, home: .timedOut, local: nil)

@Suite struct StateResolverTests {
    // MARK: the plan's named tests

    @Test func anyChangedKeyMeansCantVerify() {
        let probes = ProbeSet(main: .ok(stdout: ""), home: .hostKeyChanged, local: nil)
        #expect(StateResolver.resolve(workhorse: .sample(), probes: probes, status: .success(.sampleReady),
                                      hints: .allFine, identityUsable: true) == .cantVerify)
    }

    @Test func passwordOnlyAtTheHomeAddressMeansLocked() {
        let probes = ProbeSet(main: .timedOut, home: .authDenied(methods: ["password", "keyboard-interactive"]), local: nil)
        #expect(StateResolver.resolve(workhorse: .sample(), probes: probes, status: nil,
                                      hints: .allFine, identityUsable: true) == .locked)
    }

    @Test func aMissingKeyIsNeverShownAsLocked() {
        let probes = ProbeSet(main: .timedOut, home: .authDenied(methods: ["password"]), local: nil)
        #expect(StateResolver.resolve(workhorse: .sample(), probes: probes, status: nil,
                                      hints: .allFine, identityUsable: false) == .notSetUp(.identityUnusable))
    }

    // MARK: rule 1: a different or unknown host key at any address

    @Test func anUnknownKeyMeansCantVerify() {
        let probes = ProbeSet(main: .hostKeyUnknown, home: nil, local: nil)
        #expect(resolve(probes, status: .success(.sampleReady)) == .cantVerify)
    }

    @Test func aChangedKeyAtTheLocalNameMeansCantVerify() {
        let probes = ProbeSet(main: .timedOut, home: .timedOut, local: .hostKeyChanged)
        #expect(resolve(probes) == .cantVerify)
    }

    @Test func aChangedKeyWinsOverAnUnusableKey() {
        let probes = ProbeSet(main: .identityUnusable(detail: "no such identity"), home: .hostKeyChanged, local: nil)
        #expect(resolve(probes, identityUsable: false) == .cantVerify)
    }

    @Test func aChangedKeyWinsOverAPasswordOnlyAnswer() {
        let probes = ProbeSet(main: .authDenied(methods: ["password"]), home: .hostKeyChanged, local: nil)
        #expect(resolve(probes, workhorse: .sample(lastKeyAccepted: someTimeAgo)) == .cantVerify)
    }

    // MARK: rule 2: the key on this Mac can't be used

    @Test func anUnusableKeySeenBySSHIsNotSetUp() {
        let probes = ProbeSet(main: .identityUnusable(detail: "bad permissions"), home: nil, local: nil)
        #expect(resolve(probes) == .notSetUp(.identityUnusable))
    }

    @Test func anUnusableKeyIsNotLockedEvenIfItWorkedBefore() {
        let probes = ProbeSet(main: .timedOut, home: .authDenied(methods: keysOffered), local: nil)
        let workhorse = Workhorse.sample(lastKeyAccepted: someTimeAgo)
        #expect(resolve(probes, workhorse: workhorse, identityUsable: false) == .notSetUp(.identityUnusable))
    }

    @Test func anUnusableKeyWinsOverAReport() {
        let probes = ProbeSet(main: .ok(stdout: ""), home: nil, local: nil)
        #expect(resolve(probes, status: .success(.sampleReady), identityUsable: false) == .notSetUp(.identityUnusable))
    }

    // MARK: rule 3: the script isn't there

    @Test func scriptMissing() {
        let notFound = ProbeSet(main: .remoteFailed(exitCode: 127, stderr: "command not found"), home: nil, local: nil)
        let notRunnable = ProbeSet(main: .remoteFailed(exitCode: 126, stderr: "permission denied"), home: nil, local: nil)
        #expect(resolve(notFound) == .notSetUp(.hostScriptMissing))
        #expect(resolve(notRunnable) == .notSetUp(.hostScriptMissing))
    }

    @Test func scriptMissingAtTheHomeAddress() {
        let probes = ProbeSet(main: .timedOut, home: .remoteFailed(exitCode: 127, stderr: ""), local: nil)
        #expect(resolve(probes) == .notSetUp(.hostScriptMissing))
    }

    // MARK: rule 4: the script speaks another protocol

    @Test func scriptOutdated() {
        let probes = ProbeSet(main: .ok(stdout: ""), home: nil, local: nil)
        #expect(resolve(probes, status: .failure(.unsupportedProtocol(2))) == .notSetUp(.hostScriptOutdated))
    }

    // MARK: rule 4a: a report that can't be read

    @Test func aCutOffReportIsNeverReady() {
        let probes = ProbeSet(main: .ok(stdout: ""), home: nil, local: nil)
        #expect(resolve(probes, status: .failure(.truncated)) == .notSetUp(.unreadableReport))
    }

    @Test func noHeaderIsAnUnreadableReport() {
        let probes = ProbeSet(main: .ok(stdout: ""), home: nil, local: nil)
        #expect(resolve(probes, status: .failure(.noHeader)) == .notSetUp(.unreadableReport))
    }

    @Test func anOddExitCodeIsAnUnreadableReport() {
        let probes = ProbeSet(main: .remoteFailed(exitCode: 1, stderr: ""), home: nil, local: nil)
        #expect(resolve(probes) == .notSetUp(.unreadableReport))
    }

    @Test func anAnswerWithoutAReportIsUnreadable() {
        // ssh got through, and the caller has no report to show for it: never guess a state.
        let probes = ProbeSet(main: .ok(stdout: "macmosh-host\t1\t0.1.0\n"), home: nil, local: nil)
        #expect(resolve(probes, status: nil) == .notSetUp(.unreadableReport))
    }

    // MARK: rules 5 to 7: a report

    @Test func nobodyAtTheConsoleIsWaitingForLogin() {
        var report = HostStatus.sampleReady
        report.consoleUser = nil
        report.serverUp = false
        let probes = ProbeSet(main: .timedOut, home: .ok(stdout: ""), local: nil)
        #expect(resolve(probes, status: .success(report)) == .waitingForLogin)
    }

    @Test func serverDownWhileLoggedIn() {
        var report = HostStatus.sampleReady
        report.serverUp = false
        report.signIns = .unknown
        let probes = ProbeSet(main: .ok(stdout: ""), home: nil, local: nil)
        #expect(resolve(probes, status: .success(report)) == .notSetUp(.deskServerDown))
    }

    @Test func aFullReportIsReady() {
        let probes = ProbeSet(main: .ok(stdout: ""), home: nil, local: nil)
        #expect(resolve(probes, status: .success(.sampleReady)) == .ready(signIns: true))
    }

    @Test func keychainOffIsReadyWithSignInsOff() {
        var report = HostStatus.sampleReady
        report.signIns = .no
        let probes = ProbeSet(main: .ok(stdout: ""), home: nil, local: nil)
        #expect(resolve(probes, status: .success(report)) == .ready(signIns: false))
    }

    @Test func anUnknownSignInCheckIsNotShownAsWorking() {
        var report = HostStatus.sampleReady
        report.signIns = .unknown
        let probes = ProbeSet(main: .ok(stdout: ""), home: nil, local: nil)
        #expect(resolve(probes, status: .success(report)) == .ready(signIns: false))
    }

    // MARK: rule 8: no keys offered at any address

    @Test func passwordOnlyAtAHomeNetworkMainAddressIsLocked() {
        let probes = ProbeSet(main: .authDenied(methods: ["password"]), home: nil, local: nil)
        var hints = Hints.allFine
        hints.peerOnline = nil
        #expect(resolve(probes, hints: hints) == .locked)
    }

    @Test func passwordOnlyIsLockedEvenForAKeyThatNeverWorked() {
        let probes = ProbeSet(main: .timedOut, home: nil, local: .authDenied(methods: ["password"]))
        #expect(resolve(probes, workhorse: .sample(lastKeyAccepted: nil)) == .locked)
    }

    // MARK: rule 9: a refusal at a Tailscale address

    @Test func aRefusalAtATailscaleAddressIsNotLocked() {
        let probes = ProbeSet(main: .authDenied(methods: keysOffered), home: nil, local: nil)
        let workhorse = Workhorse.sample(lastKeyAccepted: someTimeAgo)
        #expect(resolve(probes, workhorse: workhorse) == .notSetUp(.notPaired))
    }

    @Test func aRefusalAtATailscaleAddressThatIsOfflineIsNotLocked() {
        let probes = ProbeSet(main: .authDenied(methods: keysOffered), home: nil, local: nil)
        var hints = Hints.allFine
        hints.peerOnline = false
        #expect(resolve(probes, workhorse: .sample(lastKeyAccepted: someTimeAgo), hints: hints) == .notSetUp(.notPaired))
    }

    @Test func aRefusalAtATailscaleAddressOfANewWorkhorseIsNotPaired() {
        let probes = ProbeSet(main: .authDenied(methods: keysOffered), home: nil, local: nil)
        #expect(resolve(probes, workhorse: .sample(paired: false, lastKeyAccepted: nil)) == .notSetUp(.notPaired))
    }

    // MARK: rule 10: a key that worked before is refused

    @Test func aKeyThatWorkedBeforeAndIsRefusedAtHomeIsLocked() {
        let probes = ProbeSet(main: .timedOut, home: .authDenied(methods: keysOffered), local: nil)
        let workhorse = Workhorse.sample(lastKeyAccepted: someTimeAgo)
        #expect(resolve(probes, workhorse: workhorse) == .locked)
    }

    @Test func aKeyThatWorkedBeforeAndIsRefusedAtAHomeNetworkMainAddressIsLocked() {
        let probes = ProbeSet(main: .authDenied(methods: keysOffered), home: nil, local: nil)
        var hints = Hints.allFine
        hints.peerOnline = nil
        #expect(resolve(probes, workhorse: .sample(lastKeyAccepted: someTimeAgo), hints: hints) == .locked)
    }

    // MARK: rule 11: a key that never worked is refused

    @Test func neverPairedIsNotLocked() {
        let probes = ProbeSet(main: .timedOut, home: .authDenied(methods: keysOffered), local: nil)
        let workhorse = Workhorse.sample(paired: false, lastKeyAccepted: nil)
        #expect(resolve(probes, workhorse: workhorse) == .notSetUp(.notPaired))
    }

    // MARK: rule 12: nothing answered, and the reason, first that applies

    @Test func tailscaleOffComesFirst() {
        let hints = Hints(tailscaleRunning: false, peerOnline: false, hasNetwork: false, otherVPN: true, atHome: false)
        #expect(resolve(silence, hints: hints) == .cantReach(.tailscaleOff))
    }

    @Test func thenNoNetwork() {
        let hints = Hints(tailscaleRunning: true, peerOnline: false, hasNetwork: false, otherVPN: true, atHome: false)
        #expect(resolve(silence, hints: hints) == .cantReach(.noNetwork))
    }

    @Test func thenAnotherVPN() {
        let hints = Hints(tailscaleRunning: true, peerOnline: false, hasNetwork: true, otherVPN: true, atHome: false)
        #expect(resolve(silence, hints: hints) == .cantReach(.otherVPN))
    }

    @Test func thenAwayAndOffline() {
        let hints = Hints(tailscaleRunning: true, peerOnline: false, hasNetwork: true, otherVPN: false, atHome: false)
        #expect(resolve(silence, hints: hints) == .cantReach(.awayAndOffline))
    }

    @Test func otherwiseNothingAnswers() {
        #expect(resolve(silence, hints: .allFine) == .cantReach(.nothingAnswers))
    }

    @Test func noTailscaleIsNotTailscaleOff() {
        let hints = Hints(tailscaleRunning: nil, peerOnline: nil, hasNetwork: true, otherVPN: false, atHome: false)
        #expect(resolve(silence, hints: hints) == .cantReach(.nothingAnswers))
    }

    @Test func anUnknownHomeNetworkIsNotAway() {
        let hints = Hints(tailscaleRunning: true, peerOnline: false, hasNetwork: true, otherVPN: false, atHome: nil)
        #expect(resolve(silence, hints: hints) == .cantReach(.nothingAnswers))
    }

    @Test func noAddressTriedIsCantReach() {
        #expect(resolve(ProbeSet(main: nil, home: nil, local: nil)) == .cantReach(.nothingAnswers))
    }

    @Test func otherFailuresAreCantReach() {
        let probes = ProbeSet(main: .unresolved, home: .refused, local: .unreachable(detail: "No route to host"))
        #expect(resolve(probes) == .cantReach(.nothingAnswers))
    }
}
