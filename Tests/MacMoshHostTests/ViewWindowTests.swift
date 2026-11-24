import Foundation
import Testing

extension HostScriptTests {
/// A tab that shows one window of a desk closes when that window closes (issue 139). The tab's view
/// ends, and only it: the desk keeps its other windows and its definition, a plain tab on the desk's
/// own session moves to another window as before, and a view that the person switched to another
/// window follows the window it shows. When the desk's last window closes, everything goes as before.
///
/// Every wait ends as soon as its condition holds. The limits are long because CI runners are slow.
@Suite struct ViewWindowTests {
    private func desksFile(_ h: HostHarness) -> String {
        (try? String(contentsOf: h.home.appendingPathComponent(".macmosh/desks.tsv"), encoding: .utf8)) ?? ""
    }

    private func defined(_ h: HostHarness, _ name: String) -> Bool {
        desksFile(h).split(separator: "\n").contains { $0.hasPrefix(name + "\t") }
    }

    private func hostLog(_ h: HostHarness) -> String {
        (try? String(contentsOf: h.home.appendingPathComponent(".macmosh/host.log"), encoding: .utf8)) ?? ""
    }

    /// The log's lines that say something failed.
    private func failures(_ h: HostHarness) -> [String] {
        hostLog(h).split(separator: "\n").map(String.init)
            .filter { $0.contains("failed") || $0.contains("error") || $0.contains("could not") }
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
            Issue.record(Comment(rawValue: "timed out after \(Int(seconds)) s (ViewWindowTests.swift:\(line))\n"
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

    /// The views of a desk, as `<view id>|<view name>|<window shown>`, found by MacMosh's tag.
    private func views(_ h: HostHarness, of deskID: String) -> [String] {
        h.tmux(["list-sessions", "-F", "#{session_id}|#{session_name}|#{window_id}|#{@macmosh-view}"]).stdout
            .split(separator: "\n").map(String.init)
            .filter { $0.hasSuffix("|" + deskID) }
            .map { $0.split(separator: "|").prefix(3).joined(separator: "|") }
            .sorted()
    }

    /// The id of the one view of the desk that shows this window.
    private func view(_ h: HostHarness, of deskID: String, on window: String) throws -> String {
        let found = views(h, of: deskID).filter { $0.hasSuffix("|" + window) }
        try #require(found.count == 1, "views on \(window): \(views(h, of: deskID))")
        return String(found[0].split(separator: "|")[0])
    }

    private func exists(_ h: HostHarness, _ sessionID: String) -> Bool { h.sessionFormat(sessionID, "#{session_id}") != nil }

    private func hasClient(_ h: HostHarness, _ sessionID: String) -> Bool { h.clients().contains { $0.hasPrefix(sessionID + "|") } }

    /// The records views leave on the desk server (@macmosh-view-<n>).
    private func records(_ h: HostHarness) -> [String] {
        h.tmux(["show-options", "-s"]).stdout.split(separator: "\n").map(String.init).filter { $0.hasPrefix("@macmosh-view-") }
    }

    /// Opens a tab on the desk the way the app does: the script's attach, in a terminal of its own.
    private func openTab(_ h: HostHarness, _ label: String, _ arguments: [String], script: String? = nil) throws {
        try h.startClient(label, ["/bin/bash", script ?? h.scriptURL.path, "attach"] + arguments)
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

    // MARK: - A window closes

    /// `exit` in a window a tab shows: that tab's view ends and its client exits. The tab on another
    /// window, the plain tab on the desk's own session, the desk's other windows and its definition
    /// stay, and the view's closing is ignored by the exit path as a view's always is.
    @Test func exitInAWindowATabShowsEndsThatTabsViewAndNoOther() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        let (desk, ids) = try deskWithWindows(h, "website", 3)
        try openTab(h, "plain", ["website"])
        try openTab(h, "one", ["--window", ids[1], "website"])
        try openTab(h, "two", ["--window", ids[2], "website"])
        try ready(h, desk, views: 2, clients: 3)
        let one = try view(h, of: desk, on: ids[1])
        let two = try view(h, of: desk, on: ids[2])
        // The rule is on each view, and the window it shows is remembered on it.
        #expect(h.sessionFormat(one, "#{@macmosh-window}") == ids[1])
        #expect(h.tmux(["show-hooks", "-t", one, "session-window-changed"]).stdout.contains("[1089]"))
        #expect(!h.tmux(["show-hooks", "-t", desk, "session-window-changed"]).stdout.contains("[1089]"))
        #expect(!h.tmux(["show-hooks", "-g", "session-window-changed"]).stdout.contains("[1089]"))

        typeExit(h, ids[1])
        try wait(h) { !exists(h, one) && !hasClient(h, one) }
        #expect(exists(h, two) && hasClient(h, two))
        #expect(h.currentWindow(two) == ids[2])
        #expect(hasClient(h, desk))
        #expect(h.currentWindow(desk) == ids[0])
        #expect(windowIDs(h, desk) == [ids[0], ids[2]])
        #expect(h.clients().count == 2)
        try wait(h) { hostLog(h).contains("desk-closed\tignored: a view") }
        #expect(!records(h).contains { $0.hasPrefix("@macmosh-view-\(one.dropFirst()) ") }, "\(records(h))")
        try proveTheHookHasRun(h)
        #expect(defined(h, "website"))
        #expect(failures(h).isEmpty, "\(failures(h))")
    }

    /// kill-window on the window a tab shows does the same, and a view on another window is untouched.
    @Test func killWindowOnTheWindowATabShowsEndsThatTabsView() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        let (desk, ids) = try deskWithWindows(h, "website", 3)
        try openTab(h, "one", ["--window", ids[1], "website"])
        try openTab(h, "two", ["--window", ids[2], "website"])
        try ready(h, desk, views: 2, clients: 2)
        let one = try view(h, of: desk, on: ids[1])
        let two = try view(h, of: desk, on: ids[2])

        #expect(h.tmux(["kill-window", "-t", ids[2]]).exitCode == 0)
        try wait(h) { !exists(h, two) && !hasClient(h, two) }
        #expect(exists(h, one) && hasClient(h, one))
        #expect(h.currentWindow(one) == ids[1])
        #expect(h.sessionFormat(one, "#{@macmosh-window}") == ids[1])
        #expect(windowIDs(h, desk) == [ids[0], ids[1]])
        #expect(h.currentWindow(desk) == ids[0])
        try proveTheHookHasRun(h)
        #expect(defined(h, "website"))
        #expect(failures(h).isEmpty, "\(failures(h))")
    }

    /// A tab the person switched to other windows (with tmux's own keys, which run select-window and
    /// next-window in the tab's view) ends when the window it shows now closes, not the one it was
    /// opened on or one it showed before.
    @Test func aTabThePersonSwitchedEndsWithTheWindowItShowsNow() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        let (desk, ids) = try deskWithWindows(h, "website", 4)
        try openTab(h, "one", ["--window", ids[0], "website"])
        try ready(h, desk, views: 1, clients: 1)
        let one = try view(h, of: desk, on: ids[0])

        #expect(h.tmux(["select-window", "-t", one + ":" + ids[1]]).exitCode == 0)
        try wait(h) { h.sessionFormat(one, "#{@macmosh-window}") == ids[1] }
        typeExit(h, ids[0])
        try wait(h) { !windowIDs(h, desk).contains(ids[0]) }
        Thread.sleep(forTimeInterval: 0.5)
        #expect(exists(h, one) && hasClient(h, one))
        #expect(h.currentWindow(one) == ids[1])

        #expect(h.tmux(["next-window", "-t", one]).exitCode == 0)
        try wait(h) { h.sessionFormat(one, "#{@macmosh-window}") == ids[2] }
        typeExit(h, ids[1])
        try wait(h) { !windowIDs(h, desk).contains(ids[1]) }
        Thread.sleep(forTimeInterval: 0.5)
        #expect(exists(h, one) && hasClient(h, one))
        #expect(h.currentWindow(one) == ids[2])

        typeExit(h, ids[2])
        try wait(h) { !exists(h, one) && h.clients().isEmpty }
        #expect(windowIDs(h, desk) == [ids[3]])
        #expect(defined(h, "website"))
        #expect(failures(h).isEmpty, "\(failures(h))")
    }

    /// Two tabs on one window both end when it closes. The plain tab on the desk's own session, which
    /// showed that window too, moves to another window as before.
    @Test func twoTabsOnOneWindowBothEndAndAPlainTabMovesAsBefore() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        let (desk, ids) = try deskWithWindows(h, "website", 2)
        _ = h.tmux(["select-window", "-t", desk + ":" + ids[1]])
        try openTab(h, "plain", ["website"])
        try openTab(h, "one", ["--window", ids[1], "website"])
        try openTab(h, "two", ["--window", ids[1], "website"])
        try ready(h, desk, views: 2, clients: 3)
        let made = views(h, of: desk).map { String($0.split(separator: "|")[0]) }

        typeExit(h, ids[1])
        try wait(h) { views(h, of: desk).isEmpty && h.clients().count == 1 }
        #expect(made.allSatisfy { !exists(h, $0) })
        #expect(hasClient(h, desk))
        #expect(h.currentWindow(desk) == ids[0])
        #expect(windowIDs(h, desk) == [ids[0]])
        try proveTheHookHasRun(h)
        #expect(defined(h, "website"))
        #expect(failures(h).isEmpty, "\(failures(h))")
    }

    /// A tab with a label and no window option, and a tab on a new window, both get the rule.
    @Test func aLabelledTabAndATabOnANewWindowGetTheRuleToo() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        let (desk, ids) = try deskWithWindows(h, "website", 2)
        try openTab(h, "label", ["--label", "a1b2c3d4", "website"])
        try openTab(h, "new", ["--new-window", "website"])
        try ready(h, desk, views: 2, clients: 2)
        let added = try #require(windowIDs(h, desk).last)
        #expect(!ids.contains(added))
        let labelled = try view(h, of: desk, on: ids[0])
        let fresh = try view(h, of: desk, on: added)
        #expect(h.sessionFormat(labelled, "#{@macmosh-label}|#{@macmosh-window}") == "a1b2c3d4|" + ids[0])
        #expect(h.sessionFormat(fresh, "#{@macmosh-window}") == added)

        typeExit(h, added)
        try wait(h) { !exists(h, fresh) && h.clients().count == 1 }
        #expect(exists(h, labelled))
        typeExit(h, ids[0])
        try wait(h) { !exists(h, labelled) && h.clients().isEmpty }
        #expect(windowIDs(h, desk) == [ids[1]])
        #expect(defined(h, "website"))
        #expect(failures(h).isEmpty, "\(failures(h))")
    }

    /// A view left alone in its group (its desk's own session killed by hand) holds the desk's windows.
    /// Ending it would close them, so when its window closes it keeps today's behaviour: it moves to
    /// another window, and every other window keeps running.
    @Test func aViewAloneInItsGroupKeepsTodaysBehaviour() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        let (desk, ids) = try deskWithWindows(h, "website", 3)
        try openTab(h, "one", ["--window", ids[1], "website"])
        try ready(h, desk, views: 1, clients: 1)
        let one = try view(h, of: desk, on: ids[1])
        #expect(h.tmux(["kill-session", "-t", desk]).exitCode == 0)
        #expect(windowIDs(h, one) == ids)

        typeExit(h, ids[1])
        try wait(h) { windowIDs(h, one) == [ids[0], ids[2]] }
        Thread.sleep(forTimeInterval: 1)
        #expect(exists(h, one) && hasClient(h, one))
        #expect(windowIDs(h, one) == [ids[0], ids[2]])
        #expect(h.sessionFormat(one, "#{@macmosh-window}") == h.currentWindow(one))
    }

    // MARK: - The last window

    /// The desk's last window closing goes as before: every session of the group closes, the definition
    /// goes after the hook's wait unless the desk is permanent, the log has no error, and no record of
    /// a view is left on the server.
    @Test func theDesksLastWindowClosingGoesAsBefore() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        let (desk, ids) = try deskWithWindows(h, "website", 2)
        let (notes, noteIDs) = try deskWithWindows(h, "notes", 1, permanent: true)
        try openTab(h, "one", ["--window", ids[0], "website"])
        try openTab(h, "two", ["--window", ids[1], "--label", "abcd1234", "website"])
        try openTab(h, "three", ["--window", ids[1], "website"])
        try openTab(h, "four", ["--window", noteIDs[0], "notes"])
        try ready(h, desk, views: 3, clients: 4)
        try ready(h, notes, views: 1, clients: 4)

        typeExit(h, ids[0])
        try wait(h) { views(h, of: desk).count == 2 && h.clients().count == 3 }
        typeExit(h, ids[1])
        try wait(h) { !defined(h, "website") }
        #expect(lookup(h, "website") == nil)
        #expect(views(h, of: desk).isEmpty)
        #expect(hostLog(h).contains("desk-closed\tremoved website: its last shell exited"))

        typeExit(h, noteIDs[0])
        try wait(h) { h.sessionNames().isEmpty && h.clients().isEmpty }
        try proveTheHookHasRun(h)
        #expect(defined(h, "notes"))
        #expect(hostLog(h).contains("desk-closed\tkept notes: permanent"))
        try wait(h) { records(h).isEmpty }
        #expect(failures(h).isEmpty, "\(failures(h))")
    }

    // MARK: - A tab from an older script

    /// The script before this change (0.9.0), for a test: the same script without the one line that
    /// gives a view the rule, and with its old version number.
    private func olderScript(_ h: HostHarness) throws -> String {
        let text = try String(contentsOf: h.scriptURL, encoding: .utf8)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let kept = lines.filter { $0.trimmingCharacters(in: .whitespaces) != "mm_view_rule \"$vid\"" }
        #expect(lines.count - kept.count == 1)
        let old = kept.joined(separator: "\n")
            .replacingOccurrences(of: "\nMACMOSH_HOST_VERSION=\(h.scriptVersion)\n", with: "\nMACMOSH_HOST_VERSION=0.9.0\n")
        #expect(old.contains("\nMACMOSH_HOST_VERSION=0.9.0\n"))
        let url = h.home.appendingPathComponent("older-macmosh-host")
        try old.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    /// A tab whose view an older script made (with no rule) keeps today's behaviour under the new
    /// script: when its window closes it moves to another, and nothing fails. A tab the new script
    /// opens beside it gets the rule.
    @Test func aTabFromTheOlderScriptKeepsTodaysBehaviour() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        let older = try olderScript(h)
        #expect(h.shell("/bin/bash '\(older)' version").stdout == "0.9.0\n")
        let start = h.shell("/bin/bash '\(older)' start")
        #expect(start.exitCode == 0)
        #expect(h.shell("/bin/bash '\(older)' desk-new website '\(h.home.path)'").exitCode == 0)
        let desk = try sid(h, "website")
        for _ in 1..<3 { _ = h.tmux(["new-window", "-d", "-t", desk + ":"]) }
        let ids = windowIDs(h, desk)
        try openTab(h, "old", ["--window", ids[1], "website"], script: older)
        try ready(h, desk, views: 1, clients: 1)
        let old = try view(h, of: desk, on: ids[1])
        #expect(h.sessionFormat(old, "#{@macmosh-window}") == "")
        #expect(!h.tmux(["show-hooks", "-t", old, "session-window-changed"]).stdout.contains("[1089]"))

        // The new script arrives: status, a dry run, and a tab of its own on another window.
        #expect(h.run(["status"]).exitCode == 0)
        #expect(h.run(["attach", "--dry-run", "website"]).stdout == "ok\n")
        try openTab(h, "new", ["--window", ids[2], "website"])
        try ready(h, desk, views: 2, clients: 2)
        let fresh = try view(h, of: desk, on: ids[2])

        typeExit(h, ids[1])
        try wait(h) { !windowIDs(h, desk).contains(ids[1]) && h.currentWindow(old) != ids[1] }
        Thread.sleep(forTimeInterval: 0.5)
        #expect(exists(h, old) && hasClient(h, old))
        #expect(exists(h, fresh) && hasClient(h, fresh))
        typeExit(h, ids[2])
        try wait(h) { !exists(h, fresh) && h.clients().count == 1 }
        #expect(exists(h, old) && hasClient(h, old))
        let out = h.run(["status"])
        #expect(out.exitCode == 0)
        #expect(out.stdout.contains("\nview\twebsite\t"), "\(out.stdout)")
        try proveTheHookHasRun(h)
        #expect(defined(h, "website"))
        #expect(failures(h).isEmpty, "\(failures(h))")
    }

    // MARK: - Rename and remove

    /// desk-rename keeps the rule (it names the view by its id), and desk-remove --kill takes such
    /// views and their tabs as before.
    @Test func renameAndRemoveWithKillWorkAsBefore() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        let (desk, ids) = try deskWithWindows(h, "website", 3)
        try openTab(h, "one", ["--window", ids[1], "website"])
        try openTab(h, "two", ["--window", ids[2], "website"])
        try ready(h, desk, views: 2, clients: 2)
        let one = try view(h, of: desk, on: ids[1])

        #expect(h.run(["desk-rename", "website", "notes"]).exitCode == 0)
        #expect(lookup(h, "notes") == desk)
        #expect(h.sessionFormat(one, "#{@macmosh-desk}") == "notes")
        typeExit(h, ids[1])
        try wait(h) { !exists(h, one) && h.clients().count == 1 }
        #expect(defined(h, "notes"))

        #expect(h.run(["desk-new", "api", h.home.path]).exitCode == 0)
        #expect(h.run(["desk-remove", "notes", "--kill"]).exitCode == 0)
        try wait(h) { h.sessionNames() == ["api"] && h.clients().isEmpty }
        #expect(!defined(h, "notes"))
        try proveTheHookHasRun(h)
        #expect(defined(h, "api"))
        try wait(h) { records(h).isEmpty }
        #expect(failures(h).isEmpty, "\(failures(h))")
    }
}
}
