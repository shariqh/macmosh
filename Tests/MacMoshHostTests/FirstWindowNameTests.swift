import Foundation
import Testing
@testable import MacMoshKit

extension HostScriptTests {
/// A new desk's first window, named as the desk is made (issue 163, script 0.12.0): `desk-new <name> <folder>
/// --window-name <name>`. The name keeps the window-name rule, or is exactly the desk's own name, since a desk name
/// can be 64 characters and a window name 32. It is checked before anything is made; a refused one is exit 6 with
/// the window-name rule's words. Without the option the desk is made as before.
///
/// man tmux (3.8), new-session: "-n and shell-command are invalid if -t is used." The script makes every desk
/// with -t, so it names the window with rename-window once the session is made, before the startup command is
/// typed. automatic-rename: "This flag is automatically disabled for an individual window when a name is
/// specified at creation with new-window or new-session, or later with rename-window, or with a terminal escape
/// sequence." So the name stays while the program in the window changes, which these tests show.
///
/// Every wait ends as soon as its condition holds. The limits are long because CI runners are slow.
@Suite struct FirstWindowNameTests {
    private static let rule = "macmosh-host: a window name is 1 to 32 characters, each a letter, a digit, a space, -, _ or a full stop, and it can't start or end with a space\n"

    private func desksFile(_ h: HostHarness) -> String {
        (try? String(contentsOf: h.home.appendingPathComponent(".macmosh/desks.tsv"), encoding: .utf8)) ?? ""
    }

    private func hostLog(_ h: HostHarness) -> String {
        (try? String(contentsOf: h.home.appendingPathComponent(".macmosh/host.log"), encoding: .utf8)) ?? ""
    }

    private func wait(_ h: HostHarness, seconds: Double = 30, line: UInt = #line, _ condition: () -> Bool) throws {
        do {
            try waitFor(seconds: seconds, condition)
        } catch {
            let log = hostLog(h).split(separator: "\n").suffix(20).joined(separator: "\n")
            Issue.record(Comment(rawValue: "timed out after \(Int(seconds)) s (FirstWindowNameTests.swift:\(line))\n"
                + "[desks.tsv]\n\(desksFile(h))[host.log]\n\(log)\n[sessions]\n\(h.sessionNames())"))
            throw error
        }
    }

    /// The id of the session with exactly this name, or nil.
    private func lookup(_ h: HostHarness, _ name: String) -> String? {
        let text = h.tmux(["list-sessions", "-F", "#{session_id}|#{session_name}"]).stdout
        let line = text.split(separator: "\n").first { $0.hasSuffix("|" + name) }
        return line.map { String($0.split(separator: "|")[0]) }
    }

    private func sid(_ h: HostHarness, _ name: String) throws -> String {
        try #require(lookup(h, name), "no session \(name): \(h.sessionNames())")
    }

    /// Each window of a session as `<window id>\t<name>\t<automatic-rename>`.
    private func windows(_ h: HostHarness, _ sid: String) -> [String] {
        h.tmux(["list-windows", "-t", sid + ":", "-F", "#{window_id}\t#{window_name}\t#{automatic-rename}"]).stdout
            .split(separator: "\n").map(String.init)
    }

    private func firstName(_ h: HostHarness, _ sid: String) -> String? {
        windows(h, sid).first.map { String($0.split(separator: "\t", omittingEmptySubsequences: false)[1]) }
    }

    private func program(_ h: HostHarness, _ sid: String) -> String {
        h.tmux(["display-message", "-p", "-t", sid + ":", "#{pane_current_command}"]).stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func type(_ h: HostHarness, _ target: String, _ text: String) {
        _ = h.tmux(["send-keys", "-t", target, "-l", "--", text])
        _ = h.tmux(["send-keys", "-t", target, "Enter"])
    }

    private func windowLines(_ report: String, _ desk: String) -> [String] {
        report.split(separator: "\n").map(String.init).filter { $0.hasPrefix("window\t\(desk)\t") }
    }

    // MARK: - Naming the first window

    @Test func theFirstWindowHasTheNameAndKeepsItWhenTheProgramChanges() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        let r = h.run(["desk-new", "website", h.home.path, "--window-name", "build logs"])
        #expect(r.exitCode == 0, "\(r.stderr)")
        #expect(r.stdout.isEmpty && r.stderr.isEmpty)
        let desk = try sid(h, "website")
        let shown = windows(h, desk)
        #expect(shown.count == 1)
        #expect(shown.first?.hasSuffix("\tbuild logs\t0") == true, "\(shown)")
        #expect(h.tmux(["show-options", "-w", "-t", desk + ":", "automatic-rename"]).stdout == "automatic-rename off\n")
        #expect(windowLines(h.run(["status"]).stdout, "website") == ["window\twebsite\t0\tbuild logs"])

        // Another program in the window: the name stays.
        type(h, desk + ":", "sleep 4343")
        try wait(h) { program(h, desk) == "sleep" }
        Thread.sleep(forTimeInterval: 1.5)
        #expect(firstName(h, desk) == "build logs")
        #expect(windowLines(h.run(["status"]).stdout, "website") == ["window\twebsite\t0\tbuild logs"])

        // The log keeps its line and never has the name.
        #expect(hostLog(h).contains("\tdesk-new\tcreated website\n"), "\(hostLog(h))")
        #expect(!hostLog(h).contains("build logs"))
    }

    /// "Same name as the desk" works for every desk name: a desk name can be 64 characters and a window name 32,
    /// so the desk's own name is taken whole. A name of more than 32 that is not the desk's is refused.
    @Test func aDeskNameLongerThan32IsTakenAsItsOwnWindowsName() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        let long = "a-very-long_desk-name-" + String(repeating: "x", count: 42)
        #expect(long.count == 64)
        let r = h.run(["desk-new", long, h.home.path, "--window-name", long])
        #expect(r.exitCode == 0, "\(r.stderr)")
        #expect(firstName(h, try sid(h, long)) == long)
        let report = h.run(["status"]).stdout
        #expect(windowLines(report, long) == ["window\t\(long)\t0\t\(long)"], "\(report)")
        let parsed = try HostStatus.parse(report)
        #expect(parsed.desks.first { $0.name.value == long }?.windows.map(\.name) == [long])

        // A short desk name as its own window's name, and one with a leading dash, as an older desk may have.
        #expect(h.run(["desk-new", "api", h.home.path, "--window-name", "api"]).exitCode == 0)
        #expect(firstName(h, try sid(h, "api")) == "api")
        #expect(h.run(["desk-new", "-old", h.home.path, "--window-name", "-old"]).exitCode == 0)
        #expect(firstName(h, try sid(h, "-old")) == "-old")

        // 33 characters that are not the desk's name: refused, nothing made.
        let other = String(repeating: "y", count: 33)
        let refused = h.run(["desk-new", "notes", h.home.path, "--window-name", other])
        #expect(refused.exitCode == 6)
        #expect(refused.stderr == Self.rule)
        #expect(lookup(h, "notes") == nil)
        // Another desk's long name is not this desk's name.
        let taken = h.run(["desk-new", "blog", h.home.path, "--window-name", long])
        #expect(taken.exitCode == 6)
        #expect(lookup(h, "blog") == nil)
    }

    /// A name that breaks the rule is refused before anything is made: exit 6 with the rule's words, no session, no
    /// line in the desk list, and the log says why without the name.
    @Test func aBadNameIsRefusedAndNothingIsMade() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        let refused = [
            "", " ", " lead", "trail ", "a\tb", "a\nb", "a#b", "#{pane_pid}", "it's", "a;b", "a/b", "caf\u{e9}",
            "a:b", "a,b", "a$b", String(repeating: "x", count: 33),
        ]
        for wanted in refused {
            let r = h.run(["desk-new", "website", h.home.path, "--window-name", wanted])
            #expect(r.exitCode == 6, "\(wanted.debugDescription): \(r.stderr)")
            #expect(r.stderr == Self.rule, "\(wanted.debugDescription): \(r.stderr)")
        }
        #expect(h.sessionNames().isEmpty, "\(h.sessionNames())")
        #expect(desksFile(h).isEmpty, "\(desksFile(h))")
        #expect(hostLog(h).contains("\tdesk-new\trefused: bad window name\n"), "\(hostLog(h))")
        #expect(!hostLog(h).contains("lead") && !hostLog(h).contains("pane_pid"))

        // The desk's own name is checked first, with its own words.
        let bad = h.run(["desk-new", "web site", h.home.path, "--window-name", "a#b"])
        #expect(bad.exitCode == 6)
        #expect(bad.stderr == "macmosh-host: a desk name uses letters, digits, - and _ only, up to 64 characters\n")

        // The option needs its value.
        let missing = h.run(["desk-new", "website", h.home.path, "--window-name"])
        #expect(missing.exitCode == 2)
        #expect(missing.stderr == "macmosh-host: --window-name needs a value\n")
        #expect(h.sessionNames().isEmpty)
        #expect(desksFile(h).isEmpty)
    }

    /// Without the option the desk is as before: tmux names its window after its program, and the line is the same.
    @Test func withoutTheOptionTheDeskIsAsBefore() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        #expect(h.run(["desk-new", "notes", h.home.path]).exitCode == 0)
        let desk = try sid(h, "notes")
        try wait(h) { !program(h, desk).isEmpty && firstName(h, desk) == program(h, desk) }
        #expect(windows(h, desk).first?.hasSuffix("\t1") == true, "\(windows(h, desk))")
        #expect(h.tmux(["show-options", "-w", "-t", desk + ":", "automatic-rename"]).stdout == "")
        #expect(desksFile(h) == "notes\t1\t0\t0\t\(h.home.path)\t\n")
    }

    /// With a startup command, the name is in place before the command is typed: the command reads its window's
    /// name, and finds this one. The command still runs.
    @Test func withACommandTheNameIsSetFirstAndTheCommandRuns() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        let seen = h.home.appendingPathComponent("seen.txt")
        let command = "tmux -L \(h.socket) display-message -p -t \"$TMUX_PANE\" '#{window_name}' > seen.txt; sleep 4343"
        let r = h.run(["desk-new", "api", h.home.path, "--command", command, "--window-name", "api server"])
        #expect(r.exitCode == 0, "\(r.stderr)")
        let desk = try sid(h, "api")
        try wait(h) { ((try? String(contentsOf: seen, encoding: .utf8)) ?? "").hasSuffix("\n") }
        #expect((try? String(contentsOf: seen, encoding: .utf8)) == "api server\n")
        try wait(h) { program(h, desk) == "sleep" }
        Thread.sleep(forTimeInterval: 1.5)
        #expect(firstName(h, desk) == "api server")
        // The desk list's line is as it is without the option.
        #expect(desksFile(h) == "api\t1\t0\t0\t\(h.home.path)\t\(command)\n")
    }

    /// With --keep, the window is named, and the kept command runs in it.
    @Test func withKeepTheNameIsSetAndTheCommandIsKept() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        let r = h.run(["desk-new", "worker", h.home.path, "--keep", "--window-name", "queue.1", "--command", "echo run >> runs.txt; sleep 4343"])
        #expect(r.exitCode == 0, "\(r.stderr)")
        let desk = try sid(h, "worker")
        let runs = h.home.appendingPathComponent("runs.txt")
        try wait(h, seconds: 40) { FileManager.default.fileExists(atPath: runs.path) }
        Thread.sleep(forTimeInterval: 1.5)
        #expect(firstName(h, desk) == "queue.1")
        #expect(desksFile(h) == "worker\t1\t1\t0\t\(h.home.path)\techo run >> runs.txt; sleep 4343\n")
    }

    /// A desk is made as asked or not at all: when the window can't be named, the session made here is ended and no
    /// line is left in the desk list, as when the session can't be made.
    @Test func aWindowThatCantBeNamedLeavesNoDesk() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        try h.stub("tmux", script: """
            if [ "$3" = "rename-window" ]; then exit 1; fi
            exec /usr/bin/env PATH="${PATH#*:}" tmux "$@"
            """)
        let r = h.run(["desk-new", "website", h.home.path, "--window-name", "build logs", "--command", "echo ran >> ran.txt"])
        #expect(r.exitCode == 1)
        #expect(r.stderr == "macmosh-host: could not create the desk\n")
        #expect(lookup(h, "website") == nil, "\(h.sessionNames())")
        #expect(h.sessionNames().isEmpty, "\(h.sessionNames())")
        #expect(desksFile(h).isEmpty, "a definition was left behind: \(desksFile(h))")
        #expect(hostLog(h).contains("\tdesk-new\tfailed: website could not be created\n"), "\(hostLog(h))")
        Thread.sleep(forTimeInterval: 1)
        #expect(!FileManager.default.fileExists(atPath: h.home.appendingPathComponent("ran.txt").path))
        #expect(!FileManager.default.fileExists(atPath: h.home.appendingPathComponent(".macmosh/lock").path))
        // The name is free again.
        try FileManager.default.removeItem(at: h.stubFolder.appendingPathComponent("tmux"))
        #expect(h.run(["desk-new", "website", h.home.path, "--window-name", "build logs"]).exitCode == 0)
        #expect(firstName(h, try sid(h, "website")) == "build logs")
    }

    /// The name is not stored: a permanent desk that ended comes back as one fresh window that tmux names.
    @Test func theNameIsNotKeptWhenTheDeskComesBack() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        #expect(h.run(["desk-new", "notes", h.home.path, "--permanent", "--window-name", "notes.0"]).exitCode == 0)
        #expect(desksFile(h) == "notes\t1\t0\t1\t\(h.home.path)\t\n")
        let first = try sid(h, "notes")
        type(h, first + ":", "exit")
        try wait(h) { h.sessionNames().isEmpty }
        try wait(h) { hostLog(h).contains("desk-closed\tkept notes: permanent") }
        #expect(h.run(["attach", "--dry-run", "notes"]).exitCode == 0)
        let fresh = try sid(h, "notes")
        #expect(windows(h, fresh).count == 1)
        #expect(firstName(h, fresh) != "notes.0")
        #expect(windows(h, fresh).first?.hasSuffix("\t1") == true, "\(windows(h, fresh))")
    }

    @Test func theUsageNamesTheOption() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        let r = h.run(["desk-new", "website"])
        #expect(r.exitCode == 2)
        #expect(r.stderr == "macmosh-host: usage: desk-new <name> <folder> [--no-reopen] [--permanent] [--keep] [--command <text>] [--window-name <name>]\n")
        let help = h.run([])
        #expect(help.stderr.contains("desk-new <name> <folder> [--no-reopen] [--permanent] [--keep] [--command <text>]\n"
            + "            [--window-name <name>]"), "\(help.stderr)")
    }
}
}
