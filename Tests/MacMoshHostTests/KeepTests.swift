import Foundation
import Testing

extension HostScriptTests {
@Suite struct KeepTests {
    // Every wait below ends as soon as its condition holds. The limits are long because CI runners
    // are slow: on one, three runs of a one-line command with pauses of 1 and 2 seconds took over 15 seconds.
    private func runs(_ h: HostHarness) -> Int {
        let text = (try? String(contentsOf: h.home.appendingPathComponent("runs.txt"), encoding: .utf8)) ?? ""
        return text.split(separator: "\n").count
    }

    /// What the desk's screen shows, with wrapped lines joined and the scrollback included.
    private func screen(_ h: HostHarness, _ desk: String) -> String {
        h.tmux(["capture-pane", "-p", "-J", "-S", "-", "-t", "=\(desk):"]).stdout
    }

    private func waits(in text: String) -> [Int] {
        var found: [Int] = []
        let marker = "Starting it again in "
        for line in text.split(separator: "\n") {
            guard let range = line.range(of: marker) else { continue }
            let digits = line[range.upperBound...].prefix { $0.isNumber }
            if let n = Int(digits) { found.append(n) }
        }
        return found
    }

    /// What a failing wait should say: every desk's screen, `runs.txt`, the end of `host.log` and the panes.
    private func diagnosis(_ h: HostHarness) -> String {
        var out = "\n--- diagnosis ---"
        let sessions = h.tmux(["list-sessions", "-F", "#{session_name}"]).stdout
            .split(separator: "\n").map(String.init)
        for name in sessions {
            out += "\n[screen of \(name)]\n" + screen(h, name)
        }
        let runsText = (try? String(contentsOf: h.home.appendingPathComponent("runs.txt"), encoding: .utf8)) ?? "(no runs.txt)"
        out += "\n[runs.txt]\n" + runsText
        let log = (try? String(contentsOf: h.home.appendingPathComponent(".macmosh/host.log"), encoding: .utf8)) ?? "(no host.log)"
        out += "\n[host.log, last 30 lines]\n" + log.split(separator: "\n").suffix(30).joined(separator: "\n")
        out += "\n[panes]\n" + h.tmux(["list-panes", "-a", "-F", "#{pane_pid} #{pane_current_command} #{pane_dead}"]).stdout
        out += "[sessions] " + sessions.joined(separator: ", ")
        return out
    }

    /// Like `waitFor`, but a timeout is recorded with `diagnosis`, so a failure on CI shows what happened.
    private func wait(_ h: HostHarness, seconds: Double, line: UInt = #line, _ condition: () -> Bool) throws {
        do {
            try waitFor(seconds: seconds, condition)
        } catch {
            let message: String = "timed out after \(Int(seconds)) s (KeepTests.swift:\(line))" + diagnosis(h)
            Issue.record(Comment(rawValue: message))
            throw error
        }
    }

    private func endDesk(_ h: HostHarness, _ desk: String) {
        _ = h.tmux(["kill-session", "-t", "=\(desk)"])
    }

    @Test func aKeptCommandIsStartedAgain() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        h.setEnvironment("MACMOSH_KEEP_PAUSE", "1")
        _ = h.run(["start"])
        #expect(h.run(["desk-new", "kept", h.home.path, "--keep", "--command", "echo run >> runs.txt; exit 1"]).exitCode == 0)
        try wait(h, seconds: 40) { runs(h) >= 2 }
        #expect(runs(h) >= 2)
        endDesk(h, "kept")
    }

    @Test func theWaitDoublesForACommandThatKeepsFailing() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        h.setEnvironment("MACMOSH_KEEP_PAUSE", "1")
        _ = h.run(["start"])
        _ = h.run(["desk-new", "kept", h.home.path, "--keep", "--command", "echo run >> runs.txt; exit 1"])
        try wait(h, seconds: 60) { waits(in: screen(h, "kept")).count >= 3 }
        let text = screen(h, "kept")
        #expect(Array(waits(in: text).prefix(3)) == [1, 2, 4])
        #expect(text.contains("echo run >> runs.txt; exit 1 ended (exit 1). Starting it again in 1 seconds. Press Ctrl-C to stop."))
        endDesk(h, "kept")
    }

    @Test func aDeskWithoutKeepRunsItsCommandOnce() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        h.setEnvironment("MACMOSH_KEEP_PAUSE", "1")
        _ = h.run(["start"])
        #expect(h.run(["desk-new", "once", h.home.path, "--command", "echo run >> runs.txt; exit 1"]).exitCode == 0)
        try wait(h, seconds: 30) { runs(h) >= 1 }
        Thread.sleep(forTimeInterval: 5)
        #expect(runs(h) == 1)
        endDesk(h, "once")
    }

    @Test func keepOnAnUnknownDeskExits4() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        let result = h.run(["keep", "nope"])
        #expect(result.exitCode == 4)
        #expect(!result.stderr.isEmpty)
        #expect(h.run(["keep", "bad name"]).exitCode == 4)
        #expect(h.run(["keep"]).exitCode == 2)
        // keep never starts the desk server.
        #expect(h.tmux(["list-sessions"]).exitCode != 0)
    }

    @Test func keepWithNoCommandSaysSoAndExits0() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        let dir = h.home.appendingPathComponent(".macmosh")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "bare\t0\t1\t\(h.home.path)\t\n".write(to: dir.appendingPathComponent("desks.tsv"), atomically: true, encoding: .utf8)
        let result = h.run(["keep", "bare"])
        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("nothing to keep running"))
        #expect(result.stdout.split(separator: "\n").count == 1)
    }

    @Test func deskNewKeepWithoutACommandIsRefused() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        let result = h.run(["desk-new", "bare", h.home.path, "--keep"])
        #expect(result.exitCode == 6)
        #expect(result.stderr.contains("nothing to keep running"))
        #expect(h.tmux(["has-session", "-t", "=bare"]).exitCode != 0)
        #expect(!FileManager.default.fileExists(atPath: h.home.appendingPathComponent(".macmosh/desks.tsv").path))
    }

    @Test func startAndAttachBringBackAKeptDeskAsAKeptDesk() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        h.setEnvironment("MACMOSH_KEEP_PAUSE", "1")
        _ = h.run(["start"])
        #expect(h.run(["desk-new", "kept", h.home.path, "--reopen", "--keep", "--command", "echo run >> runs.txt; exit 1"]).exitCode == 0)
        try wait(h, seconds: 40) { runs(h) >= 2 }

        // The desk server restarts: start reopens the desk, and it is kept again.
        _ = h.tmux(["kill-server"])
        try FileManager.default.removeItem(at: h.home.appendingPathComponent("runs.txt"))
        _ = h.run(["start"])
        try wait(h, seconds: 40) { runs(h) >= 2 }
        endDesk(h, "kept")

        // attach recreates a desk that was closed.
        try FileManager.default.removeItem(at: h.home.appendingPathComponent("runs.txt"))
        #expect(h.run(["attach", "--dry-run", "kept"]).exitCode == 0)
        try wait(h, seconds: 40) { runs(h) >= 2 }
        endDesk(h, "kept")
    }

    @Test func ctrlCDuringTheWaitLeavesTheDeskAtAPrompt() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        h.setEnvironment("MACMOSH_KEEP_PAUSE", "30")
        _ = h.run(["start"])
        _ = h.run(["desk-new", "kept", h.home.path, "--keep", "--command", "echo run >> runs.txt; exit 1"])
        try wait(h, seconds: 40) { !waits(in: screen(h, "kept")).isEmpty }
        _ = h.tmux(["send-keys", "-t", "=kept:", "C-c"])
        // The loop has ended and the desk's own shell is back: it answers a command.
        Thread.sleep(forTimeInterval: 1)
        _ = h.tmux(["send-keys", "-t", "=kept:", "-l", "--", "echo alive > alive.txt"])
        _ = h.tmux(["send-keys", "-t", "=kept:", "Enter"])
        try wait(h, seconds: 40) { FileManager.default.fileExists(atPath: h.home.appendingPathComponent("alive.txt").path) }
        #expect(h.tmux(["has-session", "-t", "=kept"]).exitCode == 0)
        #expect(runs(h) == 1)
        endDesk(h, "kept")
    }

    @Test func theScriptPathIsQuotedForTheDesksShell() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        h.setEnvironment("MACMOSH_KEEP_PAUSE", "1")
        let folder = h.home.appendingPathComponent("it's a $dir")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let copy = folder.appendingPathComponent("macmosh-host")
        try FileManager.default.copyItem(at: h.scriptURL, to: copy)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: copy.path)
        let quoted = "'" + copy.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        _ = h.shell("\(quoted) start")
        let made = h.shell("\(quoted) desk-new kept '\(h.home.path)' --keep --command 'echo run >> runs.txt; exit 1'")
        #expect(made.exitCode == 0)
        try wait(h, seconds: 40) { runs(h) >= 2 }
        endDesk(h, "kept")
    }
}
}
