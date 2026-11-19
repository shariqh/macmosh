import Foundation
import Testing
@testable import MacMoshKit

private let uninstallRemote = "~/.macmosh/macmosh-host uninstall --key \(sampleKeyBlob)"

@Suite struct RemovalTests {
    @Test func removeSendsOnlyThisMacsKey() async throws {
        let f = try RemovalFixture(answers: ["remove"],
                                   publicKeyBlob: "AAAAC3NzaC1lZDI1NTE5AAAAIHk0aW5nZXhhbXBsZWtleWJsb2JleGFtcGxla2V5YmxvYg==")
        try await f.removal.remove(.sample(id: "mbp"), forgetOnly: false, ui: f.ui)
        #expect(f.runner.calls.last?.argv.last ==
            "~/.macmosh/macmosh-host uninstall --key AAAAC3NzaC1lZDI1NTE5AAAAIHk0aW5nZXhhbXBsZWtleWJsb2JleGFtcGxla2V5YmxvYg==")
        #expect(throws: StoreError.self) { try f.store.find("mbp") }
    }

    @Test func removeIsOneBatchSSHCallAtTheAddressThatAnswered() async throws {
        let f = try RemovalFixture(answers: ["remove"], check: .usual(.waitingForLogin))
        try await f.removal.remove(.sample(id: "mbp"), forgetOnly: false, ui: f.ui)
        #expect(f.runner.calls.count == 1)
        let argv = try #require(f.runner.calls.first?.argv)
        #expect(argv.first == "ssh")
        #expect(argv.contains("BatchMode=yes"))
        #expect(!argv.contains("-t"))
        #expect(sshTarget(argv) == "alex@192.168.1.20")
        #expect(sshRemote(argv) == [uninstallRemote])
        #expect(argv.contains("StrictHostKeyChecking=yes"))
    }

    @Test func removeListsTheSixThingsFirst() async throws {
        let f = try RemovalFixture(answers: ["remove"])
        try await f.removal.remove(.sample(id: "mbp"), forgetOnly: false, ui: f.ui)
        #expect(Removal.whatIsRemoved.count == 6)
        let question = try #require(f.ui.indexOfFirstQuestion)
        let run = try #require(f.ui.firstIndex { if case .said(let s) = $0 { return s.contains("is off MacBook Pro") } else { return false } })
        for item in Removal.whatIsRemoved {
            let at = try #require(f.ui.indexOfSaid(item))
            #expect(at < question)
        }
        #expect(question < run)
        #expect(f.ui.asked == ["Type remove to go ahead: "])
    }

    @Test func theSixThingsAreDesign711() {
        let text = Removal.whatIsRemoved.joined(separator: "\n")
        for part in ["macmosh-host", "tmux.conf", "desks.tsv", "host.log",
                     "io.github.shariqh.macmosh.host.plist", "authorized_keys"] {
            #expect(text.contains(part))
        }
    }

    @Test func removeNeedsTheWord() async throws {
        for answer in ["", "yes", "Remove", "remove it", "no"] {
            let f = try RemovalFixture(answers: [answer])
            await #expect(throws: RemovalError.self) {
                try await f.removal.remove(.sample(id: "mbp"), forgetOnly: false, ui: f.ui)
            }
            #expect(f.runner.calls.isEmpty)
            #expect(f.stillListed)
            #expect(f.ui.waits == 1)
        }
    }

    @Test func theWordWithSpacesAroundItCounts() async throws {
        let f = try RemovalFixture(answers: [" remove \n"])
        try await f.removal.remove(.sample(id: "mbp"), forgetOnly: false, ui: f.ui)
        #expect(!f.stillListed)
    }

    @Test func yesSkipsTheQuestion() async throws {
        let f = try RemovalFixture()
        try await f.removal.remove(.sample(id: "mbp"), forgetOnly: false, skipQuestion: true, ui: f.ui)
        #expect(f.ui.asked.isEmpty)
        #expect(f.runner.calls.count == 1)
        #expect(!f.stillListed)
    }

    @Test func removeListsPowerChanges() async throws {
        let changes = ["sudo pmset -c sleep 0 womp 1", "sudo pmset -a autorestart 1"]
        let f = try RemovalFixture(answers: ["remove"], workhorse: .sample(id: "mbp", powerChanges: changes))
        try await f.removal.remove(.sample(id: "mbp", powerChanges: changes), forgetOnly: false, ui: f.ui)
        let sentence = try #require(f.ui.indexOfSaid("Power settings changed through MacMosh, in case you want to put them back:"))
        let first = try #require(f.ui.indexOfSaid(changes[0]))
        let second = try #require(f.ui.indexOfSaid(changes[1]))
        #expect(sentence < first && first < second)
        let uninstalled = try #require(f.ui.indexOfSaid("is off MacBook Pro"))
        #expect(uninstalled < sentence)
    }

    @Test func noPowerChangesMeansNoSentence() async throws {
        let f = try RemovalFixture(answers: ["remove"])
        try await f.removal.remove(.sample(id: "mbp"), forgetOnly: false, ui: f.ui)
        #expect(f.ui.indexOfSaid("Power settings changed") == nil)
    }

    // MARK: Forget only

    @Test func forgetOnlyRunsNoSSH() async throws {
        let changes = ["sudo pmset -a autorestart 1"]
        let f = try RemovalFixture(answers: ["remove"], workhorse: .sample(id: "mbp", powerChanges: changes))
        try await f.removal.remove(.sample(id: "mbp", powerChanges: changes), forgetOnly: true, ui: f.ui)
        #expect(f.runner.calls.isEmpty)
        #expect(f.checker.checks == 0)
        #expect(!f.stillListed)
        #expect(f.ui.indexOfSaid(changes[0]) != nil)
        // It says nothing on the workhorse changes, and doesn't list the six things as if they went.
        #expect(f.ui.indexOfSaid("Nothing on MacBook Pro changes") != nil)
        #expect(f.ui.indexOfSaid(Removal.whatIsRemoved[0]) == nil)
    }

    @Test func forgetOnlyStillAsksAndNeedsTheWord() async throws {
        let f = try RemovalFixture(answers: ["nope"])
        await #expect(throws: RemovalError.self) {
            try await f.removal.remove(.sample(id: "mbp"), forgetOnly: true, ui: f.ui)
        }
        #expect(f.stillListed)
    }

    @Test func forgetOnlyNeedsNoKeyAtAll() async throws {
        let f = try RemovalFixture(answers: ["remove"], writePublicKeyFile: false, breakTheKey: true)
        try await f.removal.remove(.sample(id: "mbp"), forgetOnly: true, ui: f.ui)
        #expect(!f.stillListed)
    }

    // MARK: Stops

    @Test func aFailedUninstallKeepsTheWorkhorse() async throws {
        let f = try RemovalFixture(answers: ["remove"], ssh: FakeRunner.failed(2, stderr: "macmosh-host: the key is too short\n"))
        await #expect(throws: RemovalError.self) {
            try await f.removal.remove(.sample(id: "mbp"), forgetOnly: false, ui: f.ui)
        }
        #expect(f.stillListed)
        #expect(f.ui.said.contains { $0.contains("still in your list") && $0.contains("--forget-only") })
        #expect(f.ui.waits == 1)
    }

    @Test func anUninstallThatTimesOutKeepsTheWorkhorse() async throws {
        let f = try RemovalFixture(answers: ["remove"],
                                   ssh: CommandResult(exitCode: 255, stdout: "", stderr: "", timedOut: true))
        await #expect(throws: RemovalError.self) {
            try await f.removal.remove(.sample(id: "mbp"), forgetOnly: false, ui: f.ui)
        }
        #expect(f.stillListed)
    }

    @Test func anUnreachableWorkhorseIsKeptAndForgetOnlyIsOffered() async throws {
        let states: [WorkhorseState] = [.cantReach(.tailscaleOff), .cantVerify, .locked,
                                        .notSetUp(.notPaired), .notSetUp(.hostScriptMissing)]
        for state in states {
            let f = try RemovalFixture(answers: ["remove"], check: .usual(state))
            await #expect(throws: RemovalError.self) {
                try await f.removal.remove(.sample(id: "mbp"), forgetOnly: false, ui: f.ui)
            }
            #expect(f.runner.calls.isEmpty)   // no ssh beyond the check, which is scripted
            #expect(f.stillListed)
            #expect(f.ui.said.contains { $0.contains("macmosh remove mbp --forget-only") })
            #expect(f.ui.waits == 1)
        }
    }

    @Test func removeStopsWhenTheKeyIsLockedAndMakesNoSSHCall() async throws {
        let f = try RemovalFixture(answers: ["remove"], breakTheKey: true)
        await #expect(throws: RemovalError.self) {
            try await f.removal.remove(.sample(id: "mbp"), forgetOnly: false, ui: f.ui)
        }
        #expect(f.runner.calls.isEmpty)
        #expect(f.checker.checks == 0)
        #expect(f.ui.asked.isEmpty)
        #expect(f.ui.said.contains("MacBook Pro · Your ssh key is locked"))
        #expect(f.stillListed)
    }

    @Test func removeStopsWhenThereIsNoPublicKeyFile() async throws {
        let f = try RemovalFixture(answers: ["remove"], writePublicKeyFile: false)
        await #expect(throws: RemovalError.self) {
            try await f.removal.remove(.sample(id: "mbp"), forgetOnly: false, ui: f.ui)
        }
        #expect(f.runner.calls.isEmpty)
        #expect(f.stillListed)
    }

    @Test func aWorkhorseThatAnsweredWithoutAScriptIsStillRemovable() async throws {
        // An old script, or a report that was cut off: the script is there, so try.
        for problem in [SetupProblem.hostScriptOutdated, .unreadableReport, .deskServerDown] {
            let f = try RemovalFixture(answers: ["remove"], check: .usual(.notSetUp(problem)))
            try await f.removal.remove(.sample(id: "mbp"), forgetOnly: false, ui: f.ui)
            #expect(f.runner.calls.count == 1)
            #expect(!f.stillListed)
        }
    }

    @Test func otherWorkhorsesStayInTheList() async throws {
        let f = try RemovalFixture(answers: ["remove"])
        try f.store.upsert(.sample(id: "air", name: "Air"))
        try await f.removal.remove(.sample(id: "mbp"), forgetOnly: false, ui: f.ui)
        #expect(try f.store.load().map(\.id) == ["air"])
    }
}
