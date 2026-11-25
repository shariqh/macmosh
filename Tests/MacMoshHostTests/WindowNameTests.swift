import Foundation
import Testing
@testable import MacMoshKit

extension HostScriptTests {
/// Naming one window of a desk (issue 144): `window-name <desk> <window id> <name>` renames that window
/// by its id, and `window-name <desk> <window id> --auto` gives the name back to tmux, so the window is
/// named after its running program again. A name is 1 to 32 letters, digits, spaces, `-`, `_` and `.`,
/// and doesn't start or end with a space. The name shows in the status report's window lines, in every
/// view of the desk and in the bar tmux draws at the bottom of a tab.
///
/// man tmux (3.8), automatic-rename: "This flag is automatically disabled for an individual window when
/// a name is specified at creation with new-window or new-session, or later with rename-window, or with
/// a terminal escape sequence." Everything else about renaming here is what tmux 3.8 was seen to do.
///
/// Every wait ends as soon as its condition holds. The limits are long because CI runners are slow.
@Suite struct WindowNameTests {
    private func desksFile(_ h: HostHarness) -> String {
        (try? String(contentsOf: h.home.appendingPathComponent(".macmosh/desks.tsv"), encoding: .utf8)) ?? ""
    }

    private func defined(_ h: HostHarness, _ name: String) -> Bool {
        desksFile(h).split(separator: "\n").contains { $0.hasPrefix(name + "\t") }
    }

    private func hostLog(_ h: HostHarness) -> String {
        (try? String(contentsOf: h.home.appendingPathComponent(".macmosh/host.log"), encoding: .utf8)) ?? ""
    }

    private func typeExit(_ h: HostHarness, _ target: String) {
        _ = h.tmux(["send-keys", "-t", target, "-l", "--", "exit"])
        _ = h.tmux(["send-keys", "-t", target, "Enter"])
    }

    /// Types a command line into a window's shell.
    private func type(_ h: HostHarness, _ target: String, _ text: String) {
        _ = h.tmux(["send-keys", "-t", target, "-l", "--", text])
        _ = h.tmux(["send-keys", "-t", target, "Enter"])
    }

    private func wait(_ h: HostHarness, seconds: Double = 30, line: UInt = #line, _ condition: () -> Bool) throws {
        do {
            try waitFor(seconds: seconds, condition)
        } catch {
            let log = hostLog(h).split(separator: "\n").suffix(20).joined(separator: "\n")
            Issue.record(Comment(rawValue: "timed out after \(Int(seconds)) s (WindowNameTests.swift:\(line))\n"
                + "[desks.tsv]\n\(desksFile(h))[host.log]\n\(log)\n[sessions]\n\(h.sessionNames())\n[clients]\n\(h.clients())"))
            throw error
        }
    }

    /// Proves the exit hook has run since the step before: a throwaway desk's definition goes.
    private func proveTheHookHasRun(_ h: HostHarness) throws {
        #expect(h.run(["desk-new", "marker", h.home.path]).exitCode == 0)
        typeExit(h, "=marker:")
        try wait(h) { !defined(h, "marker") }
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

    private func windowIDs(_ h: HostHarness, _ sid: String) -> [String] {
        h.tmux(["list-windows", "-t", sid + ":", "-F", "#{window_id}"]).stdout.split(separator: "\n").map(String.init)
    }

    /// Each window of a session as `<window id>\t<name>\t<automatic-rename>`, as that session lists it.
    private func names(_ h: HostHarness, _ sid: String) -> [String] {
        h.tmux(["list-windows", "-t", sid + ":", "-F", "#{window_id}\t#{window_name}\t#{automatic-rename}"]).stdout
            .split(separator: "\n").map(String.init)
    }

    /// The name of one window, as the session with this id lists it, or nil.
    private func name(_ h: HostHarness, _ sid: String, _ window: String) -> String? {
        names(h, sid).first { $0.hasPrefix(window + "\t") }.map { String($0.split(separator: "\t", omittingEmptySubsequences: false)[1]) }
    }

    /// The program running in a window's pane.
    private func program(_ h: HostHarness, _ window: String) -> String {
        h.tmux(["display-message", "-p", "-t", window, "#{pane_current_command}"]).stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// What tmux draws for each window in the bar of a session: the window's id, a tab, and its entry
    /// in the window list, expanded from window-status-current-format for the window the session shows
    /// and from window-status-format for the others (`E:`, man tmux, FORMATS).
    private func barEntries(_ h: HostHarness, _ sid: String) -> [String: String] {
        let format = "#{window_id}\t#{?window_active,#{E:window-status-current-format},#{E:window-status-format}}"
        var found: [String: String] = [:]
        for line in h.tmux(["list-windows", "-t", sid + ":", "-F", format]).stdout.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            if parts.count == 2 { found[parts[0]] = parts[1] }
        }
        return found
    }

    /// The views of a desk, as `<view id>|<window shown>`, found by MacMosh's tag.
    private func views(_ h: HostHarness, of deskID: String) -> [String] {
        h.tmux(["list-sessions", "-F", "#{session_id}|#{window_id}|#{@macmosh-view}"]).stdout
            .split(separator: "\n").map(String.init)
            .filter { $0.hasSuffix("|" + deskID) }
            .map { $0.split(separator: "|").prefix(2).joined(separator: "|") }
            .sorted()
    }

    private func exists(_ h: HostHarness, _ sessionID: String) -> Bool { h.sessionFormat(sessionID, "#{session_id}") != nil }

    /// Opens a tab on the desk the way the app does: the script's attach, in a terminal of its own.
    private func openTab(_ h: HostHarness, _ label: String, _ arguments: [String]) throws {
        try h.startClient(label, ["/bin/bash", h.scriptURL.path, "attach"] + arguments)
    }

    /// Waits until the desk has `count` views and `clients` clients, and every view's tab has attached.
    private func ready(_ h: HostHarness, _ desk: String, views count: Int, clients: Int, line: UInt = #line) throws {
        try wait(h, line: line) {
            let found = views(h, of: desk)
            return h.clients().count == clients && found.count == count && found.allSatisfy {
                h.sessionFormat(String($0.split(separator: "|")[0]), "#{destroy-unattached}") == "on"
            }
        }
    }

    /// A desk with `count` windows, showing its first.
    private func deskWithWindows(_ h: HostHarness, _ name: String, _ count: Int, permanent: Bool = false) throws -> (String, [String]) {
        #expect(h.run(["desk-new", name, h.home.path] + (permanent ? ["--permanent"] : [])).exitCode == 0)
        let id = try sid(h, name)
        for _ in 1..<count { _ = h.tmux(["new-window", "-d", "-t", id + ":"]) }
        return (id, windowIDs(h, id))
    }

    /// The `window` lines of the status report for one desk.
    private func windowLines(_ report: String, _ desk: String) -> [String] {
        report.split(separator: "\n").map(String.init).filter { $0.hasPrefix("window\t\(desk)\t") }
    }

    // MARK: - What tmux 3.8 does

    /// Pinned before the script relied on it, with tmux alone on the throwaway socket:
    /// - rename-window turns the window's own automatic-rename off, and the name then stays while
    ///   another program runs in the window;
    /// - rename-window expands a format in the name it is given (so the script refuses #);
    /// - a name that starts with - is taken as the name after --;
    /// - turning the window's automatic-rename on again names it after the program running in it at
    ///   once, though the program prints nothing. The program is started before the rename, so the pane
    ///   has no output between the rename and the option being turned on.
    @Test func whatTmuxDoesWhenAWindowIsRenamed() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        let (desk, ids) = try deskWithWindows(h, "website", 2)
        try wait(h) { name(h, desk, ids[0]) == program(h, ids[0]) && !program(h, ids[0]).isEmpty }
        #expect(h.tmux(["show-options", "-w", "-t", ids[0], "automatic-rename"]).stdout == "")
        type(h, ids[0], "sleep 4343")
        try wait(h) { program(h, ids[0]) == "sleep" && name(h, desk, ids[0]) == "sleep" }

        #expect(h.tmux(["rename-window", "-t", desk + ":" + ids[0], "--", "my name.1"]).exitCode == 0)
        #expect(name(h, desk, ids[0]) == "my name.1")
        #expect(h.tmux(["show-options", "-w", "-t", ids[0], "automatic-rename"]).stdout == "automatic-rename off\n")
        Thread.sleep(forTimeInterval: 1.5)
        #expect(name(h, desk, ids[0]) == "my name.1")

        #expect(h.tmux(["rename-window", "-t", desk + ":" + ids[1], "--", "x#{window_id}"]).exitCode == 0)
        #expect(name(h, desk, ids[1]) == "x" + ids[1])
        #expect(h.tmux(["rename-window", "-t", desk + ":" + ids[1], "--", "-n"]).exitCode == 0)
        #expect(name(h, desk, ids[1]) == "-n")

        // sleep prints nothing, so only the option change can bring the program's name back.
        #expect(h.tmux(["set-option", "-w", "-t", desk + ":" + ids[0], "automatic-rename", "on"]).exitCode == 0)
        try wait(h) { name(h, desk, ids[0]) == "sleep" }
    }

    // MARK: - Naming a window

    @Test func aNameGoesOnThatWindowOnlyAndStaysWhenTheProgramChanges() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        let (desk, ids) = try deskWithWindows(h, "website", 3)
        let (notes, _) = try deskWithWindows(h, "notes", 2)
        let before = names(h, desk)
        let notesBefore = names(h, notes)

        let r = h.run(["window-name", "website", ids[1], "build logs"])
        #expect(r.exitCode == 0, "\(r.stderr)")
        #expect(r.stdout.isEmpty && r.stderr.isEmpty)
        #expect(names(h, desk) == [before[0], "\(ids[1])\tbuild logs\t0", before[2]])
        #expect(names(h, notes) == notesBefore)
        #expect(windowLines(h.run(["status"]).stdout, "website")[1] == "window\twebsite\t1\tbuild logs")

        // Another program in the window: the name stays.
        type(h, ids[1], "sleep 4343")
        try wait(h) { program(h, ids[1]) == "sleep" }
        Thread.sleep(forTimeInterval: 1.5)
        #expect(name(h, desk, ids[1]) == "build logs")
        #expect(windowLines(h.run(["status"]).stdout, "website")[1] == "window\twebsite\t1\tbuild logs")

        // One log line, with the desk and the window id and never the name.
        #expect(hostLog(h).contains("window-name\twebsite: named window \(ids[1])\n"), "\(hostLog(h))")
        #expect(!hostLog(h).contains("build logs"))
    }

    @Test func autoGivesTheNameBackToTmux() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        let (desk, ids) = try deskWithWindows(h, "website", 2)
        #expect(h.run(["window-name", "website", ids[0], "api"]).exitCode == 0)
        type(h, ids[0], "sleep 4343")
        try wait(h) { program(h, ids[0]) == "sleep" }
        #expect(name(h, desk, ids[0]) == "api")

        let r = h.run(["window-name", "website", ids[0], "--auto"])
        #expect(r.exitCode == 0, "\(r.stderr)")
        #expect(r.stdout.isEmpty && r.stderr.isEmpty)
        try wait(h) { name(h, desk, ids[0]) == "sleep" }
        #expect(names(h, desk)[0] == "\(ids[0])\tsleep\t1")
        try wait(h) { windowLines(h.run(["status"]).stdout, "website").first == "window\twebsite\t0\tsleep" }
        #expect(hostLog(h).contains("window-name\twebsite: window \(ids[0]) named after its program again\n"), "\(hostLog(h))")

        // The program ends, and the name follows it back to the shell.
        _ = h.tmux(["send-keys", "-t", ids[0], "C-c"])
        try wait(h) { program(h, ids[0]) != "sleep" && name(h, desk, ids[0]) == program(h, ids[0]) }
        // A window tmux names already can be given back again.
        #expect(h.run(["window-name", "website", ids[1], "--auto"]).exitCode == 0)
        #expect(names(h, desk)[1].hasSuffix("\t1"))
    }

    /// Names at the edges of the rule are accepted, set exactly, reported exactly, and read by the app's
    /// parser as one name.
    @Test func namesThatKeepTheRuleAreSetAndReportedExactly() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        let (desk, ids) = try deskWithWindows(h, "website", 2)
        let accepted = [
            "build logs", "v1.2", "a-b_c", ".", "-n", "--x", "A b  C", "notes 2.0 - draft_1",
            String(repeating: "x", count: 32), "abcdefghijklmnop qrstuvwxyz.-_09",
        ]
        for wanted in accepted {
            let r = h.run(["window-name", "website", ids[1], wanted])
            #expect(r.exitCode == 0, "\(wanted): \(r.stderr)")
            #expect(name(h, desk, ids[1]) == wanted)
            let report = h.run(["status"]).stdout
            #expect(windowLines(report, "website")[1] == "window\twebsite\t1\t" + wanted, "\(report)")
            let parsed = try HostStatus.parse(report)
            #expect(parsed.desks.first { $0.name.value == "website" }?.windows.map(\.name).last == wanted)
        }
        #expect(!hostLog(h).contains("abcdefghijklmnop"))
    }

    /// A name that breaks the rule is a usage error, and nothing changes: no window's name, and no
    /// window's automatic-rename.
    @Test func namesThatBreakTheRuleAreRefusedAndChangeNothing() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        let (desk, ids) = try deskWithWindows(h, "website", 2)
        #expect(h.run(["window-name", "website", ids[1], "kept"]).exitCode == 0)
        let before = names(h, desk)
        let refused = [
            "", String(repeating: "x", count: 33), " lead", "trail ", " ", "a\tb", "a\nb", "a\n", "a#b", "#{pane_pid}",
            "it's", "say \"hi\"", "a;b", "a;", "a/b", "caf\u{e9}", "na\u{ef}ve", "\u{3b1}", "a$b", "a`b`", "a\\b",
            "a:b", "a,b", "a*b", "a\u{a0}b",
        ]
        for wanted in refused {
            let r = h.run(["window-name", "website", ids[0], wanted])
            #expect(r.exitCode == 2, "\(wanted.debugDescription): \(r.stderr)")
            #expect(r.stderr == "macmosh-host: a window name is 1 to 32 characters, each a letter, a digit, a space, -, _ or a full stop, and it can't start or end with a space\n",
                    "\(wanted.debugDescription): \(r.stderr)")
            #expect(names(h, desk) == before, "\(wanted.debugDescription)")
        }
        let usage: [[String]] = [
            [], ["website"], ["website", ids[0]], ["website", ids[0], "a", "b"], ["website", ids[0], "--auto", "a"],
            ["website", ids[0], "a", "--auto"],
        ]
        for arguments in usage {
            let r = h.run(["window-name"] + arguments)
            #expect(r.exitCode == 2, "\(arguments): \(r.stderr)")
            #expect(r.stderr.hasPrefix("macmosh-host: usage: window-name <desk> <window id> <name>"), "\(arguments): \(r.stderr)")
            #expect(names(h, desk) == before, "\(arguments)")
        }
        #expect(!hostLog(h).contains("kept"))
    }

    /// The desk is a desk by its exact name, and the window must be one of its windows, given by id.
    @Test func badWindowsAndDesksAreRefusedAndChangeNothing() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        let (desk, ids) = try deskWithWindows(h, "website", 2)
        let (notes, other) = try deskWithWindows(h, "notes", 1)
        // A view with no tab (the attach fails here, with no terminal), then one renamed by hand.
        _ = h.run(["attach", "--window", ids[1], "website"])
        _ = h.run(["attach", "--window", ids[0], "website"])
        let made = views(h, of: desk).map { String($0.split(separator: "|")[0]) }
        try #require(made.count == 2)
        let viewName = try #require(h.sessionFormat(made[0], "#{session_name}"))
        #expect(viewName.hasPrefix("website+"))
        #expect(h.tmux(["rename-session", "-t", made[1], "garden"]).exitCode == 0)
        let before = names(h, desk)
        let notesBefore = names(h, notes)
        let unchanged = { names(h, desk) == before && names(h, notes) == notesBefore }

        for window in ["1", "@", "@1x", "%1", "$1", "@-1", "@ 1", "", "website", "@00", "@0" + String(ids[1].dropFirst())] {
            for last in ["fine", "--auto"] {
                let r = h.run(["window-name", "website", window, last])
                #expect(r.exitCode == 2, "\(window): \(r.stderr)")
                #expect(r.stderr == "macmosh-host: the window must be given by its id, such as @3\n", "\(window): \(r.stderr)")
            }
        }
        for last in ["fine", "--auto"] {
            for (deskName, window) in [("website", "@99"), ("website", other[0]), ("notes", ids[1])] {
                let r = h.run(["window-name", deskName, window, last])
                #expect(r.exitCode == 4, "\(deskName) \(window): \(r.stderr)")
                #expect(r.stderr == "That window has closed.\n", "\(deskName) \(window): \(r.stderr)")
            }
            for deskName in ["api", viewName, "garden", "", "web site", "=website"] {
                let r = h.run(["window-name", deskName, ids[0], last])
                #expect(r.exitCode == 4, "\(deskName): \(r.stderr)")
                #expect(r.stderr == "macmosh-host: no such desk: \(deskName)\n", "\(deskName): \(r.stderr)")
            }
        }
        #expect(unchanged())
        #expect(hostLog(h).contains("window-name\twebsite: window @99 has closed\n"), "\(hostLog(h))")
        #expect(hostLog(h).contains("window-name\tno such desk: api\n"), "\(hostLog(h))")
        #expect(!hostLog(h).contains("fine"))
        #expect(!FileManager.default.fileExists(atPath: h.home.appendingPathComponent(".macmosh/lock").path))

        // A window of the desk that really closed, by its own id.
        _ = h.tmux(["kill-window", "-t", ids[1]])
        try wait(h) { !windowIDs(h, desk).contains(ids[1]) }
        for last in ["fine", "--auto"] {
            let r = h.run(["window-name", "website", ids[1], last])
            #expect(r.exitCode == 4, "\(r.stderr)")
            #expect(r.stderr == "That window has closed.\n", "\(r.stderr)")
        }
    }

    /// A desk argument that is not a desk name never goes into the log: a new line in it would make a
    /// line of its own, and a window name given in its place would put that name in the log.
    @Test func aDeskArgumentThatIsNotADeskNameIsNotLogged() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        let (_, ids) = try deskWithWindows(h, "website", 1)
        for deskName in ["x\nFAKE\tline", "build logs"] {
            let before = hostLog(h).split(separator: "\n", omittingEmptySubsequences: false).count
            let r = h.run(["window-name", deskName, ids[0], "website"])
            #expect(r.exitCode == 4, "\(r.stderr)")
            let log = hostLog(h)
            let lines = log.split(separator: "\n", omittingEmptySubsequences: false)
            #expect(lines.count == before + 1, "\(log)")
            #expect(lines.dropLast().last?.hasSuffix("\twindow-name\tno such desk") == true, "\(log)")
            #expect(!log.contains("FAKE") && !log.contains("build logs"), "\(log)")
        }
    }

    /// No desk server: nothing to name, and none is started. The desk is "no such desk", as it is when
    /// the server runs without it.
    @Test func withNoDeskServerThereIsNoSuchDeskAndNoneIsStarted() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        let r = h.run(["window-name", "website", "@1", "fine"])
        #expect(r.exitCode == 4, "\(r.stderr)")
        #expect(r.stderr == "macmosh-host: no such desk: website\n")
        #expect(h.tmux(["list-sessions"]).exitCode != 0)
        #expect(!FileManager.default.fileExists(atPath: h.home.appendingPathComponent("launchctl.log").path))
    }

    // MARK: - Views and the bar

    /// A window that tabs show through views is the same window: named through the window id a view
    /// shows, the name shows in the desk, in every view, and in the bar tmux draws for each of them.
    @Test func aWindowNamedThroughAViewsWindowShowsTheNameEverywhereAndInTheBar() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        let (desk, ids) = try deskWithWindows(h, "website", 3)
        try openTab(h, "plain", ["website"])
        try openTab(h, "one", ["--window", ids[1], "website"])
        try openTab(h, "two", ["--window", ids[1], "website"])
        try openTab(h, "three", ["--window", ids[2], "--label", "abcd", "website"])
        try ready(h, desk, views: 3, clients: 4)
        let shown = views(h, of: desk)
        let all = shown.map { String($0.split(separator: "|")[0]) }
        let onOne = shown.filter { $0.hasSuffix("|" + ids[1]) }.map { String($0.split(separator: "|")[0]) }
        #expect(onOne.count == 2)

        #expect(h.run(["window-name", "website", ids[1], "build logs"]).exitCode == 0)
        #expect(h.run(["window-name", "website", ids[2], "v2.0"]).exitCode == 0)
        for session in [desk] + all {
            #expect(name(h, session, ids[1]) == "build logs", "\(session)")
            #expect(name(h, session, ids[2]) == "v2.0", "\(session)")
            // tmux 3.8's window-status-format and window-status-current-format both start with #I:#W.
            let bar = barEntries(h, session)
            #expect(bar[ids[1]]?.hasPrefix("1:build logs") == true, "\(session): \(bar)")
            #expect(bar[ids[2]]?.hasPrefix("2:v2.0") == true, "\(session): \(bar)")
        }
        // The view on the named window draws it as its current window, and the desk as another one.
        #expect(barEntries(h, onOne[0])[ids[1]] == "1:build logs*")
        #expect(barEntries(h, desk)[ids[1]]?.hasPrefix("1:build logs") == true)
        #expect(h.currentWindow(desk) == ids[0])
        // Every tab is still there, and the report lists the views as before.
        #expect(h.clients().count == 4)
        let report = h.run(["status"]).stdout
        #expect(windowLines(report, "website").dropFirst() == ["window\twebsite\t1\tbuild logs", "window\twebsite\t2\tv2.0"], "\(report)")
        #expect(report.split(separator: "\n").filter { $0.hasPrefix("view\twebsite\t") }.count == 3, "\(report)")
    }

    // MARK: - Everything else as before

    /// A tab on a named window still closes with its window, and the removal rule is as before: the
    /// last shells exiting remove a desk, and a permanent desk stays.
    @Test func theRemovalRuleAndATabEndingWithItsWindowAreAsBeforeWithNamedWindows() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        let (web, webIDs) = try deskWithWindows(h, "website", 3)
        let (notes, notesIDs) = try deskWithWindows(h, "notes", 2, permanent: true)
        for (i, id) in webIDs.enumerated() { #expect(h.run(["window-name", "website", id, "web \(i)"]).exitCode == 0) }
        for (i, id) in notesIDs.enumerated() { #expect(h.run(["window-name", "notes", id, "notes.\(i)"]).exitCode == 0) }
        try openTab(h, "one", ["--window", webIDs[1], "website"])
        try openTab(h, "two", ["--window", webIDs[2], "website"])
        try ready(h, web, views: 2, clients: 2)
        let one = String(try #require(views(h, of: web).first { $0.hasSuffix("|" + webIDs[1]) }).split(separator: "|")[0])
        let two = String(try #require(views(h, of: web).first { $0.hasSuffix("|" + webIDs[2]) }).split(separator: "|")[0])

        // exit in the named window a tab shows: that tab's view ends, and only it.
        typeExit(h, webIDs[1])
        try wait(h) { !exists(h, one) }
        #expect(exists(h, two))
        #expect(h.currentWindow(two) == webIDs[2])
        #expect(names(h, web).map { String($0.split(separator: "\t")[1]) } == ["web 0", "web 2"])
        try wait(h) { hostLog(h).contains("desk-closed\tignored: a view") }
        try proveTheHookHasRun(h)
        #expect(defined(h, "website"))

        // The last shells exiting remove website, and notes stays because it is permanent.
        for id in [webIDs[0], webIDs[2]] + notesIDs { typeExit(h, id) }
        try wait(h) { !defined(h, "website") }
        try wait(h) { h.sessionNames().isEmpty }
        try wait(h) { hostLog(h).contains("desk-closed\tkept notes: permanent") }
        try proveTheHookHasRun(h)
        #expect(defined(h, "notes"))
        // A permanent desk comes back as one fresh window: its names are gone with its windows.
        #expect(h.run(["attach", "--dry-run", "notes"]).exitCode == 0)
        let fresh = try sid(h, "notes")
        #expect(windowIDs(h, fresh).count == 1)
        #expect(!(names(h, fresh).first ?? "").contains("notes.0"))
        #expect(names(h, fresh).first?.hasSuffix("\t1") == true)
    }

    /// The other subcommands leave a window's name alone: window-new, desk-rename and attach.
    @Test func otherSubcommandsKeepTheName() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        let (desk, ids) = try deskWithWindows(h, "website", 2)
        #expect(h.run(["window-name", "website", ids[1], "build logs"]).exitCode == 0)
        #expect(h.run(["window-new", "website"]).exitCode == 0)
        #expect(h.run(["desk-rename", "website", "garden"]).exitCode == 0)
        _ = h.run(["attach", "--window", ids[1], "garden"])
        #expect(name(h, desk, ids[1]) == "build logs")
        #expect(windowIDs(h, desk).count == 3)
        #expect(views(h, of: desk).count == 1)
        // The desk goes by its new name now.
        #expect(h.run(["window-name", "website", ids[1], "x"]).exitCode == 4)
        #expect(h.run(["window-name", "garden", ids[1], "x"]).exitCode == 0)
        #expect(name(h, desk, ids[1]) == "x")
    }
}
}
