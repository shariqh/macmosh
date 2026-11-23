import Foundation
import Testing

extension HostScriptTests {
/// What happens to a desk's definition when its last shell exits, and when the desk server goes away
/// instead. An ordinary desk is removed when its last shell exits; a permanent one stays. Nothing that
/// takes the server down (kill-server, a signal, restart-server) removes a definition.
///
/// Every wait ends as soon as its condition holds. The limits are long because CI runners are slow.
@Suite struct DeskLifeTests {
    private func desksFile(_ h: HostHarness) -> String {
        (try? String(contentsOf: h.home.appendingPathComponent(".macmosh/desks.tsv"), encoding: .utf8)) ?? ""
    }

    private func writeDesksFile(_ h: HostHarness, _ text: String) throws {
        let folder = h.home.appendingPathComponent(".macmosh")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try text.write(to: folder.appendingPathComponent("desks.tsv"), atomically: true, encoding: .utf8)
    }

    private func defined(_ h: HostHarness, _ name: String) -> Bool {
        desksFile(h).split(separator: "\n").contains { $0.hasPrefix(name + "\t") }
    }

    private func hostLog(_ h: HostHarness) -> String {
        (try? String(contentsOf: h.home.appendingPathComponent(".macmosh/host.log"), encoding: .utf8)) ?? ""
    }

    private func isOpen(_ h: HostHarness, _ name: String) -> Bool {
        h.tmux(["has-session", "-t", "=\(name)"]).exitCode == 0
    }

    /// Types `exit` into a pane, the way a person ends the shell.
    private func typeExit(_ h: HostHarness, _ target: String) {
        _ = h.tmux(["send-keys", "-t", target, "-l", "--", "exit"])
        _ = h.tmux(["send-keys", "-t", target, "Enter"])
    }

    /// The desk server's process id, read from this test's own socket.
    private func serverPid(_ h: HostHarness) throws -> pid_t {
        let text = h.tmux(["display-message", "-p", "#{pid}"]).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return try #require(pid_t(text), "no server pid on \(h.socket): \(text)")
    }

    private func isRunning(_ pid: pid_t) -> Bool { kill(pid, 0) == 0 }

    /// Ends the desk server with a signal, after checking that the process is this test's server.
    private func signalServer(_ h: HostHarness, _ signal: Int32) throws -> pid_t {
        let pid = try serverPid(h)
        #expect(pid > 1)
        let command = h.shell("ps -o command= -p \(pid)").stdout
        try #require(command.contains("tmux") && command.contains(h.socket),
                     "process \(pid) is not this test's server: \(command)")
        #expect(kill(pid, signal) == 0)
        return pid
    }

    /// Like `waitFor`, but a timeout is recorded with the desk list and the end of the log.
    private func wait(_ h: HostHarness, seconds: Double = 30, line: UInt = #line, _ condition: () -> Bool) throws {
        do {
            try waitFor(seconds: seconds, condition)
        } catch {
            let log = hostLog(h).split(separator: "\n").suffix(20).joined(separator: "\n")
            Issue.record(Comment(rawValue: "timed out after \(Int(seconds)) s (DeskLifeTests.swift:\(line))\n"
                + "[desks.tsv]\n\(desksFile(h))[host.log]\n\(log)\n[hooks]\n\(h.tmux(["show-hooks", "-g", "session-closed"]).stdout)"))
            throw error
        }
    }

    /// Makes an ordinary desk, ends its shell and waits until its definition is gone. Once that has
    /// happened the desk server has run its hook for every desk that closed before, so a definition
    /// that is still there afterwards was kept on purpose, not by luck of timing.
    private func proveTheHookHasRun(_ h: HostHarness) throws {
        #expect(h.run(["desk-new", "marker", h.home.path]).exitCode == 0)
        typeExit(h, "=marker:")
        try wait(h) { !defined(h, "marker") }
    }

    // MARK: - An exit

    @Test func exitInTheOnlyShellRemovesTheDesk() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        #expect(h.run(["desk-new", "brief", h.home.path]).exitCode == 0)
        #expect(defined(h, "brief"))
        typeExit(h, "=brief:")
        try wait(h) { !defined(h, "brief") }
        #expect(!isOpen(h, "brief"))
        #expect(hostLog(h).contains("removed brief"))
        // The name is free again.
        #expect(h.run(["desk-new", "brief", h.home.path]).exitCode == 0)
        #expect(defined(h, "brief"))
    }

    @Test func aDeskWithTwoWindowsStaysUntilTheSecondCloses() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        #expect(h.run(["desk-new", "pair", h.home.path]).exitCode == 0)
        #expect(h.run(["window-new", "pair"]).exitCode == 0)
        let windows = { h.tmux(["display-message", "-p", "-t", "=pair:", "#{session_windows}"]).stdout }
        #expect(windows() == "2\n")

        typeExit(h, "=pair:0")
        try wait(h) { windows() == "1\n" }
        try proveTheHookHasRun(h)
        #expect(defined(h, "pair"))
        #expect(isOpen(h, "pair"))

        typeExit(h, "=pair:")
        try wait(h) { !defined(h, "pair") }
    }

    @Test func aPermanentDeskStaysAfterItsLastShellExits() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        let folder = h.home.appendingPathComponent("site")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        _ = h.run(["start"])
        #expect(h.run(["desk-new", "site", folder.path, "--permanent"]).exitCode == 0)
        typeExit(h, "=site:")
        try wait(h) { hostLog(h).contains("kept site: permanent") }
        try proveTheHookHasRun(h)
        #expect(defined(h, "site"))
        #expect(!isOpen(h, "site"))

        let report = h.run(["status"]).stdout
        #expect(report.contains("\ndef\tsite\t1\t0\t1\t\(folder.path)\t\n"))
        #expect(!report.contains("\ndesk\tsite\t"))

        // One click opens it again: attach makes the session from the definition.
        let r = h.run(["attach", "--dry-run", "site"])
        #expect(r.exitCode == 0)
        #expect(r.stdout == "ok\n")
        #expect(isOpen(h, "site"))
    }

    // MARK: - The desk server going away

    @Test func killServerKeepsEveryDefinition() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        _ = h.run(["desk-new", "a", h.home.path])
        _ = h.run(["desk-new", "b", h.home.path, "--no-reopen"])
        _ = h.run(["desk-new", "c", h.home.path, "--permanent"])
        let before = desksFile(h)
        #expect(before.split(separator: "\n").count == 3)
        let pid = try serverPid(h)
        _ = h.tmux(["kill-server"])
        // Once the server's process is gone it can't run anything any more.
        try wait(h) { !isRunning(pid) }
        #expect(desksFile(h) == before)
        #expect(!hostLog(h).contains("removed"))
    }

    @Test(arguments: [SIGTERM, SIGKILL])
    func aSignalToTheServerKeepsEveryDefinition(signal: Int32) throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        _ = h.run(["desk-new", "a", h.home.path])
        _ = h.run(["desk-new", "b", h.home.path, "--no-reopen"])
        _ = h.run(["desk-new", "c", h.home.path, "--permanent"])
        let before = desksFile(h)
        let pid = try signalServer(h, signal)
        try wait(h) { !isRunning(pid) }
        #expect(desksFile(h) == before)
        #expect(!hostLog(h).contains("removed"))
    }

    @Test func restartServerKeepsEveryDefinitionAndReopensTheDesks() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        _ = h.run(["desk-new", "back", h.home.path])
        _ = h.run(["desk-new", "kept", h.home.path, "--permanent", "--no-reopen"])
        _ = h.run(["desk-new", "both", h.home.path, "--permanent"])
        let before = desksFile(h)
        let pid = try serverPid(h)
        // The stand-in login agent runs the script's start, as the real one would.
        try h.stub("launchctl", script: """
            echo "$*" >> "$HOME/launchctl.log"
            if [ "$1" = "kickstart" ]; then "\(h.scriptURL.path)" start; fi
            exit 0
            """)
        #expect(h.run(["restart-server", "--yes"]).exitCode == 0)
        #expect(try serverPid(h) != pid)
        #expect(desksFile(h) == before)
        #expect(isOpen(h, "back"))
        #expect(isOpen(h, "both"))
        #expect(!isOpen(h, "kept"))
        try proveTheHookHasRun(h)
        #expect(desksFile(h) == before)
    }

    // MARK: - Leftovers

    @Test func startReopensTheDesksAndDropsAStaleLine() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        _ = h.run(["desk-new", "back", h.home.path])
        _ = h.run(["desk-new", "once", h.home.path, "--no-reopen"])
        _ = h.run(["desk-new", "kept", h.home.path, "--permanent", "--no-reopen"])
        _ = h.tmux(["kill-server"])
        #expect(h.run(["start"]).exitCode == 0)
        #expect(isOpen(h, "back"))
        #expect(!isOpen(h, "once"))
        #expect(!isOpen(h, "kept"))
        // "once" would never come back, so its line goes and its name is free.
        #expect(!defined(h, "once"))
        #expect(defined(h, "back"))
        #expect(defined(h, "kept"))
        #expect(hostLog(h).contains("dropped once"))
    }

    @Test func deskNewOverAStaleLineReplacesIt() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        let folder = h.home.appendingPathComponent("new")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        _ = h.run(["start"])
        try writeDesksFile(h, "stale\t0\t0\t0\t/gone\t\nold\t1\t0\t/gone\techo hi\n")
        #expect(h.run(["desk-new", "stale", folder.path]).exitCode == 0)
        #expect(h.run(["desk-new", "old", folder.path]).exitCode == 0)
        let lines = desksFile(h).split(separator: "\n").map(String.init).sorted()
        #expect(lines == ["old\t1\t0\t0\t\(folder.path)\t", "stale\t1\t0\t0\t\(folder.path)\t"])
    }

    @Test func deskNewRefusesAClosedPermanentDesk() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        try writeDesksFile(h, "kept\t0\t0\t1\t/gone\t\n")
        #expect(h.run(["desk-new", "kept", h.home.path]).exitCode == 7)
        #expect(desksFile(h) == "kept\t0\t0\t1\t/gone\t\n")
    }

    // MARK: - Lines written before this change

    @Test func aFiveFieldLineIsReadAsNotPermanent() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        let folder = h.home.appendingPathComponent("old folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try writeDesksFile(h, "old\t1\t0\t\(folder.path)\techo hi > old.txt\nolder\t0\t0\t\(folder.path)\t\n")
        #expect(h.run(["start"]).exitCode == 0)
        // Reopened in its own folder, with its own command.
        #expect(isOpen(h, "old"))
        try wait(h) { FileManager.default.fileExists(atPath: folder.appendingPathComponent("old.txt").path) }
        // Not marked reopen and not permanent: a stale line once the server has started.
        #expect(!defined(h, "older"))
        let report = h.run(["status"]).stdout
        #expect(report.contains("\ndef\told\t1\t0\t0\t\(folder.path)\techo hi > old.txt\n"))
        // Not permanent, so its exit removes it.
        typeExit(h, "=old:")
        try wait(h) { !defined(h, "old") }
    }

    // MARK: - A server started by an older script

    @Test func aServerStartedBeforeTheUpdateGetsTheHookWithoutARestart() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        // What an older script left: a server with no hook, and a desk with a five-field line.
        _ = h.tmux(["-f", "/dev/null", "start-server", ";", "set-option", "-s", "exit-empty", "off"])
        _ = h.tmux(["new-session", "-d", "-s", "early", "-c", h.home.path])
        try writeDesksFile(h, "early\t0\t0\t\(h.home.path)\t\n")
        let pid = try serverPid(h)
        #expect(!h.tmux(["show-hooks", "-g", "session-closed"]).stdout.contains("@macmosh-desk-closed"))

        // The updated script's next status check adds the hook.
        #expect(h.run(["status"]).exitCode == 0)
        #expect(h.tmux(["show-hooks", "-g", "session-closed"]).stdout.contains("@macmosh-desk-closed"))
        #expect(try serverPid(h) == pid)
        #expect(isOpen(h, "early"))

        typeExit(h, "=early:")
        try wait(h) { !defined(h, "early") }
    }

    // MARK: - desk-closed, the hook's own subcommand

    @Test func deskClosedKeepsTheDefinitionUnlessThatSameServerIsStillUp() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        try writeDesksFile(h, "a\t0\t0\t0\t/gone\t\n")
        let pid = try serverPid(h)
        // Another server's process id: kept.
        #expect(h.run(["desk-closed", "a", String(pid + 100_000)]).exitCode == 0)
        #expect(defined(h, "a"))
        // Nobody logged in at the screen: kept.
        try h.stub("stat", script: """
            if [ "$1" = "-f" ] && [ "$2" = "%Su" ] && [ "$3" = "/dev/console" ]; then echo root; exit 0; fi
            exec /usr/bin/stat "$@"
            """)
        #expect(h.run(["desk-closed", "a", String(pid)]).exitCode == 0)
        #expect(defined(h, "a"))
        try FileManager.default.removeItem(at: h.stubFolder.appendingPathComponent("stat"))
        // The desk is open again: kept.
        _ = h.tmux(["new-session", "-d", "-s", "a"])
        #expect(h.run(["desk-closed", "a", String(pid)]).exitCode == 0)
        #expect(defined(h, "a"))
        _ = h.tmux(["kill-session", "-t", "=a"])
        try writeDesksFile(h, "a\t0\t0\t0\t/gone\t\n")
        // The same server, no session, not permanent: removed.
        #expect(h.run(["desk-closed", "a", String(pid)]).exitCode == 0)
        #expect(!defined(h, "a"))
    }

    @Test func deskClosedKeepsTheDefinitionWhenTheServerIsGone() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        try writeDesksFile(h, "a\t0\t0\t0\t/gone\t\n")
        let pid = try serverPid(h)
        _ = h.tmux(["kill-server"])
        try wait(h) { !isRunning(pid) }
        #expect(h.run(["desk-closed", "a", String(pid)]).exitCode == 0)
        #expect(defined(h, "a"))
        #expect(h.tmux(["list-sessions"]).exitCode != 0, "desk-closed must never start a server")
    }

    @Test func deskClosedAndDeskRemoveTakeTurnsWithTheList() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        let names = (1...8).map { "d\($0)" }
        try writeDesksFile(h, names.map { "\($0)\t0\t0\t0\t/gone\t\n" }.joined() + "stay\t0\t0\t1\t/gone\t\n")
        let pid = try serverPid(h)
        let script = h.scriptURL.path
        // Half go through the exit path and half through desk-remove, all at once.
        var lines: [String] = []
        for (i, name) in names.enumerated() {
            let call = i % 2 == 0 ? "desk-closed \(name) \(pid)" : "desk-remove \(name)"
            lines.append("'\(script)' \(call) & p\(i)=$!")
        }
        lines.append((0..<names.count).map { "wait $p\($0) || echo failed" }.joined(separator: "; "))
        let out = h.shell(lines.joined(separator: "\n"))
        #expect(out.stdout == "", "a writer failed: \(out.stdout) \(out.stderr)")
        #expect(desksFile(h) == "stay\t0\t0\t1\t/gone\t\n")
        #expect(!FileManager.default.fileExists(atPath: h.home.appendingPathComponent(".macmosh/lock").path))
    }
}
}
