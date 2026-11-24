import Foundation
import Testing

extension HostScriptTests {
/// The bar at the bottom of a tab on one window of a desk shows the desk's name, as a plain tab's does,
/// not the view's own name (`<desk>+<number>`) (issue 130). A view carries its desk's name in the user
/// option `@macmosh-desk`, and its own `status-left` reads that option where the server's `status-left`
/// names the session (`#S` or `#{session_name}`). `desk-rename` updates the option on every view of the
/// desk, so the bars follow.
///
/// Every wait ends as soon as its condition holds. The limits are long because CI runners are slow.
@Suite struct ViewBarTests {
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
            Issue.record(Comment(rawValue: "timed out after \(Int(seconds)) s (ViewBarTests.swift:\(line))\n"
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

    /// The views of a desk, as `<view id>|<window shown>|<label>`, found by MacMosh's tag.
    private func views(_ h: HostHarness, of deskID: String) -> [String] {
        h.tmux(["list-sessions", "-F", "#{session_id}|#{window_id}|#{@macmosh-label}|#{@macmosh-view}"]).stdout
            .split(separator: "\n").map(String.init)
            .filter { $0.hasSuffix("|" + deskID) }
            .map { $0.split(separator: "|", omittingEmptySubsequences: false).prefix(3).joined(separator: "|") }
            .sorted()
    }

    /// The id of the view of a desk that shows this window, or carries this label.
    private func view(_ h: HostHarness, of deskID: String, showing window: String? = nil, labelled label: String? = nil) throws -> String {
        let line = try #require(views(h, of: deskID).first { line in
            let f = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            return (window == nil || f[1] == window) && (label == nil || f[2] == label)
        }, "no such view: \(views(h, of: deskID))")
        return String(line.split(separator: "|")[0])
    }

    /// What the bar's left side shows for one session: its status-left, expanded as tmux expands it
    /// (`E:`, "the result of expanding the content of the status-left option", man tmux, FORMATS).
    private func bar(_ h: HostHarness, _ sessionID: String) -> String? {
        h.sessionFormat(sessionID, "#{E:status-left}")
    }

    /// The status-left set on this one session, or "" when it has none of its own.
    private func ownBar(_ h: HostHarness, _ sessionID: String) -> String {
        h.tmux(["show-options", "-t", sessionID, "-v", "status-left"]).stdout
    }

    private func globalBar(_ h: HostHarness) -> String {
        h.tmux(["show-options", "-gv", "status-left"]).stdout
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

    /// The person's own tmux settings, which the desk server reads at start.
    private func writeUserTmuxConf(_ h: HostHarness, _ text: String) throws {
        try text.write(to: h.home.appendingPathComponent(".tmux.conf"), atomically: true, encoding: .utf8)
    }

    // MARK: - What tmux 3.8 does

    /// Pinned before the script relied on it: tmux 3.8's own status-left names the session through
    /// `#{session_name}` (the manual still says `[#S] `); `E:` in a list-sessions format expands it for
    /// each session; and a status-left set on one session of a group stays with that session.
    @Test func tmuxKeepsASessionsOwnBarToThatSessionOfTheGroup() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        #expect(globalBar(h) == "[#{session_name}] \n")
        let desk = try #require(h.tmux(["new-session", "-d", "-s", "website", "-t", "gtest", "-P", "-F", "#{session_id}"]).stdout
            .split(separator: "\n").first.map(String.init))
        let one = try #require(h.tmux(["new-session", "-d", "-t", desk, "-s", "website+1", "-P", "-F", "#{session_id}"]).stdout
            .split(separator: "\n").first.map(String.init))
        let two = try #require(h.tmux(["new-session", "-d", "-t", desk, "-s", "website+2", "-P", "-F", "#{session_id}"]).stdout
            .split(separator: "\n").first.map(String.init))
        #expect(h.sessionFormat(one, "#{session_group}") == "gtest")
        #expect(bar(h, one) == "[website+1] ")

        #expect(h.tmux(["set-option", "-t", one, "@macmosh-desk", "website", ";",
                        "set-option", "-t", one, "status-left", "[#{@macmosh-desk}] "]).exitCode == 0)
        #expect(bar(h, one) == "[website] ")
        #expect(bar(h, desk) == "[website] ")
        #expect(bar(h, two) == "[website+2] ")
        #expect(ownBar(h, desk) == "")
        #expect(ownBar(h, two) == "")
        #expect(globalBar(h) == "[#{session_name}] \n")
    }

    // MARK: - The default bar

    @Test func aViewsBarShowsItsDesksNameAndNothingElseChanges() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        let (web, ids) = try deskWithWindows(h, "website", 3)
        let (notes, notesIDs) = try deskWithWindows(h, "notes", 2)
        try openTab(h, "plain", ["website"])
        try openTab(h, "one", ["--window", ids[1], "website"])
        try openTab(h, "two", ["--window", ids[2], "website"])
        try openTab(h, "new", ["--new-window", "website"])
        try openTab(h, "labelled", ["--label", "beef", "website"])
        try openTab(h, "other", ["--window", notesIDs[1], "notes"])
        try wait(h) { h.clients().count == 6 && views(h, of: web).count == 4 && views(h, of: notes).count == 1 }
        let one = try view(h, of: web, showing: ids[1])
        let two = try view(h, of: web, showing: ids[2])
        let labelled = try view(h, of: web, labelled: "beef")
        let other = try view(h, of: notes, showing: notesIDs[1])
        let all = views(h, of: web).map { String($0.split(separator: "|")[0]) }

        // Every view of website reads as the plain tab does, a view of notes as notes.
        for v in all {
            try wait(h) { h.sessionFormat(v, "#{destroy-unattached}") == "on" }
            #expect(h.sessionFormat(v, "#{@macmosh-desk}") == "website", "\(v)")
            #expect(bar(h, v) == "[website] ", "\(v)")
            #expect(ownBar(h, v) == "[#{@macmosh-desk}] \n", "\(v)")
        }
        #expect(Set(all).isSuperset(of: [one, two, labelled]))
        #expect(h.sessionFormat(other, "#{@macmosh-desk}") == "notes")
        #expect(bar(h, other) == "[notes] ")

        // The desks' own sessions, and so the plain tab, are as they were: no bar or name of their own.
        #expect(bar(h, web) == "[website] ")
        #expect(bar(h, notes) == "[notes] ")
        for desk in [web, notes] {
            #expect(ownBar(h, desk) == "")
            #expect(h.sessionFormat(desk, "#{@macmosh-desk}") == "")
        }
        #expect(h.clients().contains { $0.hasPrefix(web + "|website|") })
        #expect(globalBar(h) == "[#{session_name}] \n")

        // The views keep their names, and the report is as before.
        let names = h.sessionNames()
        #expect(names.filter { $0.hasPrefix("website+") }.count == 4, "\(names)")
        let report = h.run(["status"]).stdout
        #expect(report.split(separator: "\n").filter { $0.hasPrefix("view\twebsite\twebsite+") }.count == 4, "\(report)")
        #expect(report.contains("\nview\tnotes\tnotes+"), "\(report)")
        #expect(!report.contains("@macmosh-desk"))
    }

    // MARK: - Rename

    @Test func afterARenameTheViewsBarsShowTheNewName() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        let (web, ids) = try deskWithWindows(h, "website", 2)
        let (notes, notesIDs) = try deskWithWindows(h, "notes", 2)
        try openTab(h, "one", ["--window", ids[0], "website"])
        try openTab(h, "two", ["--window", ids[1], "--label", "aaaa", "website"])
        try openTab(h, "other", ["--window", notesIDs[1], "notes"])
        try wait(h) { h.clients().count == 3 && views(h, of: web).count == 2 && views(h, of: notes).count == 1 }
        let mine = views(h, of: web).map { String($0.split(separator: "|")[0]) }
        let other = try view(h, of: notes, showing: notesIDs[1])

        #expect(h.run(["desk-rename", "website", "garden"]).exitCode == 0)
        for v in mine {
            #expect(h.sessionFormat(v, "#{@macmosh-desk}") == "garden", "\(v)")
            #expect(bar(h, v) == "[garden] ", "\(v)")
        }
        #expect(bar(h, web) == "[garden] ")
        #expect(bar(h, other) == "[notes] ")
        #expect(h.sessionFormat(other, "#{@macmosh-desk}") == "notes")

        // A rename that is refused changes no bar.
        #expect(h.run(["desk-rename", "garden", "notes"]).exitCode == 7)
        for v in mine { #expect(bar(h, v) == "[garden] ", "\(v)") }

        // And back again.
        #expect(h.run(["desk-rename", "garden", "website"]).exitCode == 0)
        for v in mine { #expect(bar(h, v) == "[website] ", "\(v)") }
        #expect(!FileManager.default.fileExists(atPath: h.home.appendingPathComponent(".macmosh/lock").path))
    }

    // MARK: - A bar the person set himself

    /// Only the session's name changes: the view's bar expands to exactly what the desk's own bar does.
    @Test(arguments: [
        ("#[fg=red]#S ##S %%H ", "#[fg=red]#{@macmosh-desk} ##S %%H "),
        ("<#{session_name}> #{session_windows} #S#S", "<#{@macmosh-desk}> #{session_windows} #{@macmosh-desk}#{@macmosh-desk}"),
        ("#{?session_grouped,#S,-} \"q\" $HOME", "#{?session_grouped,#{@macmosh-desk},-} \"q\" $HOME"),
    ])
    func aBarThePersonSetKeepsEverythingButTheName(set: String, want: String) throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        let quoted = set.replacingOccurrences(of: "'", with: "'\\''")
        try writeUserTmuxConf(h, "set -g status-left '\(quoted)'\n")
        _ = h.run(["start"])
        try #require(globalBar(h) == set + "\n", "tmux read: \(globalBar(h))")
        let (web, ids) = try deskWithWindows(h, "website", 2)
        try openTab(h, "one", ["--window", ids[1], "website"])
        try wait(h) { h.clients().count == 1 && views(h, of: web).count == 1 }
        let v = try view(h, of: web, showing: ids[1])
        #expect(ownBar(h, v) == want + "\n")
        #expect(bar(h, v) == bar(h, web))
        #expect(bar(h, web)?.contains("website") == true)
        #expect(ownBar(h, web) == "")
        #expect(globalBar(h) == set + "\n")

        #expect(h.run(["desk-rename", "website", "garden"]).exitCode == 0)
        #expect(bar(h, v) == bar(h, web))
        #expect(bar(h, web)?.contains("garden") == true)
    }

    /// A bar with neither form is left alone: the view gets no bar of its own, only the name.
    @Test func aBarThatDoesNotNameTheSessionIsLeftAlone() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        try writeUserTmuxConf(h, "set -g status-left '[#{host_short}] #{session_windows} ##{session_name} '\n")
        _ = h.run(["start"])
        let (web, ids) = try deskWithWindows(h, "website", 2)
        try openTab(h, "one", ["--window", ids[1], "website"])
        try wait(h) { h.clients().count == 1 && views(h, of: web).count == 1 }
        let v = try view(h, of: web, showing: ids[1])
        #expect(ownBar(h, v) == "")
        #expect(h.sessionFormat(v, "#{@macmosh-desk}") == "website")
        #expect(bar(h, v) == bar(h, web))
    }

    /// tmux changes a command-line argument that ends in ";" (seen with tmux 3.8), so such a bar can't
    /// be set as written; the view is then left with the server's bar rather than a changed one.
    @Test func aBarTmuxWouldChangeOnTheWayInIsLeftAlone() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        try writeUserTmuxConf(h, "set -g status-left '[#S] ;'\n")
        _ = h.run(["start"])
        try #require(globalBar(h) == "[#S] ;\n", "tmux read: \(globalBar(h))")
        let (web, ids) = try deskWithWindows(h, "website", 2)
        try openTab(h, "one", ["--window", ids[1], "website"])
        try wait(h) { h.clients().count == 1 && views(h, of: web).count == 1 }
        let v = try view(h, of: web, showing: ids[1])
        try wait(h) { h.sessionFormat(v, "#{destroy-unattached}") == "on" }
        #expect(ownBar(h, v) == "")
        #expect(h.sessionFormat(v, "#{@macmosh-desk}") == "website")
    }

    // MARK: - The removal rule, with such views there

    @Test func theRemovalRuleIsAsBeforeWithViewsThatHaveABar() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        try writeUserTmuxConf(h, "set -g status-left '#[bold]#S '\n")
        _ = h.run(["start"])
        let (web, webIDs) = try deskWithWindows(h, "website", 2)
        let (notes, notesIDs) = try deskWithWindows(h, "notes", 2, permanent: true)
        try openTab(h, "one", ["--window", webIDs[1], "website"])
        try openTab(h, "two", ["--label", "bbbb", "website"])
        try openTab(h, "three", ["--window", notesIDs[1], "notes"])
        try wait(h) { h.clients().count == 3 && views(h, of: web).count == 2 && views(h, of: notes).count == 1 }
        let one = try view(h, of: web, showing: webIDs[1])
        #expect(ownBar(h, one) == "#[bold]#{@macmosh-desk} \n")
        try wait(h) { h.sessionFormat(one, "#{destroy-unattached}") == "on" }

        // A tab closing removes nothing.
        try h.hangUp(clientOf: one)
        try wait(h) { views(h, of: web).count == 1 }
        try proveTheHookHasRun(h)
        #expect(defined(h, "website"))
        #expect(windowIDs(h, web) == webIDs)
        #expect(hostLog(h).contains("desk-closed\tignored: a view"))

        // The last shells exiting remove website, and notes stays because it is permanent.
        for id in webIDs + notesIDs { typeExit(h, id) }
        try wait(h) { !defined(h, "website") }
        try wait(h) { h.sessionNames().isEmpty }
        try wait(h) { hostLog(h).contains("desk-closed\tkept notes: permanent") }
        try proveTheHookHasRun(h)
        #expect(defined(h, "notes"))
        #expect(!hostLog(h).contains("desk-closed\tremoved notes"))
    }
}
}
