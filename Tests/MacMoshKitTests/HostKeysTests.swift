import Foundation
import Testing
@testable import MacMoshKit

@Suite struct HostKeysTests {
    // MARK: the plan's named tests

    @Test func fingerprintMatchesSSHKeygen() async throws {
        let dir = try temporaryFolder()
        _ = await ProcessRunner().run("ssh-keygen", ["-q", "-t", "ed25519", "-N", "", "-f", dir.appendingPathComponent("k").path],
                                      environment: [:], stdin: nil, timeout: .seconds(10))
        let pub = try String(contentsOf: dir.appendingPathComponent("k.pub"), encoding: .utf8)
        let listed = await ProcessRunner().run("ssh-keygen", ["-lf", dir.appendingPathComponent("k.pub").path],
                                               environment: [:], stdin: nil, timeout: .seconds(10))
        let hostKey = pub.split(separator: " ").prefix(2).joined(separator: " ")
        #expect(listed.stdout.contains(try HostKeys.fingerprint(of: hostKey)))
    }

    @Test func scanPicksTheKeyLine() async throws {
        let output = """
        # workhorse:22 SSH-2.0-OpenSSH_10.5
        # another comment

        workhorse \(PairingSamples.hostKey)
        workhorse \(PairingSamples.otherHostKey)

        """
        let runner = FakeRunner { _ in FakeRunner.ok(output) }
        let key = try await HostKeys.scan(address: "workhorse", runner: runner)
        #expect(key == PairingSamples.hostKey)
        let argv: [String] = runner.calls.first?.argv ?? []
        let expected: [String] = ["ssh-keyscan", "-T", "5", "-t", "ed25519", "workhorse"]
        #expect(argv == expected)
    }

    @Test func scanWithNoKeyThrows() async {
        let runner = FakeRunner { _ in FakeRunner.ok("# workhorse:22 SSH-2.0-OpenSSH_10.5\n") }
        await #expect(throws: HostKeyError.noKey(address: "workhorse")) {
            try await HostKeys.scan(address: "workhorse", runner: runner)
        }
        let silent = FakeRunner { _ in FakeRunner.failed(1) }
        await #expect(throws: HostKeyError.noKey(address: "workhorse")) {
            try await HostKeys.scan(address: "workhorse", runner: silent)
        }
    }

    // MARK: more

    @Test func scanAcceptsOnlyAnEd25519Key() async {
        let lines = [
            "workhorse ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC7",
            "workhorse ssh-ed25519 not*base64",
            "workhorse ssh-ed25519",
            // Base64 that decodes, but to something that isn't an ed25519 key.
            "workhorse ssh-ed25519 " + Data("hello, this is not a key".utf8).base64EncodedString(),
            // A real-looking blob behind the wrong type name.
            "workhorse ecdsa-sha2-nistp256 " + PairingSamples.hostKey.split(separator: " ")[1],
        ]
        for line in lines {
            let runner = FakeRunner { _ in FakeRunner.ok(line + "\n") }
            await #expect(throws: HostKeyError.malformed, "line \(line)") {
                try await HostKeys.scan(address: "workhorse", runner: runner)
            }
        }
    }

    @Test func scanPassesThePort() async throws {
        let runner = FakeRunner { _ in FakeRunner.ok("[workhorse]:2222 \(PairingSamples.hostKey)\n") }
        let key = try await HostKeys.scan(address: "workhorse", port: 2222, runner: runner)
        #expect(key == PairingSamples.hostKey)
        let argv: [String] = runner.calls.first?.argv ?? []
        let expected: [String] = ["ssh-keyscan", "-T", "5", "-t", "ed25519", "-p", "2222", "workhorse"]
        #expect(argv == expected)
    }

    @Test func scanNeverPassesAnAddressThatLooksLikeAnOption() async {
        let runner = FakeRunner { _ in FakeRunner.ok("x \(PairingSamples.hostKey)\n") }
        for address in ["-oProxyCommand=x", "", "a b"] {
            await #expect(throws: HostKeyError.noKey(address: address)) {
                try await HostKeys.scan(address: address, runner: runner)
            }
        }
        #expect(runner.calls.isEmpty)
    }

    @Test func fingerprintOfAMalformedKeyThrows() {
        #expect(throws: HostKeyError.malformed) { try HostKeys.fingerprint(of: "ssh-ed25519") }
        #expect(throws: HostKeyError.malformed) { try HostKeys.fingerprint(of: "ssh-ed25519 not*base64") }
        #expect(throws: HostKeyError.malformed) { try HostKeys.fingerprint(of: "") }
    }

    @Test func fingerprintHasNoPadding() throws {
        let fingerprint = try HostKeys.fingerprint(of: PairingSamples.hostKey)
        #expect(fingerprint.hasPrefix("SHA256:"))
        #expect(!fingerprint.hasSuffix("="))
        #expect(fingerprint.count == "SHA256:".count + 43)
        #expect(try HostKeys.fingerprint(of: PairingSamples.otherHostKey) != fingerprint)
    }

    @Test func compareCommandIsTheWorkhorsesOwnKey() {
        #expect(HostKeys.compareCommand == "ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub")
    }
}
