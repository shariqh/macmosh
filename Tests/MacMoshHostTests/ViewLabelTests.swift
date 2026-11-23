import Foundation
import Testing

extension HostScriptTests {
/// Labels: `attach --label <word>` gives a tab's view a short word the daily Mac made up, and the
/// status report echoes it on the view's line, so the daily Mac can tell which of its terminal tabs
/// shows which view (issue 111, part of 105). The word is 4 to 32 characters, each a digit or a letter
/// from a to f. With no window option, a labelled tab gets a view on the window the desk shows now.
///
/// Every wait ends as soon as its condition holds. The limits are long because CI runners are slow.
@Suite struct ViewLabelTests {
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

    private func wait(_ h: HostHarness, seconds: Double = 30, line: UInt = #line, _ condition: () -> Bool) throws {
        do {
            try waitFor(seconds: seconds, condition)
        } catch {
            let log = hostLog(h).split(separator: "\n").suffix(20).joined(separator: "\n")
            Issue.record(Comment(rawValue: "timed out after \(Int(seconds)) s (ViewLabelTests.swift:\(line))\n"
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

    /// The views of a desk, as `<view id>|<view name>|<window shown>|<label>`, found by MacMosh's tag.
    private func views(_ h: HostHarness, of deskID: String) -> [String] {
        h.tmux(["list-sessions", "-F", "#{session_id}|#{session_name}|#{window_id}|#{@macmosh-label}|#{@macmosh-view}"]).stdout
            .split(separator: "\n").map(String.init)
            .filter { $0.hasSuffix("|" + deskID) }
            .map { $0.split(separator: "|", omittingEmptySubsequences: false).prefix(4).joined(separator: "|") }
            .sorted()
    }

    /// The view carrying this label, as `(id, name, window)`.
    private func view(_ h: HostHarness, of deskID: String, labelled label: String) throws -> (String, String, String) {
        let line = try #require(views(h, of: deskID).first { $0.hasSuffix("|" + label) },
                                "no view labelled \(label): \(views(h, of: deskID))")
        let f = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        return (f[0], f[1], f[2])
    }

    /// Every session that carries MacMosh's view tag, whatever desk it names.
    private func taggedViews(_ h: HostHarness) -> [String] {
        h.tmux(["list-sessions", "-F", "#{@macmosh-view}"]).stdout.split(separator: "\n").map(String.init)
    }

    private func viewLines(_ report: String) -> [String] {
        report.split(separator: "\n").map(String.init).filter { $0.hasPrefix("view\t") }
    }

    /// Opens a tab on the desk the way the app will: the script's attach, in a terminal of its own.
    private func openTab(_ h: HostHarness, _ label: String, _ arguments: [String]) throws {
        try h.startClient(label, ["/bin/bash", h.scriptURL.path, "attach"] + arguments)
    }

    /// A desk with `count` windows, showing its first.
    private func deskWithWindows(_ h: HostHarness, _ name: String, _ count: Int, permanent: Bool = false) throws -> (String, [String]) {
        #expect(h.run(["desk-new", name, h.home.path] + (permanent ? ["--permanent"] : [])).exitCode == 0)
        let id = try sid(h, name)
        for _ in 1..<count { _ = h.tmux(["new-window", "-d", "-t", id + ":"]) }
        return (id, windowIDs(h, id))
    }

    // MARK: - Stored and echoed

    @Test func aLabelIsStoredOnTheViewAndEchoedInTheReport() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        let (desk, ids) = try deskWithWindows(h, "website", 3)

        try openTab(h, "one", ["--window", ids[1], "--label", "0a1b2c3d", "website"])
        try openTab(h, "two", ["--label", "ffff0000aaaa", "--new-window", "website"])
        try openTab(h, "three", ["--window", ids[2], "website"])
        try wait(h) { h.clients().count == 3 && views(h, of: desk).count == 3 }
        let added = try #require(windowIDs(h, desk).last)
        #expect(!ids.contains(added))

        let (one, oneName, oneWindow) = try view(h, of: desk, labelled: "0a1b2c3d")
        let (two, twoName, twoWindow) = try view(h, of: desk, labelled: "ffff0000aaaa")
        #expect(oneWindow == ids[1])
        #expect(twoWindow == added)
        #expect(h.sessionFormat(one, "#{@macmosh-label}") == "0a1b2c3d")
        #expect(h.sessionFormat(two, "#{@macmosh-label}") == "ffff0000aaaa")
        // Only the views carry it: the desk's own session has none.
        #expect(h.sessionFormat(desk, "#{@macmosh-label}") == "")
        let (three, threeName, _) = try view(h, of: desk, labelled: "")
        #expect(h.sessionFormat(three, "#{@macmosh-label}") == "")

        let out = h.run(["status"]).stdout
        let lines = viewLines(out)
        #expect(lines.count == 3, "\(out)")
        #expect(lines.contains("view\twebsite\t\(oneName)\t\(ids[1])\t1\t0a1b2c3d"), "\(out)")
        #expect(lines.contains("view\twebsite\t\(twoName)\t\(added)\t1\tffff0000aaaa"), "\(out)")
        // A view with no label has an empty last field.
        #expect(lines.contains("view\twebsite\t\(threeName)\t\(ids[2])\t1\t"), "\(out)")
        #expect(out.contains("\nview\twebsite\t\(threeName)\t\(ids[2])\t1\t\n"), "\(out)")
        // The desk's own lines are as before.
        #expect(out.contains("\ndesk\twebsite\t4\t3\n"), "\(out)")
        #expect(hostLog(h).contains("attach\twebsite (window \(ids[1]), label 0a1b2c3d)"))
    }

    /// A label set by hand that isn't a label's form is left out of the report, and can't break the
    /// view's line around it.
    @Test func aLabelSetByHandThatIsNotALabelIsLeftOut() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        let (desk, ids) = try deskWithWindows(h, "website", 1)
        _ = h.run(["attach", "--window", ids[0], "--label", "abcd", "website"])
        let (vid, name, _) = try view(h, of: desk, labelled: "abcd")
        for odd in ["ab|cd", "ABCD", "abc", "ab\tcd"] {
            _ = h.tmux(["set-option", "-t", vid, "@macmosh-label", odd])
            let out = h.run(["status"]).stdout
            #expect(viewLines(out) == ["view\twebsite\t\(name)\t\(ids[0])\t0\t"], "\(odd): \(out)")
        }
    }

    // MARK: - Refused

    @Test func badLabelsAreRefusedAndMakeNothing() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        let (desk, ids) = try deskWithWindows(h, "website", 2)
        // A permanent desk that is closed: a refused attach must not make it again.
        #expect(h.run(["desk-new", "notes", h.home.path, "--permanent"]).exitCode == 0)
        typeExit(h, "=notes:")
        try wait(h) { lookup(h, "notes") == nil }
        let before = h.sessionNames()

        let bad = ["", "abc", String(repeating: "a", count: 33), "abcD", "abcg", "ab cd", "ab'cd", "-abcd", "--dry-run"]
        for label in bad {
            for form in [[], ["--window", ids[1]], ["--new-window"], ["--dry-run"]] {
                for desk in ["website", "notes"] {
                    let r = h.run(["attach"] + form + ["--label", label, desk])
                    #expect(r.exitCode == 2, "\(form) \(label) \(desk): \(r.stderr)")
                    #expect(r.stderr.contains("4 to 32 characters"), "\(r.stderr)")
                    #expect(r.stdout.isEmpty)
                }
            }
        }
        // No value at all, and --label with --cc.
        let usage: [[String]] = [
            ["website", "--label"], ["--label"],
            ["--cc", "--label", "abcd", "website"], ["--label", "abcd", "--cc", "website"],
            ["--cc", "--label", "abcd", "notes"], ["--cc", "--dry-run", "--label", "abcd", "website"],
        ]
        for arguments in usage {
            let r = h.run(["attach"] + arguments)
            #expect(r.exitCode == 2, "\(arguments): \(r.stderr)")
            let rule = arguments.contains("--cc") ? "can't be used with --label" : "4 to 32 characters"
            #expect(r.stderr.contains(rule), "\(arguments): \(r.stderr)")
        }
        #expect(h.sessionNames() == before)
        #expect(windowIDs(h, desk) == ids)
        #expect(taggedViews(h).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: h.home.appendingPathComponent(".macmosh/lock").path))

        // The longest and the shortest are taken.
        #expect(h.run(["attach", "--dry-run", "--label", String(repeating: "f", count: 32), "website"]).stdout == "ok\n")
        #expect(h.run(["attach", "--dry-run", "--label", "0000", "website"]).stdout == "ok\n")
    }

    // MARK: - No window option

    @Test func aLabelWithNoWindowOptionOpensAViewOnTheDesksCurrentWindow() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        let (desk, ids) = try deskWithWindows(h, "website", 3)
        // The desk shows its last window, not the lowest one a new view would start on.
        _ = h.tmux(["select-window", "-t", desk + ":" + ids[2]])
        try openTab(h, "plain", ["website"])
        try wait(h) { h.clients().count == 1 }

        try openTab(h, "labelled", ["--label", "beef", "website"])
        try wait(h) { h.clients().count == 2 && views(h, of: desk).count == 1 }
        let (vid, name, shown) = try view(h, of: desk, labelled: "beef")
        #expect(shown == ids[2])
        #expect(name.hasPrefix("website+"))
        #expect(h.clients().contains { $0.hasPrefix(vid + "|") })
        // The tab that was open is still a client of the desk's own session, on the window it showed.
        #expect(h.clients().contains { $0.hasPrefix(desk + "|website|") })
        #expect(h.currentWindow(desk) == ids[2])
        #expect(windowIDs(h, desk) == ids)
        try wait(h) { h.sessionFormat(vid, "#{destroy-unattached}") == "on" }

        // From now on the two tabs move on their own.
        _ = h.tmux(["select-window", "-t", desk + ":" + ids[0]])
        #expect(h.currentWindow(vid) == ids[2])
        #expect(viewLines(h.run(["status"]).stdout) == ["view\twebsite\t\(name)\t\(ids[2])\t1\tbeef"])
        #expect(hostLog(h).contains("attach\twebsite (window \(ids[2]), label beef)"))
    }

    // MARK: - Closed and missing desks

    @Test func aLabelOnAClosedPermanentDeskMakesTheDeskAndThenTheView() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        #expect(h.run(["desk-new", "notes", h.home.path, "--permanent"]).exitCode == 0)
        typeExit(h, "=notes:")
        try wait(h) { lookup(h, "notes") == nil }
        #expect(defined(h, "notes"))

        try openTab(h, "one", ["--label", "cafe01", "notes"])
        try wait(h) { lookup(h, "notes") != nil && h.clients().count == 1 }
        let desk = try sid(h, "notes")
        try wait(h) { views(h, of: desk).count == 1 }
        let (vid, _, shown) = try view(h, of: desk, labelled: "cafe01")
        #expect(shown == windowIDs(h, desk)[0])
        #expect(h.clients()[0].hasPrefix(vid + "|"))
        #expect(h.sessionFormat(desk, "#{session_group}") == "macmosh+g" + desk.dropFirst())
        #expect(h.sessionFormat(vid, "#{session_group}") == h.sessionFormat(desk, "#{session_group}"))
        #expect(defined(h, "notes"))
        #expect(h.sessionNames().filter { !$0.contains("+") } == ["notes"])
    }

    @Test func aLabelOnADeskThatIsNotThereFailsAsPlainAttachDoesAndMakesNothing() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        #expect(h.run(["desk-new", "website", h.home.path]).exitCode == 0)
        // "api" exited and its definition is gone; "ghost" never was.
        #expect(h.run(["desk-new", "api", h.home.path]).exitCode == 0)
        typeExit(h, "=api:")
        try wait(h) { !defined(h, "api") }
        let before = h.sessionNames()
        let list = desksFile(h)

        for name in ["api", "ghost", "website+1"] {
            let plain = h.run(["attach", name])
            for form in [["--label", "abcd"], ["--label", "abcd", "--new-window"], ["--dry-run", "--label", "abcd"]] {
                let labelled = h.run(["attach"] + form + [name])
                #expect(labelled.exitCode == plain.exitCode, "\(name) \(form): \(labelled.stderr)")
                #expect(labelled.exitCode == 4)
                #expect(labelled.stderr == plain.stderr)
            }
        }
        #expect(h.sessionNames() == before)
        #expect(desksFile(h) == list)
        #expect(taggedViews(h).isEmpty)
    }

    // MARK: - Rename and switching windows

    @Test func afterARenameTheViewsAreListedUnderTheNewNameWithTheirLabels() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        let (desk, ids) = try deskWithWindows(h, "website", 2)
        try openTab(h, "one", ["--window", ids[0], "--label", "aaaa", "website"])
        try openTab(h, "two", ["--window", ids[1], "--label", "bbbb", "website"])
        try wait(h) { h.clients().count == 2 && views(h, of: desk).count == 2 }
        let (_, one, _) = try view(h, of: desk, labelled: "aaaa")
        let (_, two, _) = try view(h, of: desk, labelled: "bbbb")

        #expect(h.run(["desk-rename", "website", "notes"]).exitCode == 0)
        let lines = viewLines(h.run(["status"]).stdout).sorted()
        #expect(lines == [
            "view\tnotes\t\(one)\t\(ids[0])\t1\taaaa",
            "view\tnotes\t\(two)\t\(ids[1])\t1\tbbbb",
        ].sorted())
    }

    @Test func whenThePersonSwitchesWindowsInALabelledTabTheRecordFollows() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        let (desk, ids) = try deskWithWindows(h, "website", 3)
        try openTab(h, "one", ["--window", ids[0], "--label", "1234abcd", "website"])
        try wait(h) { h.clients().count == 1 && views(h, of: desk).count == 1 }
        let (vid, name, _) = try view(h, of: desk, labelled: "1234abcd")
        #expect(viewLines(h.run(["status"]).stdout) == ["view\twebsite\t\(name)\t\(ids[0])\t1\t1234abcd"])

        // What the person's next-window key runs: next-window on the session the tab shows, its view.
        #expect(h.tmux(["next-window", "-t", vid + ":"]).exitCode == 0)
        try wait(h) { h.currentWindow(vid) != ids[0] }
        let now = try #require(h.currentWindow(vid))
        #expect(now != ids[0])
        #expect(viewLines(h.run(["status"]).stdout) == ["view\twebsite\t\(name)\t\(now)\t1\t1234abcd"])
        _ = h.tmux(["select-window", "-t", vid + ":" + ids[2]])
        #expect(viewLines(h.run(["status"]).stdout) == ["view\twebsite\t\(name)\t\(ids[2])\t1\t1234abcd"])
        // The desk's own session did not move.
        #expect(h.currentWindow(desk) == ids[0])
    }

    // MARK: - Dry run

    @Test func aDryRunWithALabelMakesNothing() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        let (desk, ids) = try deskWithWindows(h, "website", 2)
        let before = h.sessionNames()
        for form in [[], ["--window", ids[1]], ["--new-window"]] {
            let r = h.run(["attach", "--dry-run", "--label", "abcd"] + form + ["website"])
            #expect(r.exitCode == 0, "\(form): \(r.stderr)")
            #expect(r.stdout == "ok\n")
        }
        // The window is still checked.
        let closed = h.run(["attach", "--dry-run", "--label", "abcd", "--window", "@99", "website"])
        #expect(closed.exitCode == 4)
        #expect(closed.stderr.contains("That window has closed."))
        #expect(h.sessionNames() == before)
        #expect(windowIDs(h, desk) == ids)
        #expect(taggedViews(h).isEmpty)
        let labels = h.tmux(["list-sessions", "-F", "#{@macmosh-label}"]).stdout
        #expect(labels.split(separator: "\n").allSatisfy { $0.isEmpty }, "\(labels)")

        // Like any dry run, it makes a closed permanent desk again, and no view on it.
        #expect(h.run(["desk-new", "notes", h.home.path, "--permanent"]).exitCode == 0)
        typeExit(h, "=notes:")
        try wait(h) { lookup(h, "notes") == nil }
        #expect(h.run(["attach", "--dry-run", "--label", "abcd", "notes"]).stdout == "ok\n")
        #expect(lookup(h, "notes") != nil)
        #expect(taggedViews(h).isEmpty)
    }

    // MARK: - The removal rule, with labelled views there

    @Test func aLabelledTabClosingRemovesNothing() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        let (desk, ids) = try deskWithWindows(h, "website", 2)
        try openTab(h, "one", ["--window", ids[1], "--label", "aaaa", "website"])
        try openTab(h, "two", ["--label", "bbbb", "website"])
        try wait(h) { h.clients().count == 2 && views(h, of: desk).count == 2 }
        let (one, _, _) = try view(h, of: desk, labelled: "aaaa")
        try wait(h) { h.sessionFormat(one, "#{destroy-unattached}") == "on" }

        try h.hangUp(clientOf: one)
        try wait(h) { views(h, of: desk).count == 1 }
        try proveTheHookHasRun(h)
        #expect(defined(h, "website"))
        #expect(windowIDs(h, desk) == ids)
        #expect(lookup(h, "website") == desk)
        #expect(hostLog(h).contains("desk-closed\tignored: a view"))
    }

    @Test func theLastShellExitingRemovesADeskWithLabelledViewsAndAPermanentOneStays() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        let (web, webIDs) = try deskWithWindows(h, "website", 2)
        let (notes, notesIDs) = try deskWithWindows(h, "notes", 2, permanent: true)
        try openTab(h, "one", ["--window", webIDs[1], "--label", "aaaa", "website"])
        try openTab(h, "two", ["--label", "bbbb", "website"])
        try openTab(h, "three", ["--window", notesIDs[1], "--label", "cccc", "notes"])
        try openTab(h, "four", ["--label", "dddd", "notes"])
        try wait(h) { h.clients().count == 4 && views(h, of: web).count == 2 && views(h, of: notes).count == 2 }

        for id in webIDs + notesIDs { typeExit(h, id) }
        try wait(h) { !defined(h, "website") }
        try wait(h) { h.sessionNames().isEmpty }
        try wait(h) { hostLog(h).contains("desk-closed\tremoved website: its last shell exited") }
        try wait(h) { hostLog(h).contains("desk-closed\tkept notes: permanent") }
        try proveTheHookHasRun(h)
        #expect(defined(h, "notes"))
        #expect(!defined(h, "website"))
        #expect(!hostLog(h).contains("desk-closed\tremoved notes"))
    }
}
}
