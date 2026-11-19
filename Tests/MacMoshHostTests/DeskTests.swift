import Foundation
import Testing

@Suite(.serialized) struct DeskTests {
    private func makeFolder(_ h: HostHarness, _ name: String) throws -> URL {
        let url = h.home.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func desksFile(_ h: HostHarness) -> String? {
        try? String(contentsOf: h.home.appendingPathComponent(".macmosh/desks.tsv"), encoding: .utf8)
    }

    /// A `launchctl` stand-in that records its arguments and then runs the script's `start`,
    /// the way the real login agent would.
    private func loginAgentStub(_ h: HostHarness) throws {
        try h.stub("launchctl", script: """
            echo "$*" >> "$HOME/launchctl.log"
            if [ "$1" = "kickstart" ]; then "\(h.scriptURL.path)" start; fi
            exit 0
            """)
    }

    private func nobodyAtTheScreen(_ h: HostHarness) throws {
        try h.stub("stat", script: """
            if [ "$1" = "-f" ] && [ "$2" = "%Su" ] && [ "$3" = "/dev/console" ]; then
                echo root
                exit 0
            fi
            exec /usr/bin/stat "$@"
            """)
    }

    @Test func folderWithSpacesQuotesAndDollar() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        let odd = h.home.appendingPathComponent("My \"Proj\" $HOME it's é")
        try FileManager.default.createDirectory(at: odd, withIntermediateDirectories: true)
        _ = h.run(["start"])
        #expect(h.run(["desk-new", "odd", odd.path]).exitCode == 0)
        let path = h.tmux(["display-message", "-p", "-t", "=odd:", "#{session_path}"]).stdout
        #expect(path.trimmingCharacters(in: .newlines) == odd.path)
    }

    @Test func startupCommandIsTypedLiterally() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        _ = h.run(["desk-new", "typed", h.home.path, "--command", "echo \"$((6*7)) Enter C-c\" > typed.txt"])
        try waitFor(seconds: 5) { FileManager.default.fileExists(atPath: h.home.appendingPathComponent("typed.txt").path) }
        let text = try String(contentsOf: h.home.appendingPathComponent("typed.txt"), encoding: .utf8)
        #expect(text == "42 Enter C-c\n")
    }

    @Test func deskNewWritesTheDefinitionAndTheSession() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        let folder = try makeFolder(h, "site")
        _ = h.run(["start"])
        #expect(h.run(["desk-new", "website", folder.path]).exitCode == 0)
        #expect(desksFile(h) == "website\t0\t0\t\(folder.path)\t\n")
        #expect(h.tmux(["has-session", "-t", "=website"]).exitCode == 0)
        let report = h.run(["status"]).stdout
        #expect(report.contains("\ndesk\twebsite\t1\t0\n"))
        #expect(report.contains("\ndef\twebsite\t0\t0\t\(folder.path)\t\n"))
    }

    @Test func deskNewStoresTheFlagsAndTheCommand() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        let folder = try makeFolder(h, "site")
        _ = h.run(["start"])
        #expect(h.run(["desk-new", "web", folder.path, "--reopen", "--keep", "--command", "npm run dev"]).exitCode == 0)
        #expect(desksFile(h) == "web\t1\t1\t\(folder.path)\tnpm run dev\n")
    }

    @Test func deskNamesAreRestricted() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        for name in ["bad name", "a;b", "é", String(repeating: "a", count: 65)] {
            #expect(h.run(["desk-new", name, h.home.path]).exitCode == 6, "name: \(name)")
        }
        #expect(h.run(["desk-new", "", h.home.path]).exitCode == 6)
        #expect(desksFile(h) == nil)
        #expect(h.run(["desk-new", String(repeating: "a", count: 64), h.home.path]).exitCode == 0)
    }

    @Test func tabOrNewlineIsRefused() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        let tabbed = try makeFolder(h, "with\ttab")
        _ = h.run(["start"])
        #expect(h.run(["desk-new", "a", tabbed.path]).exitCode == 6)
        #expect(h.run(["desk-new", "b", h.home.path, "--command", "echo\thi"]).exitCode == 6)
        #expect(h.run(["desk-new", "c", h.home.path, "--command", "echo\nhi"]).exitCode == 6)
        #expect(h.run(["desk-new", "d", h.home.path + "\n"]).exitCode == 6)
        #expect(desksFile(h) == nil)
        #expect(h.tmux(["list-sessions"]).stdout.isEmpty)
    }

    @Test func missingFolderIsRefused() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        #expect(h.run(["desk-new", "gone", h.home.appendingPathComponent("nope").path]).exitCode == 6)
        #expect(h.run(["desk-new", "rel", "relative/folder"]).exitCode == 6)
        #expect(h.tmux(["has-session", "-t", "=gone"]).exitCode == 1)
        #expect(desksFile(h) == nil)
    }

    @Test func duplicateDeskFailsCleanly() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        #expect(h.run(["desk-new", "dup", h.home.path]).exitCode == 0)
        #expect(h.run(["desk-new", "dup", h.home.path]).exitCode == 7)
        #expect(desksFile(h)?.split(separator: "\n").count == 1)
    }

    @Test func twoWritersDoNotCorruptTheList() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        let script = h.scriptURL.path
        let out = h.shell("""
            '\(script)' desk-new one '\(h.home.path)' & p1=$!
            '\(script)' desk-new two '\(h.home.path)' & p2=$!
            wait $p1; echo $?; wait $p2; echo $?
            """).stdout
        #expect(out == "0\n0\n")
        let lines = (desksFile(h) ?? "").split(separator: "\n").map(String.init)
        #expect(lines.count == 2)
        for line in lines { #expect(line.split(separator: "\t", omittingEmptySubsequences: false).count == 5) }
    }

    @Test func twoWritersWithTheSameNameGetOneDesk() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        let script = h.scriptURL.path
        let out = h.shell("""
            '\(script)' desk-new same '\(h.home.path)' & p1=$!
            '\(script)' desk-new same '\(h.home.path)' & p2=$!
            wait $p1; r1=$?; wait $p2; r2=$?; echo "$r1 $r2"
            """).stdout
        #expect(out == "0 7\n" || out == "7 0\n")
        #expect(desksFile(h)?.split(separator: "\n").count == 1)
    }

    @Test func aStaleLockIsTakenOver() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        let lock = h.home.appendingPathComponent(".macmosh/lock")
        try FileManager.default.createDirectory(at: lock, withIntermediateDirectories: true)
        // A lock folder from a writer that died a minute ago.
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-60)],
                                              ofItemAtPath: lock.path)
        #expect(h.run(["desk-new", "late", h.home.path]).exitCode == 0)
        #expect(!FileManager.default.fileExists(atPath: lock.path))
    }

    @Test func aFreshLockMakesTheWriterWaitAndTheLockIsReleased() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        let lock = h.home.appendingPathComponent(".macmosh/lock")
        try FileManager.default.createDirectory(at: lock, withIntermediateDirectories: true)
        // Another writer lets go after a second.
        _ = h.shell("(sleep 1; rmdir '\(lock.path)') >/dev/null 2>&1 &")
        #expect(h.run(["desk-new", "waited", h.home.path]).exitCode == 0)
        #expect(desksFile(h)?.hasPrefix("waited\t") == true)
        #expect(!FileManager.default.fileExists(atPath: lock.path))
    }

    @Test func aFailedWriteStillReleasesTheLock() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        #expect(h.run(["desk-new", "dup", h.home.path]).exitCode == 0)
        #expect(h.run(["desk-new", "dup", h.home.path]).exitCode == 7)
        #expect(!FileManager.default.fileExists(atPath: h.home.appendingPathComponent(".macmosh/lock").path))
    }

    @Test func deskRemoveKeepsTheSessionUnlessKill() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        _ = h.run(["desk-new", "a", h.home.path])
        _ = h.run(["desk-new", "b", h.home.path])
        #expect(h.run(["desk-remove", "a"]).exitCode == 0)
        #expect(h.tmux(["has-session", "-t", "=a"]).exitCode == 0)
        #expect(h.run(["desk-remove", "b", "--kill"]).exitCode == 0)
        #expect(h.tmux(["has-session", "-t", "=b"]).exitCode == 1)
        #expect(desksFile(h) == "")
        #expect(h.run(["desk-remove", "nothing"]).exitCode == 4)
    }

    @Test func deskRemoveNeverStartsAServer() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        #expect(h.run(["desk-remove", "x", "--kill"]).exitCode == 4)
        #expect(h.tmux(["list-sessions"]).exitCode != 0)
    }

    @Test func windowNewAddsAWindow() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        _ = h.run(["desk-new", "w", h.home.path])
        #expect(h.run(["status"]).stdout.contains("\ndesk\tw\t1\t0\n"))
        #expect(h.run(["window-new", "w"]).exitCode == 0)
        #expect(h.run(["status"]).stdout.contains("\ndesk\tw\t2\t0\n"))
        #expect(h.run(["window-new", "nothing"]).exitCode == 4)
    }

    @Test func foldersListsFoldersOnly() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        let base = try makeFolder(h, "base")
        for name in ["b", "a", ".hidden"] {
            try FileManager.default.createDirectory(at: base.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        try "x".write(to: base.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
        let r = h.run(["folders", base.path])
        #expect(r.exitCode == 0)
        #expect(r.stdout == "a\nb\n")
        #expect(h.run(["folders", base.appendingPathComponent("nope").path]).exitCode == 6)
    }

    @Test func foldersAcceptsATilde() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        let projects = try makeFolder(h, "projects")
        for name in ["site", "api"] {
            try FileManager.default.createDirectory(at: projects.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        #expect(h.run(["folders", "~/projects"]).stdout == "api\nsite\n")
    }

    @Test func deskNewAcceptsATilde() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        let folder = try makeFolder(h, "projects")
        _ = h.run(["start"])
        #expect(h.run(["desk-new", "t", "~/projects"]).exitCode == 0)
        #expect(desksFile(h) == "t\t0\t0\t\(folder.path)\t\n")
    }

    @Test func reopenDesksComeBackOnStart() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        _ = h.run(["desk-new", "keepme", h.home.path, "--reopen"])
        _ = h.run(["desk-new", "dropme", h.home.path])
        _ = h.tmux(["kill-server"])
        #expect(h.run(["start"]).exitCode == 0)
        #expect(h.tmux(["has-session", "-t", "=keepme"]).exitCode == 0)
        #expect(h.tmux(["has-session", "-t", "=dropme"]).exitCode == 1)
    }

    @Test func startTwiceRecreatesNothing() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        _ = h.run(["desk-new", "r", h.home.path, "--reopen"])
        _ = h.tmux(["kill-session", "-t", "=r"])
        #expect(h.run(["start"]).exitCode == 0)
        #expect(h.tmux(["has-session", "-t", "=r"]).exitCode == 1)
    }

    @Test func attachRefusesWhenNobodyIsLoggedIn() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        try nobodyAtTheScreen(h)
        let r = h.run(["attach", "--dry-run", "x"])
        #expect(r.exitCode == 3)
        #expect((r.stdout + r.stderr).contains("Nobody is logged in"))
        #expect(h.tmux(["list-sessions"]).exitCode != 0)
    }

    @Test func attachAsksTheLoginAgent() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        try loginAgentStub(h)
        let r = h.run(["attach", "--dry-run", "x"])
        // No desk called x exists, but the server was asked for and is up now.
        #expect(r.exitCode == 4)
        #expect(h.tmux(["list-sessions"]).exitCode == 0)
        let log = try String(contentsOf: h.home.appendingPathComponent("launchctl.log"), encoding: .utf8)
        #expect(log == "kickstart gui/\(getuid())/io.github.shariqh.macmosh.host\n")
    }

    @Test func attachAsksTheLoginAgentForADefinedDesk() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        _ = h.run(["desk-new", "x", h.home.path])
        _ = h.tmux(["kill-server"])
        try loginAgentStub(h)
        let r = h.run(["attach", "--dry-run", "x"])
        #expect(r.exitCode == 0)
        #expect(r.stdout == "ok\n")
        let log = try String(contentsOf: h.home.appendingPathComponent("launchctl.log"), encoding: .utf8)
        #expect(log == "kickstart gui/\(getuid())/io.github.shariqh.macmosh.host\n")
    }

    @Test func attachNeverStartsTheServerItself() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        let r = h.run(["attach", "--dry-run", "x"])
        #expect(r.exitCode == 5)
        #expect(h.tmux(["list-sessions"]).exitCode != 0)
    }

    @Test func onlyStartStartsTheServer() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        _ = h.run(["desk-new", "known", h.home.path])
        _ = h.tmux(["kill-server"])
        let before = desksFile(h)
        #expect(h.run(["desk-new", "fresh", h.home.path]).exitCode == 5)
        #expect(h.tmux(["list-sessions"]).exitCode != 0)
        #expect(h.run(["window-new", "known"]).exitCode == 5)
        #expect(h.tmux(["list-sessions"]).exitCode != 0)
        #expect(desksFile(h) == before)
    }

    @Test func deskNewRefusesWhenNobodyIsLoggedIn() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        try nobodyAtTheScreen(h)
        #expect(h.run(["desk-new", "x", h.home.path]).exitCode == 3)
        #expect(h.run(["window-new", "x"]).exitCode == 3)
        #expect(h.tmux(["list-sessions"]).exitCode != 0)
    }

    @Test func attachUnknownDeskExits4() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        #expect(h.run(["attach", "--dry-run", "nothing"]).exitCode == 4)
        #expect(h.run(["attach", "--dry-run", "bad name"]).exitCode == 4)
        #expect(h.run(["attach"]).exitCode == 2)
    }

    @Test func attachCreatesADefinedDeskThatIsClosed() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        _ = h.run(["desk-new", "closed", h.home.path])
        _ = h.tmux(["kill-session", "-t", "=closed"])
        #expect(h.tmux(["has-session", "-t", "=closed"]).exitCode == 1)
        let r = h.run(["attach", "--dry-run", "closed"])
        #expect(r.exitCode == 0)
        #expect(r.stdout == "ok\n")
        #expect(h.tmux(["has-session", "-t", "=closed"]).exitCode == 0)
    }

    @Test func attachToAnOpenDeskDoesNotRunTheStartupCommandAgain() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        _ = h.run(["desk-new", "once", h.home.path, "--command", "echo x >> once.txt"])
        try waitFor(seconds: 5) { FileManager.default.fileExists(atPath: h.home.appendingPathComponent("once.txt").path) }
        #expect(h.run(["attach", "--dry-run", "once"]).exitCode == 0)
        Thread.sleep(forTimeInterval: 0.5)
        let text = try String(contentsOf: h.home.appendingPathComponent("once.txt"), encoding: .utf8)
        #expect(text == "x\n")
    }

    @Test func restartServerNeedsYes() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        _ = h.run(["desk-new", "d", h.home.path])
        #expect(h.run(["restart-server"]).exitCode == 2)
        #expect(h.tmux(["has-session", "-t", "=d"]).exitCode == 0)
    }

    @Test func restartServerClosesDesksAndAsksTheLoginAgent() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        _ = h.run(["desk-new", "open", h.home.path])
        _ = h.run(["desk-new", "again", h.home.path, "--reopen"])
        try loginAgentStub(h)
        #expect(h.run(["restart-server", "--yes"]).exitCode == 0)
        #expect(h.tmux(["has-session", "-t", "=open"]).exitCode == 1)
        #expect(h.tmux(["has-session", "-t", "=again"]).exitCode == 0)
    }

    @Test func restartServerClosesNothingWhenNobodyIsLoggedIn() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        _ = h.run(["desk-new", "d", h.home.path])
        try nobodyAtTheScreen(h)
        #expect(h.run(["restart-server", "--yes"]).exitCode == 3)
        #expect(h.tmux(["has-session", "-t", "=d"]).exitCode == 0)
    }
}
