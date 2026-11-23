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
        // The next start, which any later command brings about, keeps them too.
        #expect(h.run(["start"]).exitCode == 0)
        #expect(desksFile(h) == before)
        #expect(!isOpen(h, "b"))
        try proveTheHookHasRun(h)
        #expect(desksFile(h) == before)
        #expect(!hostLog(h).contains("removed a"))
        #expect(!hostLog(h).contains("removed b"))
        #expect(!hostLog(h).contains("removed c"))
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
        #expect(h.run(["start"]).exitCode == 0)
        #expect(desksFile(h) == before)
        try proveTheHookHasRun(h)
        #expect(desksFile(h) == before)
        #expect(!hostLog(h).contains("removed a"))
        #expect(!hostLog(h).contains("removed b"))
        #expect(!hostLog(h).contains("removed c"))
    }

    @Test func restartServerKeepsEveryDefinitionAndReopensTheDesks() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        _ = h.run(["desk-new", "back", h.home.path])
        _ = h.run(["desk-new", "once", h.home.path, "--no-reopen"])
        _ = h.run(["desk-new", "kept", h.home.path, "--permanent", "--no-reopen"])
        _ = h.run(["desk-new", "both", h.home.path, "--permanent"])
        let before = desksFile(h)
        #expect(before.split(separator: "\n").count == 4)
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
        #expect(!isOpen(h, "once"))
        try proveTheHookHasRun(h)
        #expect(desksFile(h) == before)
    }

    /// A definition not marked reopen, in the form from before 0.5.0 and in the new one, stays through
    /// every way the server comes back. Before 0.5.0 every desk made from the menu had such a line.
    @Test func aLineNotMarkedReopenSurvivesEveryRestartOfTheServer() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        let text = "five\t0\t0\t\(h.home.path)\t\nsix\t0\t0\t0\t\(h.home.path)\t\n"
        try writeDesksFile(h, text)
        #expect(h.run(["start"]).exitCode == 0)
        #expect(desksFile(h) == text)

        let pid = try serverPid(h)
        _ = h.tmux(["kill-server"])
        try wait(h) { !isRunning(pid) }
        #expect(h.run(["start"]).exitCode == 0)
        #expect(desksFile(h) == text)

        try h.stub("launchctl", script: """
            echo "$*" >> "$HOME/launchctl.log"
            if [ "$1" = "kickstart" ]; then "\(h.scriptURL.path)" start; fi
            exit 0
            """)
        #expect(h.run(["restart-server", "--yes"]).exitCode == 0)
        #expect(desksFile(h) == text)
        #expect(!isOpen(h, "five"))
        #expect(!isOpen(h, "six"))
        // attach makes either desk again from its line.
        #expect(h.run(["attach", "--dry-run", "five"]).stdout == "ok\n")
        #expect(isOpen(h, "five"))
    }

    // MARK: - Leftovers

    @Test func startReopensTheDesksAndKeepsEveryLine() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        _ = h.run(["desk-new", "back", h.home.path])
        _ = h.run(["desk-new", "once", h.home.path, "--no-reopen"])
        _ = h.run(["desk-new", "kept", h.home.path, "--permanent", "--no-reopen"])
        let before = desksFile(h)
        let pid = try serverPid(h)
        _ = h.tmux(["kill-server"])
        try wait(h) { !isRunning(pid) }
        #expect(h.run(["start"]).exitCode == 0)
        #expect(isOpen(h, "back"))
        #expect(!isOpen(h, "once"))
        #expect(!isOpen(h, "kept"))
        // "once" is not opened, but its line stays: the menu hides it and desk-new replaces it.
        #expect(desksFile(h) == before)
        #expect(!hostLog(h).contains("dropped"))
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
        try writeDesksFile(h, "old\t1\t0\t\(folder.path)\techo hi > old.txt\n"
            + "older\t0\t0\t\(folder.path)\t\n"
            + "bare\t1\t0\t\(folder.path)\t\n")
        #expect(h.run(["start"]).exitCode == 0)
        // Reopened in its own folder, with its own command.
        #expect(isOpen(h, "old"))
        try wait(h) { FileManager.default.fileExists(atPath: folder.appendingPathComponent("old.txt").path) }
        // Not marked reopen: not opened, and its line stays.
        #expect(!isOpen(h, "older"))
        #expect(defined(h, "older"))
        // Marked reopen with no startup command: the empty last field is the command, not a permanent flag.
        #expect(isOpen(h, "bare"))
        let report = h.run(["status"]).stdout
        #expect(report.contains("\ndef\told\t1\t0\t0\t\(folder.path)\techo hi > old.txt\n"))
        #expect(report.contains("\ndef\tolder\t0\t0\t0\t\(folder.path)\t\n"))
        #expect(report.contains("\ndef\tbare\t1\t0\t0\t\(folder.path)\t\n"))
        // Not permanent, so an exit removes either.
        typeExit(h, "=old:")
        try wait(h) { !defined(h, "old") }
        typeExit(h, "=bare:")
        try wait(h) { !defined(h, "bare") }
        #expect(defined(h, "older"))
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

    @Test func theHookIsSetOnceAndYourOwnHooksStay() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        try "set-hook -g session-closed[0] 'run-shell true'\n"
            .write(to: h.home.appendingPathComponent(".tmux.conf"), atomically: true, encoding: .utf8)
        _ = h.run(["start"])
        for i in 0..<4 {
            #expect(h.run(["status"]).exitCode == 0)
            #expect(h.run(["start"]).exitCode == 0)
            #expect(h.run(["desk-new", "d\(i)", h.home.path]).exitCode == 0)
            #expect(h.run(["window-new", "d\(i)"]).exitCode == 0)
            #expect(h.run(["attach", "--dry-run", "d\(i)"]).exitCode == 0)
        }
        let hooks = h.tmux(["show-hooks", "-g", "session-closed"]).stdout
        let ours = hooks.split(separator: "\n").filter { $0.contains("@macmosh-desk-closed") }
        #expect(ours.count == 1, "\(hooks)")
        #expect(hooks.contains("run-shell true"), "\(hooks)")
    }

    // MARK: - Your own tmux settings

    /// destroy-unattached closes a session when its last client leaves. MacMosh turns it off for its
    /// own server, because a closed tab or mosh window must never close a desk.
    @Test func detachingNeverClosesADeskWhenYourSettingsTurnOnDestroyUnattached() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        try "set -g destroy-unattached on\n"
            .write(to: h.home.appendingPathComponent(".tmux.conf"), atomically: true, encoding: .utf8)
        _ = h.run(["start"])
        #expect(h.run(["desk-new", "solo", h.home.path]).exitCode == 0)
        // A client comes and goes, the way a tab or a mosh window does.
        _ = h.shell("tmux -L '\(h.socket)' -C attach-session -t =solo < /dev/null")
        try proveTheHookHasRun(h)
        #expect(isOpen(h, "solo"))
        #expect(defined(h, "solo"))
        #expect(h.tmux(["show-options", "-gv", "destroy-unattached"]).stdout == "off\n")
    }

    @Test func aRunningServerGetsDestroyUnattachedTurnedOff() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.tmux(["-f", "/dev/null", "start-server", ";", "set-option", "-s", "exit-empty", "off",
                    ";", "set-option", "-g", "destroy-unattached", "on"])
        #expect(h.tmux(["show-options", "-gv", "destroy-unattached"]).stdout == "on\n")
        #expect(h.run(["status"]).exitCode == 0)
        #expect(h.tmux(["show-options", "-gv", "destroy-unattached"]).stdout == "off\n")
    }

    // MARK: - Desk names are text

    /// awk reads "7" and "007", or "1e3" and "1000", as the same number. The script compares names as
    /// text, so one desk never touches the other's line.
    @Test(arguments: zip(["7", "007", "1e3", "1000"], ["007", "7", "1000", "1e3"]))
    func aNameThatLooksLikeANumberTouchesOnlyItsOwnLine(one: String, other: String) throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        #expect(h.run(["desk-new", other, h.home.path]).exitCode == 0)
        let otherLine = desksFile(h)
        #expect(h.run(["desk-new", one, h.home.path]).exitCode == 0)
        #expect(defined(h, one))
        #expect(defined(h, other))

        #expect(h.run(["desk-remove", one, "--kill"]).exitCode == 0)
        #expect(!defined(h, one))
        #expect(desksFile(h) == otherLine)
        #expect(isOpen(h, other))

        #expect(h.run(["desk-new", one, h.home.path]).exitCode == 0)
        typeExit(h, "=\(one):")
        try wait(h) { !defined(h, one) }
        try proveTheHookHasRun(h)
        #expect(desksFile(h) == otherLine)
        #expect(isOpen(h, other))
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

    /// The hook runs for every session that closes, your own tmux sessions too.
    @Test func deskClosedIgnoresANameThatIsNotADeskName() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        let text = "bad name\t0\t0\t0\t/gone\t\na.b\t0\t0\t0\t/gone\t\n"
        try writeDesksFile(h, text)
        let pid = try serverPid(h)
        for name in ["bad name", "a.b"] {
            #expect(h.run(["desk-closed", name, String(pid)]).exitCode == 0)
        }
        #expect(desksFile(h) == text)
        #expect(hostLog(h).contains("ignored: not a desk name"))
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
