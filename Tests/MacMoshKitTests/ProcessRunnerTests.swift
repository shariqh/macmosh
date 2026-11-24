import Foundation
import Testing
@testable import MacMoshKit

/// The commands these tests stop would run for 30 seconds. A stop must land well before that; the
/// bound leaves room for a busy CI machine, which has started a timed test seconds late (issue #137).
private let timeLimitWithRoom: Duration = .seconds(15)

@Suite struct ProcessRunnerTests {
    let runner = ProcessRunner()

    @Test func capturesBothStreamsAndTheExitCode() async {
        let r = await runner.run("/bin/sh", ["-c", "echo out; echo err >&2; exit 3"],
                                 environment: [:], stdin: nil, timeout: .seconds(5))
        #expect(r == CommandResult(exitCode: 3, stdout: "out\n", stderr: "err\n", timedOut: false))
    }

    @Test func killsAtTimeout() async {
        let clock = ContinuousClock(); let start = clock.now
        let r = await runner.run("/bin/sleep", ["30"], environment: [:], stdin: nil, timeout: .milliseconds(500))
        #expect(r.timedOut)
        #expect(r.exitCode == -1)
        #expect(clock.now - start < timeLimitWithRoom)
    }

    @Test func aStuckShellAndItsChildAreBothStoppedAtTimeout() async {
        // The shell waits for its child, so stopping only the shell would leave the child holding the pipes.
        let clock = ContinuousClock(); let start = clock.now
        let r = await runner.run("/bin/sh", ["-c", "/bin/sleep 30; echo after"],
                                 environment: [:], stdin: nil, timeout: .milliseconds(500))
        #expect(r.timedOut)
        #expect(r.stdout == "")
        #expect(clock.now - start < timeLimitWithRoom)
    }

    @Test func twoMegabytesOfOutputDoNotBlock() async {
        let r = await runner.run("/bin/sh", ["-c", "head -c 2000000 /dev/zero | tr '\\0' a"],
                                 environment: [:], stdin: nil, timeout: .seconds(20))
        #expect(r.stdout.count == 2_000_000)
    }

    @Test(arguments: ["", "plain", "a b", "it's", "say \"hi\"", "$HOME", "`id`", "a\nb", "é ☕", "-n", "a;b|c&d"])
    func quotedTextComesBackUnchanged(_ s: String) async {
        let r = await runner.run("/bin/sh", ["-c", "printf %s " + ShellQuote.posix(s)],
                                 environment: [:], stdin: nil, timeout: .seconds(5))
        #expect(r.stdout == s)
    }

    @Test func cancellingTheTaskStopsTheChild() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("macmosh-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let pidFile = dir.appendingPathComponent("pid").path

        let runner = self.runner
        let task = Task {
            await runner.run("/bin/sh", ["-c", "echo $$ > \(ShellQuote.posix(pidFile)); exec /bin/sleep 30"],
                             environment: [:], stdin: nil, timeout: .seconds(60))
        }
        // Cancel only once the shell has started, so the signal can't arrive before it is running.
        var pid: pid_t?
        for _ in 0..<500 where pid == nil {
            if let text = try? String(contentsOfFile: pidFile, encoding: .utf8),
               let n = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)) { pid = n }
            else { try await Task.sleep(for: .milliseconds(10)) }
        }
        let started = try #require(pid)

        let clock = ContinuousClock(); let start = clock.now
        task.cancel()
        let r = await task.value
        #expect(clock.now - start < timeLimitWithRoom)
        #expect(!r.timedOut)
        #expect(kill(started, 0) == -1 && errno == ESRCH)
    }

    @Test func oneTimeoutDoesNotDisturbCommandsRunningAtTheSameTime() async {
        let runner = self.runner
        async let slow = runner.run("/bin/sleep", ["30"], environment: [:], stdin: nil, timeout: .milliseconds(300))
        async let a = runner.run("/bin/sh", ["-c", "/bin/sleep 1; echo a"], environment: [:], stdin: nil, timeout: .seconds(10))
        async let b = runner.run("/bin/sh", ["-c", "/bin/sleep 1; echo b"], environment: [:], stdin: nil, timeout: .seconds(10))
        let (s, ra, rb) = await (slow, a, b)
        #expect(s.timedOut)
        #expect(ra == CommandResult(exitCode: 0, stdout: "a\n", stderr: "", timedOut: false))
        #expect(rb == CommandResult(exitCode: 0, stdout: "b\n", stderr: "", timedOut: false))
    }

    @Test func passesStdin() async {
        let bytes = Data("héllo\n\u{0}\u{1}world".utf8)
        let r = await runner.run("/bin/cat", [], environment: [:], stdin: bytes, timeout: .seconds(5))
        #expect(r.exitCode == 0)
        #expect(Data(r.stdout.utf8) == bytes)
    }

    @Test func aLargeStdinThroughCatDoesNotDeadlock() async {
        let bytes = Data(repeating: UInt8(ascii: "x"), count: 3_000_000)
        let r = await runner.run("/bin/cat", [], environment: [:], stdin: bytes, timeout: .seconds(20))
        #expect(r.stdout.count == 3_000_000)
    }

    @Test func noStdinMeansTheChildSeesEndOfInput() async {
        let r = await runner.run("/bin/cat", [], environment: [:], stdin: nil, timeout: .seconds(5))
        #expect(r.exitCode == 0 && r.stdout.isEmpty && !r.timedOut)
    }

    @Test func addsToTheEnvironment() async {
        let r = await runner.run("/bin/sh", ["-c", "printf '%s|%s' \"$MM_X\" \"${PATH:+set}\""],
                                 environment: ["MM_X": "1"], stdin: nil, timeout: .seconds(5))
        #expect(r.stdout == "1|set")
    }

    @Test func findsBareNamesOnPath() async {
        let r = await runner.run("true", [], environment: [:], stdin: nil, timeout: .seconds(5))
        #expect(r.exitCode == 0)
    }

    @Test func missingProgramIsAFailureNotACrash() async {
        let r = await runner.run("macmosh-no-such-program", [], environment: [:], stdin: nil, timeout: .seconds(5))
        #expect(r.exitCode == 127)
        #expect(r.stderr.contains("macmosh-no-such-program"))
        let r2 = await runner.run("/nonexistent/dir/tool", [], environment: [:], stdin: nil, timeout: .seconds(5))
        #expect(r2.exitCode == 127)
        #expect(r2.stderr.contains("/nonexistent/dir/tool"))
    }

    @Test func aProgramKilledBySignalReportsOnePlusTheSignalNumber() async {
        let r = await runner.run("/bin/sh", ["-c", "kill -9 $$"], environment: [:], stdin: nil, timeout: .seconds(5))
        #expect(r.exitCode == 137 && !r.timedOut)
    }

    // MARK: ToolFinder

    @Test func findsAToolInHomebrewsFolderWhenPathLacksIt() {
        let found = ToolFinder.find("tmux", path: "/usr/bin:/bin",
                                    isExecutable: { $0 == "/opt/homebrew/bin/tmux" })
        #expect(found == "/opt/homebrew/bin/tmux")
    }

    @Test func pathComesBeforeHomebrewsFolders() {
        let found = ToolFinder.find("tmux", path: "/usr/bin:/bin",
                                    isExecutable: { $0 == "/usr/bin/tmux" || $0 == "/opt/homebrew/bin/tmux" })
        #expect(found == "/usr/bin/tmux")
    }

    @Test func aToolThatIsNowhereIsNil() {
        #expect(ToolFinder.find("tmux", path: nil, isExecutable: { _ in false }) == nil)
    }

    // MARK: runAttached (serialized: they share the process's Ctrl-C handling)

    @Suite(.serialized) struct Attached {
        let runner = ProcessRunner()

        @Test func runAttachedReturnsTheChildsExitCode() async {
            let code = await runner.runAttached(["/bin/sh", "-c", "exit 7"], environment: [:])
            #expect(code == 7)
        }

        @Test func runAttachedReturnsOnePlusTheSignalNumberForAKilledChild() async {
            let code = await runner.runAttached(["/bin/sh", "-c", "kill -9 $$"], environment: [:])
            #expect(code == 137)
        }

        @Test func aMissingProgramReturns127() async {
            let code = await runner.runAttached(["macmosh-no-such-program"], environment: [:])
            #expect(code == 127)
        }

        @Test func ctrlCDuringAnAttachedChildLeavesTheParentRunning() async throws {
            let before = sigintDisposition()
            let runner = self.runner
            let task = Task { await runner.runAttached(["/bin/sleep", "1"], environment: [:]) }

            // Send the signal only once the parent is ignoring it. If that never happens the test
            // fails without sending anything, instead of killing the test process.
            var ignoring = false
            for _ in 0..<300 where !ignoring {
                if sigintDisposition() == Self.ignored { ignoring = true }
                else { try await Task.sleep(for: .milliseconds(10)) }
            }
            #expect(ignoring, "the parent never started ignoring Ctrl-C")
            if ignoring { kill(getpid(), SIGINT) }

            let code = await task.value
            #expect(code == 0)
            #expect(sigintDisposition() == before, "Ctrl-C handling was not put back")
        }

        static let ignored = 1

        /// 0 for the default action, 1 for ignored, anything else is a handler's address.
        func sigintDisposition() -> Int {
            var old = sigaction()
            sigaction(SIGINT, nil, &old)
            return unsafeBitCast(old.__sigaction_u.__sa_handler, to: Int.self)
        }
    }
}
