import Foundation
import Testing

extension HostScriptTests {
/// What tmux 3.8 does with session groups, which views rely on. A view is a small tmux session in
/// the same group as a desk's own session, one per terminal tab, so each tab keeps its own current
/// window over the desk's shared windows. These tests make the sessions by hand on the throwaway
/// socket, so they pin tmux itself, not the script.
///
/// Every wait ends as soon as its condition holds. The limits are long because CI runners are slow.
@Suite struct SessionGroupTests {
    /// A desk's session as the script makes one: in a group of its own whose name no desk can have,
    /// "macmosh+g" and the number of the id the session is about to get.
    private func makeDesk(_ h: HostHarness, _ name: String, windows: Int = 1) throws -> String {
        let next = h.tmux(["display-message", "-p", "#{next_session_id}"]).stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let made = h.tmux(["new-session", "-d", "-P", "-F", "#{session_id}", "-s", name,
                           "-t", "macmosh+g" + next.dropFirst(), "-c", h.home.path])
        let sid = made.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        try #require(made.exitCode == 0 && sid.hasPrefix("$"), "no desk \(name): \(made)")
        #expect(sid == next)
        for _ in 1..<max(windows, 1) { _ = h.tmux(["new-window", "-d", "-t", sid + ":"]) }
        _ = h.tmux(["select-window", "-t", sid + ":0"])
        return sid
    }

    private func group(_ h: HostHarness, _ sid: String) -> String { h.sessionFormat(sid, "#{session_group}") ?? "?" }

    /// A view joined to the group by the group's name, tagged as MacMosh tags it.
    private func makeView(_ h: HostHarness, desk sid: String, _ name: String) throws -> String {
        let made = h.tmux(["new-session", "-d", "-t", group(h, sid), "-s", name, "-P", "-F", "#{session_id}",
                           ";", "set-option", "@macmosh-view", sid])
        let vid = made.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        try #require(made.exitCode == 0 && vid.hasPrefix("$"), "no view \(name): \(made)")
        return vid
    }

    private func windowIDs(_ h: HostHarness, _ sid: String) -> [String] {
        h.tmux(["list-windows", "-t", sid + ":", "-F", "#{window_id}"]).stdout.split(separator: "\n").map(String.init)
    }

    private func hookLog(_ h: HostHarness) -> String {
        (try? String(contentsOf: h.home.appendingPathComponent("closed.log"), encoding: .utf8)) ?? ""
    }

    // MARK: 1. Sharing windows

    @Test func aViewSharesTheDesksWindowsAndKeepsItsOwnCurrentWindow() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        // Every new shell writes a line, to count them.
        let shells = h.home.appendingPathComponent("shells.log")
        _ = h.tmux(["set-option", "-g", "default-command", "echo started >> '\(shells.path)'; exec /bin/sh"])
        let sid = try makeDesk(h, "website", windows: 3)
        let ids = windowIDs(h, sid)
        #expect(ids.count == 3)
        let count = { ((try? String(contentsOf: shells, encoding: .utf8)) ?? "").split(separator: "\n").count }
        try waitFor(seconds: 30) { count() == 3 }

        let vid = try makeView(h, desk: sid, "website+1")
        #expect(windowIDs(h, vid) == ids)
        // Joining starts no shell of its own (a report on the 3.6 source said it starts one and drops it).
        Thread.sleep(forTimeInterval: 0.5)
        #expect(count() == 3)
        // A new view starts on the group's lowest window, whatever the desk shows.
        _ = h.tmux(["select-window", "-t", sid + ":" + ids[1]])
        let second = try makeView(h, desk: sid, "website+2")
        #expect(h.currentWindow(second) == ids[0])

        // Each session keeps its own current window.
        #expect(h.tmux(["select-window", "-t", vid + ":" + ids[2]]).exitCode == 0)
        #expect(h.currentWindow(vid) == ids[2])
        #expect(h.currentWindow(sid) == ids[1])
        // window_active is relative to the session the windows are listed from.
        let active = { (s: String) in
            h.tmux(["list-windows", "-t", s + ":", "-F", "#{window_id}=#{window_active}"]).stdout
        }
        #expect(active(sid) == "\(ids[0])=0\n\(ids[1])=1\n\(ids[2])=0\n")
        #expect(active(vid) == "\(ids[0])=0\n\(ids[1])=0\n\(ids[2])=1\n")

        // new-window -d moves nobody; plain new-window moves only the session it targets.
        let quiet = h.tmux(["new-window", "-d", "-P", "-F", "#{window_id}", "-t", sid + ":"]).stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(windowIDs(h, vid).contains(quiet))
        #expect(h.currentWindow(sid) == ids[1])
        #expect(h.currentWindow(vid) == ids[2])
        let loud = h.tmux(["new-window", "-P", "-F", "#{window_id}", "-t", sid + ":"]).stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(h.currentWindow(sid) == loud)
        #expect(h.currentWindow(vid) == ids[2])

        // Killing a view (without -g) leaves every window to the desk.
        #expect(h.tmux(["kill-session", "-t", vid]).exitCode == 0)
        #expect(windowIDs(h, sid) == ids + [quiet, loud])
    }

    /// The window and session lookups the script uses. display-message answers even for a window or a
    /// session that does not exist, so it can't tell whether one is there; list-windows can.
    @Test func displayMessageCantTellAMissingWindowButListWindowsCan() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        let sid = try makeDesk(h, "website")
        let missing = h.tmux(["display-message", "-p", "-t", sid + ":@99", "#{window_id}"])
        #expect(missing.exitCode == 0)
        #expect(missing.stdout == windowIDs(h, sid)[0] + "\n")
        #expect(h.tmux(["display-message", "-p", "-t", "$99", "#{session_id}"]).exitCode == 0)
        #expect(!windowIDs(h, sid).contains("@99"))
        // A window target in a view: the view's id, a colon and the window's id.
        let vid = try makeView(h, desk: sid, "website+1")
        #expect(h.tmux(["select-window", "-t", vid + ":@99"]).exitCode != 0)
    }

    // MARK: 2. Group names

    @Test func aGroupIsNamedOnceAndAnOldNameCanCatchANewDesk() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        // A session made without a group, as the script before 0.7.0 made every desk.
        let old = h.tmux(["new-session", "-d", "-P", "-F", "#{session_id}", "-s", "work"]).stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
        _ = h.tmux(["new-window", "-d", "-t", old + ":"])
        _ = h.tmux(["new-window", "-d", "-t", old + ":"])
        #expect(h.sessionFormat(old, "#{session_grouped}|#{session_group}") == "0|")

        // Joined by the session's name with no name of its own: the group takes the session's name,
        // and the new session is called "<group>-<number>".
        let joined = h.tmux(["new-session", "-d", "-t", "work", "-P", "-F", "#{session_id}|#{session_name}"]).stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let vid = String(joined.split(separator: "|")[0])
        #expect(joined == vid + "|work-" + vid.dropFirst())
        #expect(group(h, old) == "work")
        #expect(group(h, vid) == "work")
        // A session id works as well as a name.
        let byID = h.tmux(["new-session", "-d", "-t", old, "-P", "-F", "#{session_id}"]).stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(group(h, byID) == "work")
        _ = h.tmux(["kill-session", "-t", byID])

        // A rename leaves the group's name as it was.
        #expect(h.tmux(["rename-session", "-t", old, "web"]).exitCode == 0)
        #expect(group(h, old) == "work")

        // The hazard: a new session called "work" and a view joined by that name land in the old
        // group, so the view shows the other desk's three windows. The new session is pulled into the
        // old group too.
        let fresh = h.tmux(["new-session", "-d", "-P", "-F", "#{session_id}", "-s", "work"]).stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let wrong = h.tmux(["new-session", "-d", "-t", "work", "-P", "-F", "#{session_id}"]).stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(group(h, wrong) == "work")
        #expect(windowIDs(h, wrong) == windowIDs(h, old))
        #expect(group(h, fresh) == "work")
        _ = h.tmux(["kill-session", "-t", wrong])
        _ = h.tmux(["kill-session", "-t", fresh])

        // The cure: a desk born in a group of its own, named "macmosh+g<its id>", gets one window in
        // its folder, and a rename can't make its group's name a desk name.
        let born = try makeDesk(h, "work")
        #expect(group(h, born) == "macmosh+g" + born.dropFirst())
        #expect(windowIDs(h, born).count == 1)
        #expect(h.tmux(["display-message", "-p", "-t", born + ":", "#{pane_current_path}"]).stdout
            .trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("/" + h.home.lastPathComponent))
        let view = try makeView(h, desk: born, "work+1")
        #expect(group(h, view) == group(h, born))
        #expect(windowIDs(h, view) == windowIDs(h, born))
        #expect(h.tmux(["rename-session", "-t", born, "notes"]).exitCode == 0)
        let again = try makeDesk(h, "work")
        let view2 = try makeView(h, desk: again, "work+2")
        #expect(windowIDs(h, view2) == windowIDs(h, again))
        #expect(windowIDs(h, again).count == 1)
        #expect(windowIDs(h, born).count == 1)
        #expect(windowIDs(h, again) != windowIDs(h, born))

        // A group with one session left stays a group.
        _ = h.tmux(["kill-session", "-t", view2])
        #expect(h.sessionFormat(again, "#{session_grouped}|#{session_group_size}") == "1|1")
    }

    // MARK: 3. A view ends with its client

    @Test func aViewGoesWithItsClientAndTheDeskStays() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        let sid = try makeDesk(h, "website", windows: 2)
        let ids = windowIDs(h, sid)

        // keep-last set on a view that has no client yet destroys it at once.
        let early = try makeView(h, desk: sid, "website+1")
        _ = h.tmux(["set-option", "-t", early, "destroy-unattached", "keep-last"])
        #expect(h.sessionFormat(early, "#{session_name}") == nil)

        // Set in the same command list, after the attach, it applies once the client is there.
        let one = try makeView(h, desk: sid, "website+2")
        let two = try makeView(h, desk: sid, "website+3")
        for (label, vid) in [("one", one), ("two", two)] {
            try h.startClient(label, ["tmux", "-L", h.socket, "attach-session", "-t", vid,
                                    ";", "set-option", "-t", vid, "destroy-unattached", "keep-last"])
        }
        try waitFor(seconds: 30) { h.clients().count == 2 }
        try waitFor(seconds: 30) {
            h.sessionFormat(one, "#{destroy-unattached}") == "keep-last"
                && h.sessionFormat(two, "#{destroy-unattached}") == "keep-last"
        }
        #expect(h.sessionFormat(sid, "#{destroy-unattached}") == "off")

        // A detach ends the first view; a hangup, as when a terminal closes, ends the second.
        let tty = try #require(h.clients().first { $0.hasPrefix(one + "|") }?.split(separator: "|").last)
        _ = h.tmux(["detach-client", "-t", String(tty)])
        try waitFor(seconds: 30) { h.sessionFormat(one, "#{session_name}") == nil }
        try h.hangUp(clientOf: two)
        try waitFor(seconds: 30) { h.sessionFormat(two, "#{session_name}") == nil }
        #expect(h.sessionNames() == ["website"])
        #expect(windowIDs(h, sid) == ids)

        // An attach that fails (no terminal) runs nothing after it, so that view stays with no client.
        let stray = try makeView(h, desk: sid, "website+4")
        let failed = h.tmux(["attach-session", "-t", stray, ";", "set-option", "-t", stray, "destroy-unattached", "keep-last"])
        #expect(failed.exitCode != 0)
        #expect(h.sessionFormat(stray, "#{session_attached}|#{destroy-unattached}") == "0|off")
    }

    // MARK: 4. The last shell

    @Test func whenTheLastShellExitsEverySessionInTheGroupClosesAndTheHookRunsForEach() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        let log = h.home.appendingPathComponent("closed.log").path
        _ = h.tmux(["set-hook", "-g", "session-closed[7]", "run-shell \"echo '#{hook_session_name}' >> '\(log)'\""])
        let sid = try makeDesk(h, "website", windows: 2)
        _ = try makeView(h, desk: sid, "website+1")
        _ = try makeView(h, desk: sid, "website+2")
        _ = try makeDesk(h, "notes")

        for id in windowIDs(h, sid) {
            _ = h.tmux(["send-keys", "-t", sid + ":" + id, "-l", "--", "exit"])
            _ = h.tmux(["send-keys", "-t", sid + ":" + id, "Enter"])
        }
        try waitFor(seconds: 30) { h.sessionNames() == ["notes"] }
        try waitFor(seconds: 30) { hookLog(h).split(separator: "\n").count == 3 }
        #expect(hookLog(h).split(separator: "\n").map(String.init).sorted() == ["website", "website+1", "website+2"])
    }

    // MARK: 5. Counts

    @Test func theCountsWithTwoViewsOnDifferentWindows() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        let sid = try makeDesk(h, "website", windows: 2)
        let ids = windowIDs(h, sid)
        let one = try makeView(h, desk: sid, "website+1")
        let two = try makeView(h, desk: sid, "website+2")
        _ = h.tmux(["select-window", "-t", two + ":" + ids[1]])
        try h.startClient("one", cols: 100, rows: 30, ["tmux", "-L", h.socket, "attach-session", "-t", one])
        try h.startClient("two", cols: 120, rows: 40, ["tmux", "-L", h.socket, "attach-session", "-t", two])
        try waitFor(seconds: 30) { h.clients().count == 2 }

        let counts = "#{session_attached}|#{session_group_attached}|#{session_group_size}"
        #expect(h.sessionFormat(sid, counts) == "0|2|3")
        #expect(h.sessionFormat(one, counts) == "1|2|3")
        #expect(h.sessionFormat(two, counts) == "1|2|3")
        // window_active_clients counts the clients of every session in the group that show the window.
        let perWindow = { h.tmux(["list-windows", "-t", sid + ":", "-F", "#{window_id}=#{window_active_clients}"]).stdout }
        #expect(perWindow() == "\(ids[0])=1\n\(ids[1])=1\n")
        #expect(h.clients().map { $0.split(separator: "|")[1] } == ["website+1", "website+2"])

        // 6. Sizes: window-size is "latest" by default, and a window shown by one tab only takes that
        // tab's size (less the status line).
        #expect(h.tmux(["show-options", "-gv", "window-size"]).stdout == "latest\n")
        let sizes = { h.tmux(["list-windows", "-t", sid + ":", "-F", "#{window_width}x#{window_height}"]).stdout }
        try waitFor(seconds: 30) { sizes() == "100x29\n120x39\n" }

        // Both on one window: two clients there, none on the other, and the window has one of the two sizes.
        _ = h.tmux(["select-window", "-t", two + ":" + ids[0]])
        try waitFor(seconds: 30) { perWindow() == "\(ids[0])=2\n\(ids[1])=0\n" }
        let shared = String(sizes().split(separator: "\n")[0])
        #expect(["100x29", "120x39"].contains(shared), "\(shared)")
    }

    // MARK: 7. Today's window-new and attach, with views there

    @Test func todaysWindowNewAndAttachBehaveAsBeforeWithViewsThere() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        #expect(h.run(["desk-new", "website", h.home.path]).exitCode == 0)
        let sid = try #require(h.tmux(["list-sessions", "-F", "#{session_id}"]).stdout
            .split(separator: "\n").first.map(String.init))
        _ = h.tmux(["new-window", "-d", "-t", sid + ":"])
        let ids = windowIDs(h, sid)
        // A view made by hand: the script before 0.7.0 makes desks with no group, so the view joins
        // the desk by its name.
        let made = h.tmux(["new-session", "-d", "-t", "website", "-s", "website+1", "-P", "-F", "#{session_id}"])
        let vid = made.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = h.tmux(["select-window", "-t", vid + ":" + ids[1]])

        // window-new: the desk shows the new window, the view does not move.
        #expect(h.run(["window-new", "website"]).exitCode == 0)
        let after = windowIDs(h, sid)
        #expect(after.count == 3)
        #expect(h.currentWindow(sid) == after.last)
        #expect(h.currentWindow(vid) == ids[1])

        // attach: the client is the desk's own session's.
        try h.startClient("plain", ["/bin/bash", h.scriptURL.path, "attach", "website"])
        try waitFor(seconds: 30) { h.clients().count == 1 }
        #expect(h.clients()[0].hasPrefix(sid + "|website|"))
        #expect(h.sessionNames() == ["website", "website+1"])
    }
}
}
