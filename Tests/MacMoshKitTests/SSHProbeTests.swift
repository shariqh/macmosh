import Foundation
import Testing
@testable import MacMoshKit

/// What OpenSSH 10 prints before anything else when the key exchange isn't post-quantum.
/// Harmless noise that comes ahead of the line that decides.
private let pqWarning = """
** WARNING: connection is not using a post-quantum key exchange algorithm.
** This session may be vulnerable to "store now, decrypt later" attacks.
** The server may need to be upgraded. See https://openssh.com/pq.html

"""

/// Every fixture under `Fixtures/ssh/`: ssh's answers when a connection fails.
private let failureFixtures = [
    "ssh/changed-key.txt", "ssh/unknown-key.txt", "ssh/timed-out.txt", "ssh/refused.txt", "ssh/unresolved.txt",
    "ssh/identity-bad-permissions.assumed.txt", "ssh/identity-missing.txt",
    "ssh/identity-wrong-passphrase.assumed.txt", "ssh/auth-denied.txt", "ssh/auth-denied-password-only.assumed.txt",
]

private func failed(_ exitCode: Int32 = 255, fixture name: String) throws -> CommandResult {
    FakeRunner.failed(exitCode, stderr: try fixture(name))
}

private func crlf(_ s: String) -> String { s.replacingOccurrences(of: "\n", with: "\r\n") }

@Suite struct SSHProbeTests {
    // MARK: the plan's named tests

    @Test func refusedSignInListsTheMethodsOffered() {
        let r = FakeRunner.failed(255, stderr: "alex@workhorse: Permission denied (publickey,password,keyboard-interactive).\n")
        #expect(SSHProbe.classify(r) == .authDenied(methods: ["publickey", "password", "keyboard-interactive"]))
    }

    @Test func aChangedKeyWinsOverEverythingElse() throws {
        let text = try fixture("ssh/changed-key.txt") + "alex@workhorse: Permission denied (publickey).\n"
        #expect(SSHProbe.classify(FakeRunner.failed(255, stderr: text)) == .hostKeyChanged)
    }

    @Test func aMissingScriptIsARemoteFailure() {
        let stderr = "zsh:1: no such file or directory: /Users/alex/.macmosh/macmosh-host\n"
        #expect(SSHProbe.classify(FakeRunner.failed(127, stderr: stderr)) == .remoteFailed(exitCode: 127, stderr: stderr))
    }

    // MARK: one test per row of the table, in order

    @Test func row1ChangedKeyIsHostKeyChanged() throws {
        #expect(SSHProbe.classify(try failed(fixture: "ssh/changed-key.txt")) == .hostKeyChanged)
        // Either sign alone is enough: a user's LogLevel may hide the banner but keep the last lines.
        #expect(SSHProbe.classify(FakeRunner.failed(255, stderr: "@    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @\n")) == .hostKeyChanged)
        #expect(SSHProbe.classify(FakeRunner.failed(255, stderr:
            "Host key for macmosh-mbp has changed and you have requested strict checking.\nHost key verification failed.\n")) == .hostKeyChanged)
    }

    @Test func row2NoKeyOnFileIsHostKeyUnknown() throws {
        #expect(SSHProbe.classify(try failed(fixture: "ssh/unknown-key.txt")) == .hostKeyUnknown)
    }

    /// At a quieter log level ssh prints only this line for a changed key. The cautious reading is
    /// "can't verify it".
    @Test func aBareVerificationFailureIsHostKeyChanged() {
        #expect(SSHProbe.classify(FakeRunner.failed(255, stderr: "Host key verification failed.\n")) == .hostKeyChanged)
        #expect(SSHProbe.classify(FakeRunner.failed(255, stderr: "Host key verification failed.\r\nalex@workhorse: Permission denied (publickey).\n"))
                == .hostKeyChanged)
        #expect(SSHProbe.classify(FakeRunner.failed(255, stderr: "ssh: connect to host workhorse port 22: Connection refused\nHost key verification failed.\n"))
                == .hostKeyChanged)
    }

    @Test func row3TimedOutConnectionIsTimedOut() throws {
        #expect(SSHProbe.classify(try failed(fixture: "ssh/timed-out.txt")) == .timedOut)
        #expect(SSHProbe.classify(FakeRunner.failed(255, stderr: "Connection timed out during banner exchange\n")) == .timedOut)
        // Stopped by MacMosh's own time limit, with nothing printed.
        #expect(SSHProbe.classify(CommandResult(exitCode: -1, stdout: "", stderr: "", timedOut: true)) == .timedOut)
    }

    @Test func row4RefusedConnectionIsRefused() throws {
        #expect(SSHProbe.classify(try failed(fixture: "ssh/refused.txt")) == .refused)
    }

    @Test func row5UnknownNameIsUnresolved() throws {
        #expect(SSHProbe.classify(try failed(fixture: "ssh/unresolved.txt")) == .unresolved)
    }

    @Test func row6UnusableKeyIsIdentityUnusable() throws {
        #expect(SSHProbe.classify(try failed(fixture: "ssh/identity-bad-permissions.assumed.txt"))
                == .identityUnusable(detail: "Load key \"/Users/alex/.ssh/macmosh_ed25519\": bad permissions"))
        #expect(SSHProbe.classify(FakeRunner.failed(255, stderr:
            "no such identity: /Users/alex/.ssh/macmosh_ed25519: No such file or directory\nalex@workhorse: Permission denied (publickey).\n"))
                == .identityUnusable(detail: "no such identity: /Users/alex/.ssh/macmosh_ed25519: No such file or directory"))
        #expect(SSHProbe.classify(try failed(fixture: "ssh/identity-wrong-passphrase.assumed.txt"))
                == .identityUnusable(detail: "Load key \"/Users/alex/.ssh/other_ed25519\": incorrect passphrase supplied to decrypt private key"))
        // The banner alone, without the "Load key" line, still counts.
        #expect(SSHProbe.classify(FakeRunner.failed(255, stderr: "@         WARNING: UNPROTECTED PRIVATE KEY FILE!          @\n"))
                == .identityUnusable(detail: "@         WARNING: UNPROTECTED PRIVATE KEY FILE!          @"))
    }

    /// ssh's warning when the `-i` file is missing. It then falls back to the user's default keys,
    /// so the call may be refused or may even sign in: neither counts.
    @Test func aMissingKeyFileIsIdentityUnusable() throws {
        let missing = "Warning: Identity file /Users/alex/.ssh/macmosh_ed25519 not accessible: No such file or directory."
        #expect(SSHProbe.classify(try failed(fixture: "ssh/identity-missing.txt")) == .identityUnusable(detail: missing))
        let text = try fixture("ssh/identity-missing.txt")
        #expect(SSHProbe.classify(FakeRunner.failed(255, stderr: text + "alex@workhorse: Permission denied (publickey).\n"))
                == .identityUnusable(detail: missing))
        #expect(SSHProbe.classify(CommandResult(exitCode: 0, stdout: "ok\n", stderr: text, timedOut: false))
                == .identityUnusable(detail: missing))
        // Both parts are needed: either alone is not this warning.
        #expect(SSHProbe.classify(FakeRunner.failed(255, stderr: "Identity file is fine\n")) == .unreachable(detail: "Identity file is fine"))
        #expect(SSHProbe.classify(FakeRunner.failed(255, stderr: "/tmp/x not accessible\n")) == .unreachable(detail: "/tmp/x not accessible"))
    }

    @Test func row7RefusedSignInIsAuthDenied() throws {
        #expect(SSHProbe.classify(try failed(fixture: "ssh/auth-denied.txt"))
                == .authDenied(methods: ["publickey", "password", "keyboard-interactive"]))
        // The locked screen's assumed answer: no publickey on offer.
        #expect(SSHProbe.classify(try failed(fixture: "ssh/auth-denied-password-only.assumed.txt"))
                == .authDenied(methods: ["password", "keyboard-interactive"]))
    }

    @Test func row8ExitZeroIsOk() {
        #expect(SSHProbe.classify(FakeRunner.ok("macmosh-host\t1\t0.1.0\nend\n")) == .ok(stdout: "macmosh-host\t1\t0.1.0\nend\n"))
    }

    @Test func row9Exit255WithNoKnownSignIsUnreachable() {
        let r = FakeRunner.failed(255, stderr: "kex_exchange_identification: read: Connection reset by peer\nConnection reset by 192.168.1.20 port 22\n")
        #expect(SSHProbe.classify(r) == .unreachable(detail: "Connection reset by 192.168.1.20 port 22"))
        #expect(SSHProbe.classify(FakeRunner.failed(255)) == .unreachable(detail: ""))
    }

    @Test func row10AnyOtherExitCodeIsARemoteFailure() {
        #expect(SSHProbe.classify(FakeRunner.failed(4, stderr: "macmosh-host: no such desk: web\n"))
                == .remoteFailed(exitCode: 4, stderr: "macmosh-host: no such desk: web\n"))
        // Stopped by cancelling, not by the time limit.
        #expect(SSHProbe.classify(CommandResult(exitCode: -1, stdout: "", stderr: "", timedOut: false))
                == .remoteFailed(exitCode: -1, stderr: ""))
    }

    // MARK: mixed and messy answers

    @Test func aChangedKeyWinsOverEveryOtherSign() throws {
        let changed = try fixture("ssh/changed-key.txt")
        for other in failureFixtures where other != "ssh/changed-key.txt" {
            let text = try fixture(other)
            for stderr in [changed + text, text + changed, pqWarning + text + changed] {
                #expect(SSHProbe.classify(FakeRunner.failed(255, stderr: stderr)) == .hostKeyChanged, "with \(other)")
                #expect(SSHProbe.classify(FakeRunner.failed(0, stderr: stderr)) == .hostKeyChanged, "with \(other), exit 0")
            }
        }
        #expect(SSHProbe.classify(CommandResult(exitCode: -1, stdout: "", stderr: changed, timedOut: true)) == .hostKeyChanged)
    }

    @Test func anUnknownKeyWinsOverEverythingButAChangedOne() throws {
        let unknown = try fixture("ssh/unknown-key.txt")
        for other in failureFixtures where other != "ssh/changed-key.txt" && other != "ssh/unknown-key.txt" {
            let text = try fixture(other)
            #expect(SSHProbe.classify(FakeRunner.failed(255, stderr: text + unknown)) == .hostKeyUnknown, "with \(other)")
        }
    }

    @Test func aFailureSignIsNeverOkWhateverTheExitCode() throws {
        for name in failureFixtures {
            for code: Int32 in [0, 1, 127, 255] {
                let outcome = SSHProbe.classify(FakeRunner.failed(code, stderr: try fixture(name)))
                if case .ok = outcome { Issue.record("\(name) with exit \(code) was read as ok") }
            }
        }
    }

    @Test func warningsBeforeTheDecidingLineDoNotChangeTheAnswer() throws {
        #expect(SSHProbe.classify(FakeRunner.failed(255, stderr: pqWarning + (try fixture("ssh/auth-denied.txt"))))
                == .authDenied(methods: ["publickey", "password", "keyboard-interactive"]))
        #expect(SSHProbe.classify(FakeRunner.failed(255, stderr: pqWarning + (try fixture("ssh/refused.txt")))) == .refused)
        #expect(SSHProbe.classify(FakeRunner.failed(255, stderr: pqWarning + (try fixture("ssh/unknown-key.txt")))) == .hostKeyUnknown)
        #expect(SSHProbe.classify(CommandResult(exitCode: 0, stdout: "ok\n", stderr: pqWarning, timedOut: false)) == .ok(stdout: "ok\n"))
        #expect(SSHProbe.classify(FakeRunner.failed(255, stderr: pqWarning + "Connection closed by 192.168.1.20 port 22\n"))
                == .unreachable(detail: "Connection closed by 192.168.1.20 port 22"))
    }

    @Test func windowsLineEndingsReadTheSame() throws {
        #expect(SSHProbe.classify(FakeRunner.failed(255, stderr: crlf(try fixture("ssh/changed-key.txt")))) == .hostKeyChanged)
        #expect(SSHProbe.classify(FakeRunner.failed(255, stderr: crlf(try fixture("ssh/unknown-key.txt")))) == .hostKeyUnknown)
        #expect(SSHProbe.classify(FakeRunner.failed(255, stderr: crlf(try fixture("ssh/auth-denied.txt"))))
                == .authDenied(methods: ["publickey", "password", "keyboard-interactive"]))
        #expect(SSHProbe.classify(FakeRunner.failed(255, stderr: crlf(try fixture("ssh/identity-bad-permissions.assumed.txt"))))
                == .identityUnusable(detail: "Load key \"/Users/alex/.ssh/macmosh_ed25519\": bad permissions"))
        #expect(SSHProbe.classify(FakeRunner.failed(255, stderr: "Connection closed by 192.168.1.20 port 22\r\n"))
                == .unreachable(detail: "Connection closed by 192.168.1.20 port 22"))
    }

    @Test func signsInTheRemoteCommandsStdoutDoNotCount() throws {
        // The remote command printed ssh's phrases; only ssh's own stderr decides.
        for name in failureFixtures {
            let out = try fixture(name)
            #expect(SSHProbe.classify(CommandResult(exitCode: 0, stdout: out, stderr: "", timedOut: false)) == .ok(stdout: out),
                    "\(name) on stdout")
            #expect(SSHProbe.classify(CommandResult(exitCode: 3, stdout: out, stderr: "", timedOut: false))
                    == .remoteFailed(exitCode: 3, stderr: ""), "\(name) on stdout, exit 3")
        }
    }

    @Test func theMethodListIsReadFromSshsOwnLine() {
        // A remote line that merely says "Permission denied" (no bracket) is not a refused sign-in.
        #expect(SSHProbe.classify(FakeRunner.failed(1, stderr: "ls: /private: Permission denied\n"))
                == .remoteFailed(exitCode: 1, stderr: "ls: /private: Permission denied\n"))
        // Spaces and an empty entry are dropped.
        #expect(SSHProbe.classify(FakeRunner.failed(255, stderr: "alex@workhorse: Permission denied (publickey, ,password).\n"))
                == .authDenied(methods: ["publickey", "password"]))
        // The last refusal is the one ssh exited on.
        #expect(SSHProbe.classify(FakeRunner.failed(255, stderr:
            "Permission denied (keyboard-interactive).\nalex@workhorse: Permission denied (publickey,password).\n"))
                == .authDenied(methods: ["publickey", "password"]))
    }
}
