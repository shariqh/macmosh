import Foundation
import Testing

extension HostScriptTests {
/// Views: one small tmux session per terminal tab, in the same group as the desk's own session, so a
/// tab keeps its own current window. `attach --window @N` and `attach --new-window` make one; the
/// status report says which windows a tab shows; `status` sweeps views that never got a tab; and every
/// other path treats a view as no desk at all.
///
/// Every wait ends as soon as its condition holds. The limits are long because CI runners are slow.
@Suite struct DeskViewTests {
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

    private func typeExit(_ h: HostHarness, _ target: String) {
        _ = h.tmux(["send-keys", "-t", target, "-l", "--", "exit"])
        _ = h.tmux(["send-keys", "-t", target, "Enter"])
    }

    private func wait(_ h: HostHarness, seconds: Double = 30, line: UInt = #line, _ condition: () -> Bool) throws {
        do {
            try waitFor(seconds: seconds, condition)
        } catch {
            let log = hostLog(h).split(separator: "\n").suffix(20).joined(separator: "\n")
            Issue.record(Comment(rawValue: "timed out after \(Int(seconds)) s (DeskViewTests.swift:\(line))\n"
                + "[desks.tsv]\n\(desksFile(h))[host.log]\n\(log)\n[sessions]\n\(h.sessionNames())\n[clients]\n\(h.clients())"))
            throw error
        }
    }

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

    /// The views of a desk, as `<view id>|<view name>|<window shown>`, found by MacMosh's tag.
    private func views(_ h: HostHarness, of deskID: String) -> [String] {
        h.tmux(["list-sessions", "-F", "#{session_id}|#{session_name}|#{window_id}|#{@macmosh-view}"]).stdout
            .split(separator: "\n").map(String.init)
            .filter { $0.hasSuffix("|" + deskID) }
            .map { $0.split(separator: "|").prefix(3).joined(separator: "|") }
            .sorted()
    }

    /// Opens a tab on the desk the way the app will: the script's attach, in a terminal of its own.
    private func openTab(_ h: HostHarness, _ label: String, _ arguments: [String]) throws {
        try h.startClient(label, ["/bin/bash", h.scriptURL.path, "attach"] + arguments)
    }

    /// A desk with `count` windows, showing its first.
    private func deskWithWindows(_ h: HostHarness, _ name: String, _ count: Int) throws -> (String, [String]) {
        #expect(h.run(["desk-new", name, h.home.path]).exitCode == 0)
        let id = try sid(h, name)
        for _ in 1..<count { _ = h.tmux(["new-window", "-d", "-t", id + ":"]) }
        return (id, windowIDs(h, id))
    }

    // MARK: - Groups

    @Test func everyDeskIsBornInAGroupOfItsOwn() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        #expect(h.run(["desk-new", "website", h.home.path]).exitCode == 0)
        #expect(h.run(["desk-new", "notes", h.home.path, "--permanent"]).exitCode == 0)
        let group = { (name: String) in h.sessionFormat(lookup(h, name) ?? "", "#{session_group}") ?? "" }
        let website = try sid(h, "website")
        #expect(group("website") == "macmosh+g" + website.dropFirst())
        #expect(group("notes") != group("website"))
        #expect(windowIDs(h, website).count == 1)

        // A rename keeps the group; a desk made again from its definition gets one of its own.
        #expect(h.run(["desk-rename", "website", "web"]).exitCode == 0)
        #expect(group("web") == "macmosh+g" + website.dropFirst())
        typeExit(h, "=notes:")
        try wait(h) { lookup(h, "notes") == nil }
        #expect(h.run(["attach", "--dry-run", "notes"]).exitCode == 0)
        #expect(group("notes").hasPrefix("macmosh+g"))
        #expect(group("notes") == "macmosh+g" + (try sid(h, "notes")).dropFirst())

        // So are the desks a start reopens.
        _ = h.tmux(["kill-server"])
        #expect(h.run(["start"]).exitCode == 0)
        #expect(group("web") == "macmosh+g" + (try sid(h, "web")).dropFirst())
    }

    // MARK: - attach --window and --new-window

    @Test func attachWindowOpensATabOnThatWindowAndTheTabTakesItsViewAway() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        let (desk, ids) = try deskWithWindows(h, "website", 3)
        #expect(h.currentWindow(desk) == ids[0])

        try openTab(h, "one", ["--window", ids[1], "website"])
        try wait(h) { h.clients().count == 1 }
        let found = views(h, of: desk)
        #expect(found.count == 1)
        let parts = try #require(found.first).split(separator: "|").map(String.init)
        let vid = parts[0]
        #expect(parts[1].hasPrefix("website+"))
        #expect(parts[2] == ids[1])
        #expect(h.clients()[0].hasPrefix(vid + "|"))
        // The desk shows what it showed; the tab's view ends with its tab, and only it.
        #expect(h.currentWindow(desk) == ids[0])
        try wait(h) { h.sessionFormat(vid, "#{destroy-unattached}") == "keep-last" }
        #expect(h.sessionFormat(desk, "#{destroy-unattached}") == "off")
        #expect(hostLog(h).contains("attach\twebsite (window \(ids[1]))"))

        try openTab(h, "two", ["--window", ids[2], "website"])
        try wait(h) { h.clients().count == 2 }
        #expect(views(h, of: desk).map { String($0.split(separator: "|")[2]) } == [ids[1], ids[2]])

        try h.hangUp(clientOf: vid)
        try wait(h) { views(h, of: desk).count == 1 }
        #expect(windowIDs(h, desk) == ids)
        #expect(h.sessionNames().filter { !$0.contains("+") } == ["website"])
        try proveTheHookHasRun(h)
        #expect(defined(h, "website"))
        #expect(hostLog(h).contains("desk-closed\tignored: not a desk name"))
    }

    @Test func attachNewWindowAddsAWindowAndOpensATabOnIt() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        let (desk, ids) = try deskWithWindows(h, "website", 2)
        // A tab on the desk's own session, as today's app opens one.
        try openTab(h, "plain", ["website"])
        try wait(h) { h.clients().count == 1 }

        try openTab(h, "new", ["--new-window", "website"])
        try wait(h) { h.clients().count == 2 && views(h, of: desk).count == 1 }
        let after = windowIDs(h, desk)
        #expect(after.count == 3)
        let added = try #require(after.last)
        #expect(!ids.contains(added))
        #expect(views(h, of: desk)[0].hasSuffix("|" + added))
        // The tab that was open keeps showing what it showed.
        #expect(h.currentWindow(desk) == ids[0])
        // It starts in the desk's folder, as a window from window-new does.
        let path = h.tmux(["display-message", "-p", "-t", added, "#{pane_current_path}"]).stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(path.hasSuffix("/" + h.home.lastPathComponent))
        #expect(hostLog(h).contains("attach\twebsite (new window \(added))"))
    }

    @Test func badAndClosedWindowsAreRefusedAndMakeNothing() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        let (desk, ids) = try deskWithWindows(h, "website", 2)
        let before = h.sessionNames()

        let closed = h.run(["attach", "--window", "@99", "website"])
        #expect(closed.exitCode == 4, "\(closed.stderr)")
        #expect(closed.stderr.contains("That window has closed."))

        let usage: [[String]] = [
            ["--window", "1", "website"], ["--window", "website"], ["--window"], ["--window", "@", "website"],
            ["--window", "@1x", "website"], ["--cc", "--window", ids[0], "website"], ["--cc", "--new-window", "website"],
            ["--window", ids[0], "--new-window", "website"],
        ]
        for arguments in usage {
            let r = h.run(["attach"] + arguments)
            #expect(r.exitCode == 2, "\(arguments): \(r.stderr)")
        }
        // A dry run checks the window and stops: no view, no window.
        #expect(h.run(["attach", "--dry-run", "--window", ids[1], "website"]).stdout == "ok\n")
        #expect(h.run(["attach", "--dry-run", "--window", "@99", "website"]).exitCode == 4)
        #expect(h.run(["attach", "--dry-run", "--new-window", "website"]).stdout == "ok\n")
        // A window of another desk is not this desk's window.
        let (_, other) = try deskWithWindows(h, "notes", 1)
        #expect(h.run(["attach", "--window", other[0], "website"]).exitCode == 4)
        #expect(windowIDs(h, desk) == ids)
        #expect(h.sessionNames() == (before + ["notes"]).sorted())
        #expect(!FileManager.default.fileExists(atPath: h.home.appendingPathComponent(".macmosh/lock").path))
    }

    // MARK: - A desk made by the script before 0.7.0

    @Test func aDeskWithNoGroupGetsOneFromItsFirstTabAndAnOldGroupNameIsNeverJoined() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        try writeDesksFile(h, "website\t1\t0\t0\t\(h.home.path)\t\nnotes\t1\t0\t0\t\(h.home.path)\t\n")
        // The way the older script made a desk: a session with no group.
        _ = h.tmux(["new-session", "-d", "-s", "website", "-c", h.home.path])
        _ = h.tmux(["new-session", "-d", "-s", "notes", "-c", h.home.path])
        let website = try sid(h, "website")
        _ = h.tmux(["new-window", "-d", "-t", website + ":"])
        let ids = windowIDs(h, website)

        try openTab(h, "one", ["--window", ids[1], "website"])
        try wait(h) { views(h, of: website).count == 1 }
        // The group takes the desk's name, and the desk is never renamed.
        #expect(h.sessionFormat(website, "#{session_name}|#{session_group}") == "website|website")
        #expect(views(h, of: website)[0].hasSuffix("|" + ids[1]))
        #expect(!hostLog(h).contains("rename"))

        // A group called "website" outlives a rename. Another old desk renamed to "website" must not
        // join it: its tab is refused and its windows are its own.
        #expect(h.run(["desk-rename", "website", "web"]).exitCode == 0)
        #expect(h.run(["desk-rename", "notes", "website"]).exitCode == 0)
        let notes = try sid(h, "website")
        let notesWindows = windowIDs(h, notes)
        let r = h.run(["attach", "--window", notesWindows[0], "website"])
        #expect(r.exitCode == 1, "\(r.stderr)")
        #expect(!r.stderr.isEmpty)
        #expect(h.sessionFormat(notes, "#{session_grouped}") == "0")
        #expect(windowIDs(h, notes) == notesWindows)
        #expect(windowIDs(h, website) == ids)
        #expect(views(h, of: notes).isEmpty)
    }

    // MARK: - The report

    @Test func theReportSaysWhichWindowsHaveATabAndThroughWhichView() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        let (desk, ids) = try deskWithWindows(h, "website", 3)
        _ = h.tmux(["rename-window", "-t", ids[0], "zsh"])
        _ = h.tmux(["rename-window", "-t", ids[1], "claude"])
        _ = h.tmux(["rename-window", "-t", ids[2], "npm"])
        for id in ids { _ = h.tmux(["set-option", "-w", "-t", id, "automatic-rename", "off"]) }
        try openTab(h, "plain", ["website"])
        try openTab(h, "one", ["--window", ids[1], "website"])
        try wait(h) { h.clients().count == 2 && views(h, of: desk).count == 1 }
        let view = String(views(h, of: desk)[0].split(separator: "|")[1])

        let out = h.run(["status"]).stdout
        // The desk and window lines are as before; the desk counts every tab, its views' too.
        #expect(out.contains("\ndesk\twebsite\t3\t2\nwindow\twebsite\t0\tzsh\nwindow\twebsite\t1\tclaude\nwindow\twebsite\t2\tnpm\n"), "\(out)")
        #expect(out.contains("\nwindowinfo\twebsite\t0\t\(ids[0])\t1\t1\n"), "\(out)")
        #expect(out.contains("\nwindowinfo\twebsite\t1\t\(ids[1])\t0\t1\n"), "\(out)")
        #expect(out.contains("\nwindowinfo\twebsite\t2\t\(ids[2])\t0\t0\n"), "\(out)")
        #expect(out.contains("\nview\twebsite\t\(view)\t\(ids[1])\t1\n"), "\(out)")
        // A view is never a desk.
        #expect(!out.contains("\ndesk\twebsite+"))
        #expect(out.split(separator: "\n").filter { $0.hasPrefix("desk\t") }.count == 1)

        // After a rename the view's line names the desk by its new name.
        #expect(h.run(["desk-rename", "website", "notes"]).exitCode == 0)
        let renamed = h.run(["status"]).stdout
        #expect(renamed.contains("\nview\tnotes\t\(view)\t\(ids[1])\t1\n"), "\(renamed)")
        #expect(renamed.contains("\ndesk\tnotes\t3\t2\n"))
    }

    // MARK: - Sweeping

    @Test func statusSweepsOldViewsWithNoTabAndNothingElse() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        let (desk, ids) = try deskWithWindows(h, "website", 2)
        let group = h.sessionFormat(desk, "#{session_group}") ?? ""
        let make = { (name: String) -> String in
            h.tmux(["new-session", "-d", "-t", group, "-s", name, "-P", "-F", "#{session_id}",
                    ";", "set-option", "@macmosh-view", desk]).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let stray = make("website+101")
        // A view with a tab, a session of your own with a + in its name, and a view whose desk was
        // killed by hand (the last of its group: it holds the windows, so it stays).
        try openTab(h, "one", ["--window", ids[1], "website"])
        try wait(h) { h.clients().count == 1 }
        _ = h.tmux(["new-session", "-d", "-t", group, "-s", "mine+1"])
        let (lonely, _) = try deskWithWindows(h, "notes", 1)
        let lonelyGroup = h.sessionFormat(lonely, "#{session_group}") ?? ""
        let lone = h.tmux(["new-session", "-d", "-t", lonelyGroup, "-s", "notes+5", "-P", "-F", "#{session_id}",
                           ";", "set-option", "@macmosh-view", lonely]).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = h.tmux(["kill-session", "-t", lonely])

        // Younger than a minute: kept.
        #expect(h.run(["status"]).exitCode == 0)
        #expect(h.sessionFormat(stray, "#{session_name}") == "website+101")

        // Older than the age (shortened for the test): swept, and only it.
        h.setEnvironment("MACMOSH_VIEW_SWEEP_AGE", "1")
        Thread.sleep(forTimeInterval: 2.2)
        #expect(h.run(["status"]).exitCode == 0)
        #expect(h.sessionFormat(stray, "#{session_name}") == nil)
        #expect(views(h, of: desk).count == 1)
        #expect(h.sessionNames().contains("mine+1"))
        #expect(h.sessionFormat(lone, "#{session_name}") == "notes+5")
        #expect(windowIDs(h, desk) == ids)
        #expect(hostLog(h).contains("status\tremoved 1 view with no tab"))
    }

    // MARK: - Every other path, with views there

    @Test func removeWithKillTakesTheViewsAndTheirTabs() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        let (desk, ids) = try deskWithWindows(h, "website", 2)
        try openTab(h, "one", ["--window", ids[0], "website"])
        try openTab(h, "two", ["--window", ids[1], "website"])
        try wait(h) { h.clients().count == 2 }
        #expect(h.run(["desk-new", "notes", h.home.path]).exitCode == 0)

        #expect(h.run(["desk-remove", "website", "--kill"]).exitCode == 0)
        try wait(h) { h.sessionNames() == ["notes"] && h.clients().isEmpty }
        #expect(views(h, of: desk).isEmpty)
        #expect(!defined(h, "website"))
        try proveTheHookHasRun(h)
        #expect(desksFile(h).hasPrefix("notes\t"))
    }

    @Test func theLastShellExitingRemovesADeskThatHasViews() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        let (desk, ids) = try deskWithWindows(h, "website", 2)
        try openTab(h, "one", ["--window", ids[1], "website"])
        try wait(h) { h.clients().count == 1 }
        let stray = h.tmux(["new-session", "-d", "-t", h.sessionFormat(desk, "#{session_group}") ?? "", "-s", "website+7",
                            "-P", "-F", "#{session_id}", ";", "set-option", "@macmosh-view", desk]).stdout
        #expect(!stray.isEmpty)
        for id in ids { typeExit(h, id) }
        try wait(h) { !defined(h, "website") }
        #expect(h.sessionNames().isEmpty)
        #expect(hostLog(h).contains("desk-closed\tremoved website: its last shell exited"))
        #expect(hostLog(h).contains("desk-closed\tignored: not a desk name"))
    }

    @Test func aRestartWithTabsOpenBringsBackOnlyTheDesks() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        let (_, ids) = try deskWithWindows(h, "website", 2)
        _ = h.run(["desk-new", "notes", h.home.path, "--permanent"])
        try openTab(h, "one", ["--window", ids[1], "website"])
        try wait(h) { h.clients().count == 1 }
        let before = desksFile(h)
        try h.stub("launchctl", script: """
            echo "$*" >> "$HOME/launchctl.log"
            if [ "$1" = "kickstart" ]; then "\(h.scriptURL.path)" start; fi
            exit 0
            """)
        #expect(h.run(["restart-server", "--yes"]).exitCode == 0)
        #expect(h.sessionNames() == ["notes", "website"])
        #expect(desksFile(h) == before)
        try proveTheHookHasRun(h)
        #expect(desksFile(h) == before)
    }

    @Test func aRenamedDesksNameIsFreeAndItsViewsStayWithIt() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        let (desk, ids) = try deskWithWindows(h, "website", 2)
        try openTab(h, "one", ["--window", ids[1], "website"])
        try wait(h) { h.clients().count == 1 }
        #expect(h.run(["desk-rename", "website", "notes"]).exitCode == 0)
        // The old name is free: a new desk gets it, with windows of its own, and its tab shows them.
        #expect(h.run(["desk-new", "website", h.home.path]).exitCode == 0)
        let fresh = try sid(h, "website")
        #expect(windowIDs(h, fresh).count == 1)
        try openTab(h, "two", ["--new-window", "website"])
        try wait(h) { views(h, of: fresh).count == 1 }
        #expect(windowIDs(h, fresh).count == 2)
        #expect(windowIDs(h, desk) == ids)
        #expect(views(h, of: desk).count == 1)
        // Names with a + are never desks.
        #expect(h.run(["desk-new", "website+1", h.home.path]).exitCode == 6)
        #expect(h.run(["attach", "website+1"]).exitCode == 4)
        #expect(h.run(["window-new", "website+1"]).exitCode == 4)
        #expect(h.run(["desk-remove", "website+1", "--kill"]).exitCode == 4)
        #expect(h.run(["desk-rename", "website+1", "fresh"]).exitCode == 2)
    }

    /// keep finds its desk through the session its pane is in, and tmux names the view for a pane that
    /// a view shows. keep then goes from the view to its desk.
    @Test func keepFindsItsDeskThroughAView() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        try writeDesksFile(h, "api2\t1\t1\t0\t\(h.home.path)\techo run >> runs.txt; sleep 4343\n")
        let made = h.tmux(["new-session", "-d", "-P", "-F", "#{session_id}", "-s", "api2", "-t", "macmosh+gx", "-c", h.home.path])
        let desk = made.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = h.tmux(["new-session", "-d", "-t", "macmosh+gx", "-s", "api2+1", ";", "set-option", "@macmosh-view", desk])
        // The premise: asked about the desk's pane, tmux names the view.
        let pane = h.tmux(["display-message", "-p", "-t", desk + ":", "#{pane_id}"]).stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(h.tmux(["display-message", "-p", "-t", pane, "#{session_name}"]).stdout == "api2+1\n")
        _ = h.tmux(["send-keys", "-t", desk + ":", "-l", "--", "'\(h.scriptURL.path)' keep api"])
        _ = h.tmux(["send-keys", "-t", desk + ":", "Enter"])
        let runs = { (try? String(contentsOf: h.home.appendingPathComponent("runs.txt"), encoding: .utf8)) ?? "" }
        try wait(h) { runs() == "run\n" }
        #expect(!hostLog(h).contains("no such desk: api"))
    }

    @Test func todaysCallsBehaveAsBeforeWithTabsOnViews() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        let (desk, ids) = try deskWithWindows(h, "website", 2)
        try openTab(h, "one", ["--window", ids[1], "website"])
        try wait(h) { h.clients().count == 1 }
        let vid = String(views(h, of: desk)[0].split(separator: "|")[0])
        // window-new: the desk's own session shows the new window; the view stays where it was.
        #expect(h.run(["window-new", "website"]).exitCode == 0)
        let after = windowIDs(h, desk)
        #expect(after.count == 3)
        #expect(h.currentWindow(desk) == after.last)
        #expect(h.currentWindow(vid) == ids[1])
        // attach with no option: a client of the desk's own session, and no new view.
        try openTab(h, "plain", ["website"])
        try wait(h) { h.clients().count == 2 }
        #expect(h.clients().contains { $0.hasPrefix(desk + "|website|") })
        #expect(views(h, of: desk).count == 1)
        #expect(h.run(["attach", "--dry-run", "website"]).stdout == "ok\n")
        #expect(views(h, of: desk).count == 1)
    }
}
}
