import Foundation
import Testing

extension HostScriptTests {
/// `desk-rename <old> <new>`: the desk keeps its windows, what runs in them and every field of its
/// definition; only the name changes, in the tmux session and in the definition's first field.
///
/// Every wait ends as soon as its condition holds. The limits are long because CI runners are slow.
@Suite struct DeskRenameTests {
    private func desksFile(_ h: HostHarness) -> String {
        (try? String(contentsOf: h.home.appendingPathComponent(".macmosh/desks.tsv"), encoding: .utf8)) ?? ""
    }

    private func writeDesksFile(_ h: HostHarness, _ text: String) throws {
        let folder = h.home.appendingPathComponent(".macmosh")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try text.write(to: folder.appendingPathComponent("desks.tsv"), atomically: true, encoding: .utf8)
    }

    private func line(_ h: HostHarness, _ name: String) -> String? {
        desksFile(h).split(separator: "\n").map(String.init).first { $0.hasPrefix(name + "\t") }
    }

    private func defined(_ h: HostHarness, _ name: String) -> Bool { line(h, name) != nil }

    private func hostLog(_ h: HostHarness) -> String {
        (try? String(contentsOf: h.home.appendingPathComponent(".macmosh/host.log"), encoding: .utf8)) ?? ""
    }

    private func isOpen(_ h: HostHarness, _ name: String) -> Bool {
        h.tmux(["has-session", "-t", "=\(name)"]).exitCode == 0
    }

    private func sessions(_ h: HostHarness) -> [String] {
        h.tmux(["list-sessions", "-F", "#{session_name}"]).stdout.split(separator: "\n").map(String.init).sorted()
    }

    private func typeExit(_ h: HostHarness, _ target: String) {
        _ = h.tmux(["send-keys", "-t", target, "-l", "--", "exit"])
        _ = h.tmux(["send-keys", "-t", target, "Enter"])
    }

    private func wait(_ h: HostHarness, seconds: Double = 30, line: UInt = #line, _ condition: () -> Bool) throws {
        do {
            try waitFor(seconds: seconds, condition)
        } catch {
            let log = hostLog(h).split(separator: "\n").suffix(20).joined(separator: "\n")
            Issue.record(Comment(rawValue: "timed out after \(Int(seconds)) s (DeskRenameTests.swift:\(line))\n"
                + "[desks.tsv]\n\(desksFile(h))[host.log]\n\(log)"))
            throw error
        }
    }

    /// Makes an ordinary desk, ends its shell and waits until its definition is gone: by then the desk
    /// server has run its hook for every desk that closed before.
    private func proveTheHookHasRun(_ h: HostHarness) throws {
        #expect(h.run(["desk-new", "marker", h.home.path]).exitCode == 0)
        typeExit(h, "=marker:")
        try wait(h) { !defined(h, "marker") }
    }

    // MARK: - Renaming

    @Test func anOpenDeskKeepsItsProgramItsWindowsAndEveryOtherField() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        let folder = h.home.appendingPathComponent("my site")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        _ = h.run(["start"])
        #expect(h.run(["desk-new", "other", h.home.path]).exitCode == 0)
        #expect(h.run(["desk-new", "website", folder.path, "--no-reopen", "--permanent",
                       "--command", "sleep 4242"]).exitCode == 0)
        #expect(h.run(["window-new", "website"]).exitCode == 0)
        let otherLine = line(h, "other")

        // The program is running in the desk's first window.
        let command = { h.tmux(["display-message", "-p", "-t", "=website:0", "#{pane_current_command}"]).stdout }
        try wait(h) { command() == "sleep\n" }
        let shell = h.tmux(["display-message", "-p", "-t", "=website:0", "#{pane_pid}"]).stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let child = h.shell("pgrep -P \(shell)").stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let program = try #require(pid_t(child), "no program under the desk's shell \(shell): \(child)")

        let r = h.run(["desk-rename", "website", "notes"])
        #expect(r.exitCode == 0, "\(r.stderr)")

        #expect(!isOpen(h, "website"))
        #expect(isOpen(h, "notes"))
        #expect(kill(program, 0) == 0, "the program in the desk stopped")
        #expect(h.tmux(["display-message", "-p", "-t", "=notes:0", "#{pane_current_command}"]).stdout == "sleep\n")
        #expect(h.tmux(["display-message", "-p", "-t", "=notes:", "#{session_windows}"]).stdout == "2\n")
        #expect(line(h, "notes") == "notes\t0\t0\t1\t\(folder.path)\tsleep 4242")
        #expect(!defined(h, "website"))
        #expect(line(h, "other") == otherLine)
        #expect(desksFile(h).split(separator: "\n").count == 2)
        #expect(hostLog(h).contains("renamed website to notes"))
    }

    @Test func aClosedPermanentDeskIsRenamedWithoutAServer() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        try writeDesksFile(h, "journal\t1\t1\t1\t/gone\techo hi\nother\t1\t0\t0\t/gone\t\n")
        let r = h.run(["desk-rename", "journal", "diary"])
        #expect(r.exitCode == 0, "\(r.stderr)")
        #expect(desksFile(h) == "diary\t1\t1\t1\t/gone\techo hi\nother\t1\t0\t0\t/gone\t\n")
        #expect(h.tmux(["list-sessions"]).exitCode != 0, "desk-rename must never start a server")
    }

    @Test func aSessionWithNoDefinitionIsRenamed() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        _ = h.tmux(["new-session", "-d", "-s", "loose"])
        #expect(h.run(["desk-rename", "loose", "found"]).exitCode == 0)
        #expect(sessions(h) == ["found"])
        #expect(desksFile(h) == "")
    }

    /// A line for the new name that is neither open nor permanent is left over from an exit, and is
    /// replaced, as desk-new replaces it.
    @Test func aLeftoverLineForTheNewNameIsReplaced() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        #expect(h.run(["desk-new", "notes", h.home.path, "--command", "echo hi"]).exitCode == 0)
        let notes = try #require(line(h, "notes"))
        try writeDesksFile(h, desksFile(h) + "website\t1\t0\t0\t/gone\tnpm start\n")
        #expect(h.run(["desk-rename", "notes", "website"]).exitCode == 0)
        #expect(desksFile(h) == "website" + notes.dropFirst("notes".count) + "\n")
        #expect(sessions(h) == ["website"])
    }

    // MARK: - Refusals change nothing

    @Test func aTakenNameABadNameAndAMissingDeskAreRefused() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        #expect(h.run(["desk-new", "website", h.home.path]).exitCode == 0)
        #expect(h.run(["desk-new", "notes", h.home.path]).exitCode == 0)
        try writeDesksFile(h, desksFile(h) + "journal\t0\t0\t1\t/gone\t\n")
        let before = desksFile(h)
        let open = sessions(h)

        let cases: [([String], Int32)] = [
            (["website", "notes"], 7),        // an open desk has the name
            (["website", "journal"], 7),      // a closed permanent desk has it
            (["journal", "website"], 7),
            (["website", "website"], 7),
            (["nothing", "fresh"], 4),        // no desk to rename
            (["website", "my desk"], 2),      // names break the rule
            (["website", "a.b"], 2),
            (["web site", "fresh"], 2),
            (["website", String(repeating: "x", count: 65)], 2),
            (["website"], 2),                 // usage
            (["website", "fresh", "extra"], 2),
        ]
        for (arguments, code) in cases {
            let r = h.run(["desk-rename"] + arguments)
            #expect(r.exitCode == code, "\(arguments): \(r.stderr)")
            #expect(!r.stderr.isEmpty, "\(arguments) said nothing")
            #expect(desksFile(h) == before, "\(arguments)")
            #expect(sessions(h) == open, "\(arguments)")
        }
        #expect(!FileManager.default.fileExists(atPath: h.home.appendingPathComponent(".macmosh/lock").path))
    }

    /// With no desk server, a line that is not permanent is a desk waiting to reopen at the next login,
    /// not a leftover, so its name is taken.
    @Test func withNoServerADeskWaitingToReopenKeepsItsName() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        let before = "website\t1\t0\t0\t/gone\tnpm start\nnotes\t1\t0\t0\t/gone\t\n"
        try writeDesksFile(h, before)
        let r = h.run(["desk-rename", "notes", "website"])
        #expect(r.exitCode == 7, "\(r.stderr)")
        #expect(desksFile(h) == before)
        #expect(h.tmux(["list-sessions"]).exitCode != 0, "desk-rename must never start a server")
    }

    /// With the server up, a closed desk that is not permanent has exited: its line waits only for the
    /// exit path to remove it, so it is no desk to rename. Renaming it would keep the line for good.
    @Test func aDeskThatHasJustExitedIsNotRenamed() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        h.setEnvironment("MACMOSH_HOOK_DELAY", "5")
        _ = h.run(["start"])
        #expect(h.run(["desk-new", "website", h.home.path, "--command", "echo hi"]).exitCode == 0)
        typeExit(h, "=website:")
        try wait(h) { !isOpen(h, "website") }
        #expect(defined(h, "website"), "the exit path ran before the rename")
        let before = desksFile(h)
        let r = h.run(["desk-rename", "website", "notes"])
        #expect(r.exitCode == 4, "\(r.stderr)")
        #expect(desksFile(h) == before)
        try wait(h) { !defined(h, "website") }
        #expect(!defined(h, "notes"))
    }

    /// tmux matches "=name" against an attached client's tty name when no session has that name, so a
    /// desk named like a client's tty must not stand for the session that client shows.
    @Test func aNameLikeAnAttachedClientsTtyIsNotThatClientsDesk() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        #expect(h.run(["desk-new", "website", h.home.path]).exitCode == 0)
        // A client attached to website through a terminal of its own, as mosh attaches one.
        _ = h.shell("(sleep 60 | script -q /dev/null env TERM=xterm-256color tmux -L \"$MACMOSH_SOCKET\""
            + " attach-session -t =website"
            + " >/dev/null 2>&1 &)")
        var tty = ""
        try wait(h) {
            tty = h.tmux(["list-clients", "-F", "#{client_tty}"]).stdout
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return !tty.isEmpty
        }
        let client = (tty as NSString).lastPathComponent
        let websiteLine = try #require(line(h, "website"))

        // No desk has the client's name.
        let r = h.run(["desk-rename", client, "notes"])
        #expect(r.exitCode == 4, "\(r.stderr)")
        #expect(sessions(h) == ["website"])
        #expect(desksFile(h) == websiteLine + "\n")
        let windows = { h.tmux(["list-windows", "-a", "-F", "#{session_name}:#{window_index}"]).stdout }
        let websiteWindows = windows()
        let removed = h.run(["desk-remove", client, "--kill"])
        #expect(removed.exitCode == 4, "\(removed.stderr)")
        #expect(removed.stderr.contains("no such desk"), "\(removed.stderr)")
        #expect(sessions(h) == ["website"])
        let added = h.run(["window-new", client])
        #expect(added.exitCode == 4, "\(added.stderr)")
        #expect(windows() == websiteWindows)
        let attached = h.run(["attach", client])
        #expect(attached.exitCode == 4, "\(attached.stderr)")
        #expect(attached.stderr.contains("no such desk"), "\(attached.stderr)")
        #expect(sessions(h) == ["website"])
        #expect(windows() == websiteWindows)
        #expect(desksFile(h) == websiteLine + "\n")

        // A closed permanent desk has it: only its line is renamed.
        try writeDesksFile(h, desksFile(h) + "\(client)\t1\t0\t1\t/gone\t\n")
        #expect(h.run(["desk-rename", client, "notes"]).exitCode == 0)
        #expect(sessions(h) == ["website"])
        #expect(desksFile(h) == websiteLine + "\nnotes\t1\t0\t1\t/gone\t\n")

        // And a new name like the client's is free.
        #expect(h.run(["desk-rename", "notes", client]).exitCode == 0)
        #expect(sessions(h) == ["website"])
    }

    /// A kept desk types "<script> keep <name>" into its shell, which may run it only after a rename.
    /// keep then finds the desk by the session it runs in.
    @Test func aKeptDeskRenamedBeforeItsShellRunsKeepStillStartsItsCommand() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        try writeDesksFile(h, "api2\t1\t1\t0\t\(h.home.path)\techo run >> runs.txt; sleep 4343\n")
        #expect(h.tmux(["new-session", "-d", "-s", "api2", "-c", h.home.path]).exitCode == 0)
        _ = h.tmux(["send-keys", "-t", "=api2:", "-l", "--", "'\(h.scriptURL.path)' keep api"])
        _ = h.tmux(["send-keys", "-t", "=api2:", "Enter"])
        let runs = { (try? String(contentsOf: h.home.appendingPathComponent("runs.txt"), encoding: .utf8)) ?? "" }
        try wait(h) { runs() == "run\n" }
        #expect(!hostLog(h).contains("no such desk: api"))
    }

    /// The reopen loop reads the list it opened. A desk renamed while it runs is opened by a second pass.
    @Test func aDeskRenamedWhileTheServerReopensDesksIsOpened() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        try writeDesksFile(h, "alpha\t1\t0\t0\t\(h.home.path)\t\ngamma\t1\t0\t1\t\(h.home.path)\t\n")
        let real = h.shell("command -v tmux").stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        // A tmux that, as alpha is made, renames gamma to delta in the list the way desk-rename does.
        try h.stub("tmux", script: """
            case " $* " in
                *" new-session "*" alpha "*)
                    if [ ! -e "$HOME/renamed" ]; then
                        : > "$HOME/renamed"
                        f="$HOME/.macmosh/desks.tsv"
                        /usr/bin/sed 's/^gamma\t/delta\t/' "$f" > "$f.x" && /bin/mv "$f.x" "$f"
                    fi
                    ;;
            esac
            exec '\(real)' "$@"
            """)
        #expect(h.run(["start"]).exitCode == 0)
        #expect(FileManager.default.fileExists(atPath: h.home.appendingPathComponent("renamed").path))
        #expect(sessions(h) == ["alpha", "delta"])
    }

    @Test func ifTheListCantBeWrittenTheSessionGetsItsNameBack() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        #expect(h.run(["desk-new", "website", h.home.path]).exitCode == 0)
        let before = desksFile(h)
        // An awk that fails only for the rename's rewrite of the list.
        try h.stub("awk", script: """
            for a in "$@"; do case "$a" in *substr*) exit 1 ;; esac; done
            exec /usr/bin/awk "$@"
            """)
        let r = h.run(["desk-rename", "website", "notes"])
        #expect(r.exitCode == 1)
        #expect(sessions(h) == ["website"])
        #expect(desksFile(h) == before)
        #expect(!FileManager.default.fileExists(atPath: h.home.appendingPathComponent(".macmosh/lock").path))
    }

    // MARK: - Names are text

    /// awk reads "7" and "007", or "1e3" and "1000", as the same number. The rename compares names as
    /// text, so it never touches the other desk's line or takes its name for a match.
    @Test(arguments: zip(["7", "007", "1e3", "1000"], ["007", "7", "1000", "1e3"]))
    func aNameThatLooksLikeANumberIsOnlyItself(one: String, other: String) throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        #expect(h.run(["desk-new", other, h.home.path]).exitCode == 0)
        let otherLine = try #require(line(h, other))

        // Not a desk, though awk would read it as the other's number.
        #expect(h.run(["desk-rename", one, "fresh"]).exitCode == 4)
        #expect(desksFile(h) == otherLine + "\n")

        // Free, for the same reason.
        #expect(h.run(["desk-new", "spare", h.home.path]).exitCode == 0)
        #expect(h.run(["desk-rename", "spare", one]).exitCode == 0)
        #expect(defined(h, one))
        #expect(line(h, other) == otherLine)

        // And renaming it away leaves the other alone.
        #expect(h.run(["desk-rename", one, "moved"]).exitCode == 0)
        #expect(line(h, other) == otherLine)
        #expect(isOpen(h, other))
        #expect(sessions(h) == [other, "moved"].sorted())
    }

    // MARK: - Nothing is lost by a rename

    /// A rename closes no session, so the exit path never runs for it.
    @Test func theExitPathLeavesARenamedDeskAlone() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        #expect(h.run(["desk-new", "website", h.home.path]).exitCode == 0)
        #expect(h.run(["desk-rename", "website", "notes"]).exitCode == 0)
        let renamed = try #require(line(h, "notes"))
        try proveTheHookHasRun(h)
        #expect(line(h, "notes") == renamed)
        #expect(isOpen(h, "notes"))
        #expect(!hostLog(h).contains("desk-closed\tremoved notes"))
        #expect(!hostLog(h).contains("desk-closed\tremoved website"))
    }

    /// A desk exits; inside the exit path's wait another desk takes its name. The exit path then finds
    /// a desk of that name open, and keeps its definition.
    @Test func aDeskRenamedToTheNameOfOneThatJustExitedKeepsItsDefinition() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        // A longer wait than the harness's, so the rename surely lands inside it.
        h.setEnvironment("MACMOSH_HOOK_DELAY", "5")
        _ = h.run(["start"])
        #expect(h.run(["desk-new", "website", h.home.path]).exitCode == 0)
        #expect(h.run(["desk-new", "notes", h.home.path, "--command", "echo notes"]).exitCode == 0)
        let notes = try #require(line(h, "notes"))

        typeExit(h, "=website:")
        try wait(h) { !isOpen(h, "website") }
        #expect(defined(h, "website"), "the exit path ran before the rename")
        #expect(h.run(["desk-rename", "notes", "website"]).exitCode == 0)

        try wait(h) { hostLog(h).contains("kept website: open again") }
        #expect(line(h, "website") == "website" + notes.dropFirst("notes".count))
        #expect(isOpen(h, "website"))
        #expect(!defined(h, "notes"))
        #expect(!hostLog(h).contains("removed website"))
    }

    @Test func renamesRemovesAndTheExitPathTakeTurnsWithTheList() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        let gone = (1...8).map { "d\($0)" }
        let renamed = (1...6).map { "r\($0)" }
        try writeDesksFile(h, gone.map { "\($0)\t0\t0\t0\t/gone\t\n" }.joined()
            + renamed.map { "\($0)\t0\t0\t1\t/gone\techo \($0)\n" }.joined()
            + "stay\t0\t0\t1\t/gone\t\n")
        let pid = h.tmux(["display-message", "-p", "#{pid}"]).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let script = h.scriptURL.path
        // Half the d lines go through the exit path and half through desk-remove, while every r line is
        // renamed, all at once.
        var calls: [String] = []
        for (i, name) in gone.enumerated() {
            calls.append(i % 2 == 0 ? "desk-closed \(name) \(pid)" : "desk-remove \(name)")
        }
        for name in renamed { calls.append("desk-rename \(name) s\(name.dropFirst())") }
        var lines = calls.enumerated().map { "'\(script)' \($0.element) & p\($0.offset)=$!" }
        lines.append((0..<calls.count).map { "wait $p\($0) || echo failed" }.joined(separator: "; "))
        let out = h.shell(lines.joined(separator: "\n"))
        #expect(out.stdout == "", "a writer failed: \(out.stdout) \(out.stderr)")

        let expected = (1...6).map { "s\($0)\t0\t0\t1\t/gone\techo r\($0)" } + ["stay\t0\t0\t1\t/gone\t"]
        #expect(desksFile(h).split(separator: "\n").map(String.init).sorted() == expected.sorted())
        #expect(desksFile(h).hasSuffix("\n"))
        #expect(!FileManager.default.fileExists(atPath: h.home.appendingPathComponent(".macmosh/lock").path))
    }
}
}
