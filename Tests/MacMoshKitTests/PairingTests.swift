import Foundation
import Testing
@testable import MacMoshKit

private func mode(_ url: URL) throws -> Int {
    (try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int ?? -1) & 0o777
}

@Suite struct PairingTests {
    // MARK: the plan's named tests

    @Test func pairStopsWhenTheUserDoesNotTypeYes() async throws {
        let f = try PairingFixture(answers: ["no"])
        await #expect(throws: PairingError.declined) { try await f.pairing.pair("alex@workhorse", confirmedFingerprint: nil, ui: f.ui) }
        #expect(f.interactive.calls.isEmpty)
        #expect(try f.store.find("workhorse").paired == false)
    }

    @Test func theKeyHasNoPassphraseAndIsPrivate() async throws {
        let f = try PairingFixture(answers: [])
        try await f.keys.ensureIdentity()
        let key = f.paths.defaultIdentity
        #expect(try FileManager.default.attributesOfItem(atPath: key.path)[.posixPermissions] as? Int == 0o600)
        let r = await ProcessRunner().run("ssh-keygen", ["-y", "-P", "", "-f", key.path], environment: [:], stdin: nil, timeout: .seconds(10))
        #expect(r.exitCode == 0)
    }

    @Test func ensureIdentityNeverOverwrites() async throws {
        let f = try PairingFixture(answers: [])
        try FileManager.default.createDirectory(at: f.paths.sshDir, withIntermediateDirectories: true)
        // Something unusable at the key's path is still left alone.
        let unusable = Data("not a key\n".utf8)
        try unusable.write(to: f.paths.defaultIdentity)
        try await f.keys.ensureIdentity()
        #expect(try Data(contentsOf: f.paths.defaultIdentity) == unusable)
        let pub = f.paths.defaultIdentity.appendingPathExtension("pub")
        #expect(!FileManager.default.fileExists(atPath: pub.path))

        // A real key made earlier stays exactly as it was.
        let g = try PairingFixture(answers: [])
        try await g.keys.ensureIdentity()
        let first = try Data(contentsOf: g.paths.defaultIdentity)
        let firstPub = try Data(contentsOf: g.paths.defaultIdentity.appendingPathExtension("pub"))
        try await g.keys.ensureIdentity()
        #expect(try Data(contentsOf: g.paths.defaultIdentity) == first)
        #expect(try Data(contentsOf: g.paths.defaultIdentity.appendingPathExtension("pub")) == firstPub)
    }

    @Test func addPinsTheScannedKey() async throws {
        let f = try PairingFixture(answers: [])
        let w = try await f.pairing.add(target: "alex@workhorse", name: nil)
        #expect(w.id == "workhorse")
        #expect(w.name == "workhorse")
        #expect(w.user == "alex")
        #expect(w.mainAddress == "workhorse")
        #expect(w.hostKey == PairingSamples.hostKey)
        #expect(w.paired == false)
        #expect(try f.store.load() == [w])
        let pinned = try String(contentsOf: f.paths.knownHostsFile, encoding: .utf8)
        #expect(pinned == "macmosh-workhorse \(PairingSamples.hostKey)\n")
        let scans = f.runner.calls.map(\.argv).filter { $0.first == "ssh-keyscan" }
        #expect(scans.count == 1)
    }

    @Test func addRefusesADifferentKeyForAKnownAddress() async throws {
        let f = try PairingFixture(answers: [], scannedKey: PairingSamples.otherHostKey)
        let saved = Workhorse.sample(id: "mbp", name: "MacBook Pro", mainAddress: "workhorse",
                                     hostKey: PairingSamples.hostKey, paired: true)
        try f.store.upsert(saved)
        let listBefore = try Data(contentsOf: f.paths.workhorsesFile)
        let pinnedBefore = try Data(contentsOf: f.paths.knownHostsFile)
        await #expect(throws: PairingError.keyDiffers) { try await f.pairing.add(target: "alex@workhorse", name: nil) }
        await #expect(throws: PairingError.keyDiffers) { try await f.pairing.add(target: "alex@WORKHORSE", name: "Other") }
        #expect(try f.store.load() == [saved])
        #expect(try Data(contentsOf: f.paths.workhorsesFile) == listBefore)
        #expect(try Data(contentsOf: f.paths.knownHostsFile) == pinnedBefore)
    }

    @Test func addRejectsBadTargets() async throws {
        let f = try PairingFixture(answers: [])
        let targets = ["workhorse", "a b@c", "-oProxyCommand=x@y", "@workhorse", "alex@", "alex@-oProxyCommand=x",
                       "alex@work@horse", "alex@work\nhorse", "alex@work\thorse", ""]
        for target in targets {
            await #expect(throws: PairingError.badTarget(target), "target \(target)") {
                try await f.pairing.add(target: target, name: nil)
            }
        }
        #expect(f.runner.calls.isEmpty)
        #expect(try f.store.load().isEmpty)
    }

    @Test func pairSkipsTheQuestionWhenTheFingerprintWasConfirmed() async throws {
        let f = try PairingFixture(answers: ["no"])
        let fingerprint = try HostKeys.fingerprint(of: PairingSamples.hostKey)
        let w = try await f.pairing.pair("alex@workhorse", confirmedFingerprint: fingerprint, ui: f.ui)
        #expect(f.ui.asked.isEmpty)
        #expect(f.interactive.calls.count == 1)
        #expect(w.paired)

        // A confirmed fingerprint that doesn't match is no confirmation: the question is asked.
        let g = try PairingFixture(answers: ["no"])
        let other = try HostKeys.fingerprint(of: PairingSamples.otherHostKey)
        await #expect(throws: PairingError.declined) {
            try await g.pairing.pair("alex@workhorse", confirmedFingerprint: other, ui: g.ui)
        }
        #expect(g.ui.asked == ["Type yes if they match: "])
        #expect(g.interactive.calls.isEmpty)
    }

    @Test func pairUsesThePinnedKeyOptions() throws {
        let f = try PairingFixture(answers: [])
        let w = Workhorse.sample(id: "mbp", user: "alex", mainAddress: "workhorse")
        let argv = f.pairing.copyIDArgv(for: w)
        #expect(argv.first == "ssh-copy-id")
        #expect(argv.contains("StrictHostKeyChecking=yes"))
        #expect(argv.contains("HostKeyAlias=macmosh-mbp"))
        let iPositions = argv.indices.filter { argv[$0] == "-i" }
        #expect(iPositions.count == 1)
        let identity: String? = iPositions.first.map { argv[$0 + 1] }
        #expect(identity == f.paths.defaultIdentity.path + ".pub")
        let tail: [String] = Array(argv.suffix(2))
        let expectedTail: [String] = ["--", "alex@workhorse"]
        #expect(tail == expectedTail)
        let options: [String] = SSHInvocation.hostKeyOptions(for: w, paths: f.paths)
        let middle: [String] = Array(argv.dropFirst(3).dropLast(2))
        #expect(middle == options)
    }

    @Test func pairCreatesTheKeyWhenThereIsNone() async throws {
        let f = try PairingFixture(answers: ["yes"])
        #expect(!FileManager.default.fileExists(atPath: f.paths.sshDir.path))
        _ = try await f.pairing.pair("alex@workhorse", confirmedFingerprint: nil, ui: f.ui)
        #expect(f.ui.said.first == "Created MacMosh's own ssh key at \(f.paths.defaultIdentity.path).")
        #expect(try mode(f.paths.sshDir) == 0o700)
        #expect(try mode(f.paths.defaultIdentity) == 0o600)
        #expect(f.keys.identityState(for: .sample()) == .usable)

        // The second time, the key is there and nothing is said about it.
        let ui = ScriptedInteraction(answers: ["yes"])
        _ = try await f.pairing.pair("workhorse", confirmedFingerprint: nil, ui: ui)
        #expect(!ui.said.contains { $0.hasPrefix("Created") })
    }

    @Test func finishWaitsForAKeyOnlyOnFailure() {
        let ok = ScriptedInteraction()
        #expect(ok.finish(0, reason: nil) == 0)
        #expect(ok.waits == 0)
        #expect(ok.said.isEmpty)

        let failed = ScriptedInteraction()
        #expect(failed.finish(3, reason: "It didn't work. Run: macmosh pair workhorse") == 3)
        #expect(failed.waits == 1)
        #expect(failed.said == ["It didn't work. Run: macmosh pair workhorse"])
    }

    @Test func pairSaysWhoIsAskingBeforeThePassword() async throws {
        let saidAtCopy = Box<[String]?>(nil)
        let ui = Box<ScriptedInteraction?>(nil)
        let f = try PairingFixture(answers: ["yes"], onCopy: { _ in saidAtCopy.value = ui.value?.said })
        ui.value = f.ui
        _ = try await f.pairing.pair("alex@workhorse", confirmedFingerprint: nil, ui: f.ui)
        let sentence = "Next, ssh asks for the workhorse's password. You are typing into ssh; MacMosh can't see it."
        #expect(saidAtCopy.value?.last == sentence)
    }

    @Test func pairMarksPairedOnlyAfterTheKeyWorks() async throws {
        let denied = FakeRunner.failed(255, stderr: "alex@workhorse: Permission denied (publickey,password,keyboard-interactive).\n")
        let f = try PairingFixture(answers: ["yes"], probe: denied)
        await #expect(throws: PairingError.keyNotAccepted) {
            try await f.pairing.pair("alex@workhorse", confirmedFingerprint: nil, ui: f.ui)
        }
        #expect(f.interactive.calls.count == 1)
        let saved = try f.store.find("workhorse")
        #expect(saved.paired == false)
        #expect(saved.lastKeyAccepted == nil)

        let g = try PairingFixture(answers: ["yes"])
        let w = try await g.pairing.pair("alex@workhorse", confirmedFingerprint: nil, ui: g.ui)
        #expect(w.paired)
        #expect(w.lastKeyAccepted == PairingFixture.now)
        #expect(try g.store.find("workhorse") == w)
        // The check is a batch ssh with MacMosh's key, asking for the computer name.
        let probe: [String] = g.sshCalls.first ?? []
        #expect(probe.contains("BatchMode=yes"))
        #expect(probe.last == "scutil --get ComputerName")
        #expect(probe.contains(g.paths.defaultIdentity.path))
        #expect(g.ui.said.last == "Paired. Next: macmosh prepare workhorse --fix")
    }

    @Test func aNameTakenFromTheAddressBecomesTheComputerName() async throws {
        let f = try PairingFixture(answers: ["yes"])
        let w = try await f.pairing.pair("alex@workhorse", confirmedFingerprint: nil, ui: f.ui)
        #expect(w.name == PairingSamples.computerName)
        #expect(w.id == "workhorse")

        // A name the user chose is kept.
        let g = try PairingFixture(answers: ["yes"])
        _ = try await g.pairing.add(target: "alex@workhorse", name: "Studio")
        let named = try await g.pairing.pair("studio", confirmedFingerprint: nil, ui: g.ui)
        #expect(named.name == "Studio")
    }

    @Test func nothingInPairingMentionsAPasswordParameter() throws {
        let files = ["Sources/MacMoshKit/Setup/Pairing.swift", "Sources/MacMoshKit/Run/Interaction.swift",
                     "Sources/MacMoshKit/SSH/HostKeys.swift", "Sources/MacMoshKit/SSH/KeyManager.swift"]
        // A declared name (`let`, `var`, `func`, `case`) or a parameter or property label (`name:`)
        // that contains either word. The sentences MacMosh says about the password don't match.
        let pattern = #"\b(let|var|func|case)\s+\w*(password|passphrase)\w*|\b\w*(password|passphrase)\w*\s*:"#
        let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        for file in files {
            let source = try String(contentsOf: repoRoot().appendingPathComponent(file), encoding: .utf8)
            let range = NSRange(source.startIndex..., in: source)
            let found = regex.matches(in: source, range: range).compactMap { Range($0.range, in: source).map { String(source[$0]) } }
            #expect(found.isEmpty, "\(file): \(found)")
        }
        // The check itself catches what it is for.
        let bad = "func pair(password: String)\nlet passphraseText = x"
        #expect(regex.numberOfMatches(in: bad, range: NSRange(bad.startIndex..., in: bad)) == 2)
    }

    // MARK: more

    @Test func pairSaysEachLineInOrder() async throws {
        let f = try PairingFixture(answers: ["yes"])
        _ = try await f.pairing.pair("alex@workhorse", confirmedFingerprint: nil, ui: f.ui)
        let fingerprint = try HostKeys.fingerprint(of: PairingSamples.hostKey)
        let expected: [String] = [
            "Created MacMosh's own ssh key at \(f.paths.defaultIdentity.path).",
            "This installs MacMosh's own ssh key on alex@workhorse, so MacMosh can check on that Mac without a password.",
            "Its key fingerprint is: \(fingerprint)",
            "At the workhorse, run this and compare: ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub",
            "Next, ssh asks for the workhorse's password. You are typing into ssh; MacMosh can't see it.",
            "Paired. Next: macmosh prepare workhorse --fix",
        ]
        #expect(f.ui.said == expected)
        #expect(f.ui.asked == ["Type yes if they match: "])
        let copy: [String] = f.interactive.calls.first ?? []
        #expect(copy == f.pairing.copyIDArgv(for: try f.store.find("workhorse")))
    }

    @Test func pairAcceptsYesInAnyCaseAndNothingElse() async throws {
        for answer in [" Yes ", "YES"] {
            let f = try PairingFixture(answers: [answer])
            let w = try await f.pairing.pair("alex@workhorse", confirmedFingerprint: nil, ui: f.ui)
            #expect(w.paired, "answer \(answer)")
        }
        for answer in ["", "y", "yes please", "ok"] {
            let f = try PairingFixture(answers: [answer])
            await #expect(throws: PairingError.declined, "answer \(answer)") {
                try await f.pairing.pair("alex@workhorse", confirmedFingerprint: nil, ui: f.ui)
            }
            #expect(f.interactive.calls.isEmpty)
        }
    }

    @Test func pairStopsWhenTheCopyFails() async throws {
        let f = try PairingFixture(answers: ["yes"], copyExitCodes: [1])
        await #expect(throws: PairingError.copyFailed(1)) {
            try await f.pairing.pair("alex@workhorse", confirmedFingerprint: nil, ui: f.ui)
        }
        #expect(f.sshCalls.isEmpty)
        #expect(try f.store.find("workhorse").paired == false)
    }

    @Test func pairNeverReplacesAPinnedKey() async throws {
        let f = try PairingFixture(answers: ["yes"], scannedKey: PairingSamples.otherHostKey)
        let saved = Workhorse.sample(id: "mbp", mainAddress: "workhorse", hostKey: PairingSamples.hostKey, paired: false)
        try f.store.upsert(saved)
        await #expect(throws: PairingError.keyDiffers) {
            try await f.pairing.pair("alex@workhorse", confirmedFingerprint: nil, ui: f.ui)
        }
        #expect(f.interactive.calls.isEmpty)
        #expect(try f.store.load() == [saved])
    }

    @Test func pairOfASavedWorkhorseShowsThePinnedKeyWithoutScanning() async throws {
        let f = try PairingFixture(answers: ["yes"], scannedKey: PairingSamples.otherHostKey)
        try f.store.upsert(.sample(id: "mbp", name: "MacBook Pro", mainAddress: "workhorse",
                                   hostKey: PairingSamples.hostKey, paired: false))
        let w = try await f.pairing.pair("mbp", confirmedFingerprint: nil, ui: f.ui)
        #expect(w.paired)
        #expect(w.name == "MacBook Pro")
        #expect(f.ui.said.contains("Its key fingerprint is: \(try HostKeys.fingerprint(of: PairingSamples.hostKey))"))
        #expect(!f.runner.calls.contains { $0.argv.first == "ssh-keyscan" })
    }

    @Test func pairWithAKeyOfTheUsersOwnCreatesNothing() async throws {
        let f = try PairingFixture(answers: ["yes"])
        let other = f.paths.sshDir.appendingPathComponent("id_other").path
        try f.store.upsert(.sample(id: "mbp", mainAddress: "workhorse", hostKey: PairingSamples.hostKey,
                                   paired: false, identityFile: other))
        await #expect(throws: PairingError.identityUnusable(path: other)) {
            try await f.pairing.pair("mbp", confirmedFingerprint: nil, ui: f.ui)
        }
        #expect(!FileManager.default.fileExists(atPath: f.paths.defaultIdentity.path))
        #expect(f.interactive.calls.isEmpty)
        #expect(f.sshCalls.isEmpty)
    }

    @Test func pairStopsWhenItsOwnKeyIsUnusable() async throws {
        let f = try PairingFixture(answers: ["yes"])
        try FileManager.default.createDirectory(at: f.paths.sshDir, withIntermediateDirectories: true)
        try Data("not a key\n".utf8).write(to: f.paths.defaultIdentity)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: f.paths.defaultIdentity.path)
        await #expect(throws: PairingError.identityUnusable(path: f.paths.defaultIdentity.path)) {
            try await f.pairing.pair("alex@workhorse", confirmedFingerprint: nil, ui: f.ui)
        }
        #expect(f.interactive.calls.isEmpty)
        #expect(try Data(contentsOf: f.paths.defaultIdentity) == Data("not a key\n".utf8))
    }

    @Test func addKeepsAKnownAddressWithTheSameKey() async throws {
        let f = try PairingFixture(answers: [])
        let saved = Workhorse.sample(id: "mbp", name: "MacBook Pro", mainAddress: "workhorse",
                                     hostKey: PairingSamples.hostKey, paired: true)
        try f.store.upsert(saved)
        let listBefore = try Data(contentsOf: f.paths.workhorsesFile)
        let w = try await f.pairing.add(target: "alex@workhorse", name: nil)
        #expect(w == saved)
        #expect(try Data(contentsOf: f.paths.workhorsesFile) == listBefore)
    }

    @Test func addNamesAnIPAddressWhole() async throws {
        let f = try PairingFixture(answers: [])
        let w = try await f.pairing.add(target: "alex@192.168.1.20", name: nil)
        #expect(w.name == "192.168.1.20")
        #expect(w.id == "192-168-1-20")
        let named = try await f.pairing.add(target: "alex@workhorse.local", name: "My Studio")
        #expect(named.id == "my-studio")
        #expect(named.name == "My Studio")
    }

    @Test func publicKeyBlobIsTheBase64Field() async throws {
        let f = try PairingFixture(answers: [])
        try await f.keys.ensureIdentity()
        let pub = try String(contentsOf: f.paths.defaultIdentity.appendingPathExtension("pub"), encoding: .utf8)
        let blob = try f.keys.publicKeyBlob(for: .sample())
        #expect(pub.hasPrefix("ssh-ed25519 \(blob) "))
        #expect(Data(base64Encoded: blob) != nil)
        let comment = KeyManager.keyComment(hostName: ProcessInfo.processInfo.hostName)
        #expect(pub.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix(" " + comment))
    }

    @Test func keyCommentNamesThisMac() {
        #expect(KeyManager.keyComment(hostName: "Alexs-MacBook-Pro.local") == "macmosh@Alexs-MacBook-Pro")
        #expect(KeyManager.keyComment(hostName: "alex's mac (2).lan") == "macmosh@alexsmac2")
        #expect(KeyManager.keyComment(hostName: "") == "macmosh@mac")
        #expect(KeyManager.keyComment(hostName: "Café") == "macmosh@Caf")
    }

    @Test func tailscaleStatusListsTheDevices() async throws {
        let json = try fixture("tailscale/status.json")
        let app = SystemHints.tailscaleAppPath
        let runner = FakeRunner { _ in FakeRunner.ok(json) }
        let hints = SystemHints(runner: runner, isExecutable: { $0 == app }, searchPath: "/usr/bin:/bin", ownAddresses: { [] })
        let status = await hints.tailscaleStatus()
        #expect(status?.running == true)
        #expect(status?.peers.count == 2)
        let argv: [String] = runner.calls.first?.argv ?? []
        let expected: [String] = [app, "status", "--json"]
        #expect(argv == expected)

        let none = SystemHints(runner: runner, isExecutable: { _ in false }, searchPath: "/usr/bin:/bin", ownAddresses: { [] })
        #expect(await none.tailscaleStatus() == nil)
        let slow = FakeRunner { _ in CommandResult(exitCode: -1, stdout: "", stderr: "", timedOut: true) }
        let timedOut = SystemHints(runner: slow, isExecutable: { $0 == app }, searchPath: "/usr/bin:/bin", ownAddresses: { [] })
        #expect(await timedOut.tailscaleStatus() == nil)
        let garbled = FakeRunner { _ in FakeRunner.ok("The Tailscale GUI failed to start\n") }
        let unreadable = SystemHints(runner: garbled, isExecutable: { $0 == app }, searchPath: "/usr/bin:/bin", ownAddresses: { [] })
        #expect(await unreadable.tailscaleStatus() == nil)
    }

    @Test func chooseTargetOffersTheMacsOnTailscale() throws {
        let status = try TailscaleStatus.parse(json: Data(fixture("tailscale/status.json").utf8))
        let ui = ScriptedInteraction(answers: ["1", ""])
        #expect(Pairing.chooseTarget(ui: ui, tailscale: status, currentUser: "alex") == "alex@workhorse.example-tailnet.ts.net")
        #expect(ui.said.contains { $0.contains("1. Spare MacBook Pro") })
        #expect(!ui.said.contains { $0.contains("media-box") })
        #expect(ui.asked.last == "User name on the workhorse [alex]: ")

        let typed = ScriptedInteraction(answers: ["192.168.1.20", "sam"])
        #expect(Pairing.chooseTarget(ui: typed, tailscale: status, currentUser: "alex") == "sam@192.168.1.20")
        let whole = ScriptedInteraction(answers: ["sam@studio"])
        #expect(Pairing.chooseTarget(ui: whole, tailscale: nil, currentUser: "alex") == "sam@studio")
        #expect(whole.asked == ["Workhorse address: "])
        let nothing = ScriptedInteraction(answers: [""])
        #expect(Pairing.chooseTarget(ui: nothing, tailscale: status, currentUser: "alex") == nil)
        let outOfRange = ScriptedInteraction(answers: ["7"])
        #expect(Pairing.chooseTarget(ui: outOfRange, tailscale: status, currentUser: "alex") == nil)
    }

    @Test func everyErrorSaysWhatToDoNext() {
        let errors: [Error] = [
            PairingError.badTarget("workhorse"), PairingError.keyDiffers, PairingError.declined,
            PairingError.copyFailed(1), PairingError.keyNotAccepted, PairingError.identityUnusable(path: "/k"),
            HostKeyError.noKey(address: "workhorse"), HostKeyError.malformed, StoreError.notFound("x"),
        ]
        for error in errors {
            let text = Pairing.explain(error, target: "alex@workhorse")
            #expect(!text.isEmpty)
            #expect(text.contains("Run:") || text.contains("Check") || text.contains("Stop"), "\(error): \(text)")
        }
        #expect(Pairing.explain(PairingError.keyDiffers, target: "alex@workhorse").contains("Don't type a password"))
    }
}
