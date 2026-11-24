import Foundation
import Testing

extension HostScriptTests {
/// What tmux 3.8 runs when the window that a session of a group shows closes, which the rule that ends
/// a view with its window relies on (issue 139). The sessions and the hooks are made by hand on the
/// throwaway socket, as `SessionGroupTests` does, so these tests pin tmux itself, not the script.
///
/// man tmux (3.8), HOOKS, says what each hook is for and nothing about when one runs for which session:
/// - "session-window-changed  Run when a session changes its active window."
/// - "window-unlinked  Run when a window is unlinked from a session."
/// - "window-linked  Run when a window is linked into a session."
/// - "pane-exited  Run when the program running in a pane exits."
/// - "window-closed  Run when a window is closed."
/// - "Hooks are stored as array options ... Like options different hooks may be global or belong to a
///   session, window or pane."
/// and FORMATS: "hook_session  ID of session where hook was run, if any", "hook_window  ID of window
/// where hook was run, if any". Everything else here is what tmux 3.8 was seen to do.
///
/// Every wait ends as soon as its condition holds. The limits are long because CI runners are slow.
@Suite struct WindowCloseHookTests {
    /// A desk's session as the script makes one, in a group of its own, showing its first window.
    private func makeDesk(_ h: HostHarness, _ name: String, windows: Int) throws -> String {
        let next = h.tmux(["display-message", "-p", "#{next_session_id}"]).stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let made = h.tmux(["new-session", "-d", "-P", "-F", "#{session_id}", "-s", name,
                           "-t", "macmosh+g" + next.dropFirst(), "-c", h.home.path])
        let sid = made.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        try #require(made.exitCode == 0 && sid.hasPrefix("$"), "no desk \(name): \(made)")
        for _ in 1..<max(windows, 1) { _ = h.tmux(["new-window", "-d", "-t", sid + ":"]) }
        _ = h.tmux(["select-window", "-t", sid + ":0"])
        return sid
    }

    /// A view joined through the desk's session id, showing one window.
    private func makeView(_ h: HostHarness, desk sid: String, _ name: String, on window: String) throws -> String {
        let made = h.tmux(["new-session", "-d", "-t", sid, "-s", name, "-P", "-F", "#{session_id}"])
        let vid = made.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        try #require(made.exitCode == 0 && vid.hasPrefix("$"), "no view \(name): \(made)")
        #expect(h.tmux(["select-window", "-t", vid + ":" + window]).exitCode == 0)
        return vid
    }

    private func windowIDs(_ h: HostHarness, _ sid: String) -> [String] {
        h.tmux(["list-windows", "-t", sid + ":", "-F", "#{window_id}"]).stdout.split(separator: "\n").map(String.init)
    }

    private var logName: String { "hooks.log" }

    // A window loop (#{W:#{window_id} }) leaves a space after each window, the last one too.

    private func log(_ h: HostHarness) -> [String] {
        ((try? String(contentsOf: h.home.appendingPathComponent(logName), encoding: .utf8)) ?? "")
            .split(separator: "\n").map(String.init)
    }

    private func clearLog(_ h: HostHarness) {
        try? "".write(to: h.home.appendingPathComponent(logName), atomically: true, encoding: .utf8)
    }

    /// pane-exited and window-closed belong to no session (hook_session is empty for them), so they are
    /// set globally. The others are set on each session given, and run-shell -t names that session, so
    /// each line reads the session's own state: `<hook> hs=<hook_session> sid=<session the formats read>
    /// hw=<hook_window> cur=<its current window> wins=<its windows>`.
    private func logHooks(_ h: HostHarness, sessions: [String]) {
        let path = h.home.appendingPathComponent(logName).path
        for hook in ["pane-exited", "window-closed"] {
            _ = h.tmux(["set-hook", "-g", hook + "[5]", "run-shell \"echo '\(hook) hw=#{hook_window}' >> '\(path)'\""])
        }
        for sid in sessions {
            for hook in ["session-window-changed", "window-unlinked", "window-linked"] {
                let line = "\(hook) hs=#{hook_session} sid=#{session_id} hw=#{hook_window} cur=#{window_id} wins=#{W:#{window_id} }"
                _ = h.tmux(["set-hook", "-t", sid, hook + "[5]", "run-shell -t '\(sid)' \"echo '\(line)' >> '\(path)'\""])
            }
        }
    }

    /// The lines of one hook for one session.
    private func lines(_ all: [String], _ hook: String, _ sid: String) -> [String] {
        all.filter { $0.hasPrefix(hook + " hs=" + sid + " ") }
    }

    private func field(_ line: String, _ name: String) -> String {
        guard let range = line.range(of: " " + name + "=") else { return "" }
        let rest = line[range.upperBound...]
        if name == "wins" { return rest.trimmingCharacters(in: .whitespaces) }
        return String(rest.prefix { $0 != " " })
    }

    // MARK: 1. A window closes

    /// The window two views show closes, by its shell exiting and then by kill-window. Each session
    /// that showed it gets one session-window-changed, read from that session: the hook's window is its
    /// new current window, and the closed one is already gone from its windows. A session that showed
    /// another window gets none. Every session gets window-unlinked for the closed window.
    @Test func eachSessionThatShowedAClosedWindowGetsSessionWindowChanged() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        let desk = try makeDesk(h, "website", windows: 4)
        let ids = windowIDs(h, desk)
        let one = try makeView(h, desk: desk, "website+1", on: ids[1])
        let two = try makeView(h, desk: desk, "website+2", on: ids[1])
        let three = try makeView(h, desk: desk, "website+3", on: ids[2])
        let all = [desk, one, two, three]
        logHooks(h, sessions: all)
        clearLog(h)

        // The shell in ids[1] exits.
        _ = h.tmux(["send-keys", "-t", ids[1], "-l", "--", "exit"])
        _ = h.tmux(["send-keys", "-t", ids[1], "Enter"])
        try waitFor(seconds: 30) { log(h).contains { $0.hasPrefix("window-closed") } }
        var seen = log(h)
        #expect(seen.first == "pane-exited hw=\(ids[1])", "\(seen)")
        #expect(seen.last == "window-closed hw=\(ids[1])", "\(seen)")
        for line in seen where line.contains(" hs=") {
            #expect(field(line, "hs") == field(line, "sid"), "the formats read another session: \(line)")
        }
        for vid in [one, two] {
            let changed = lines(seen, "session-window-changed", vid)
            #expect(changed.count == 1, "\(vid): \(seen)")
            let line = try #require(changed.first)
            #expect(field(line, "hw") == field(line, "cur"))
            #expect(field(line, "hw") != ids[1])
            #expect(field(line, "wins") == [ids[0], ids[2], ids[3]].joined(separator: " "))
            // Its window-unlinked comes after it.
            let unlinked = try #require(seen.firstIndex { $0.hasPrefix("window-unlinked hs=\(vid) ") && $0.contains(" hw=\(ids[1]) ") })
            #expect(try #require(seen.firstIndex(of: line)) < unlinked)
        }
        for sid in [desk, three] {
            #expect(lines(seen, "session-window-changed", sid).isEmpty, "\(sid): \(seen)")
        }
        for sid in all {
            let unlinked = lines(seen, "window-unlinked", sid).filter { field($0, "hw") == ids[1] }
            #expect(unlinked.count == 1, "\(sid): \(seen)")
            #expect(!field(unlinked.first ?? "", "wins").contains(ids[1]))
        }
        #expect(h.currentWindow(three) == ids[2])
        #expect(h.currentWindow(desk) == ids[0])

        // kill-window on the window the third view shows: no pane-exited, and the same for that view.
        clearLog(h)
        #expect(h.tmux(["kill-window", "-t", ids[2]]).exitCode == 0)
        try waitFor(seconds: 30) { log(h).contains { $0.hasPrefix("window-closed") } }
        seen = log(h)
        #expect(!seen.contains { $0.hasPrefix("pane-exited") }, "\(seen)")
        #expect(seen.last == "window-closed hw=\(ids[2])", "\(seen)")
        let changed = lines(seen, "session-window-changed", three)
        #expect(changed.count == 1, "\(seen)")
        #expect(field(changed.first ?? "", "hw") == field(changed.first ?? "", "cur"))
        #expect(field(changed.first ?? "", "wins") == [ids[0], ids[3]].joined(separator: " "))
        for sid in [desk, one, two] {
            #expect(lines(seen, "session-window-changed", sid).isEmpty, "\(sid): \(seen)")
        }
    }

    // MARK: 2. The person switches windows

    /// select-window and next-window in one session run session-window-changed for that session only;
    /// the window it left is still one of its windows, and nothing is unlinked.
    @Test func switchingWindowsRunsSessionWindowChangedForThatSessionOnly() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        let desk = try makeDesk(h, "website", windows: 3)
        let ids = windowIDs(h, desk)
        let one = try makeView(h, desk: desk, "website+1", on: ids[0])
        let two = try makeView(h, desk: desk, "website+2", on: ids[0])
        logHooks(h, sessions: [desk, one, two])
        clearLog(h)

        #expect(h.tmux(["select-window", "-t", one + ":" + ids[2]]).exitCode == 0)
        try waitFor(seconds: 30) { !log(h).isEmpty }
        Thread.sleep(forTimeInterval: 0.5)
        var seen = log(h)
        #expect(seen.count == 1, "\(seen)")
        #expect(seen.first == "session-window-changed hs=\(one) sid=\(one) hw=\(ids[2]) cur=\(ids[2]) wins=\(ids.joined(separator: " ")) ", "\(seen)")

        clearLog(h)
        #expect(h.tmux(["next-window", "-t", one]).exitCode == 0)
        try waitFor(seconds: 30) { !log(h).isEmpty }
        Thread.sleep(forTimeInterval: 0.5)
        seen = log(h)
        #expect(seen == ["session-window-changed hs=\(one) sid=\(one) hw=\(ids[0]) cur=\(ids[0]) wins=\(ids.joined(separator: " ")) "], "\(seen)")
        #expect(h.currentWindow(two) == ids[0])
        #expect(h.currentWindow(desk) == ids[0])
    }

    // MARK: 3. The last window

    /// When the group's last window closes, every session closes and none gets session-window-changed.
    @Test func whenTheLastWindowClosesNoSessionGetsSessionWindowChanged() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        let desk = try makeDesk(h, "website", windows: 1)
        let ids = windowIDs(h, desk)
        let one = try makeView(h, desk: desk, "website+1", on: ids[0])
        let two = try makeView(h, desk: desk, "website+2", on: ids[0])
        logHooks(h, sessions: [desk, one, two])
        clearLog(h)
        _ = h.tmux(["send-keys", "-t", ids[0], "-l", "--", "exit"])
        _ = h.tmux(["send-keys", "-t", ids[0], "Enter"])
        try waitFor(seconds: 30) { h.sessionNames().isEmpty }
        Thread.sleep(forTimeInterval: 0.5)
        #expect(!log(h).contains { $0.hasPrefix("session-window-changed") }, "\(log(h))")
    }

    // MARK: 4. A session's own hook

    /// A hook set on one session takes the place of the global hook of the same name for that session:
    /// tmux reads the session's own array and doesn't add the global one's members. Other sessions
    /// still run the global one.
    @Test func aSessionsOwnHookTakesThePlaceOfTheGlobalOne() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        let desk = try makeDesk(h, "website", windows: 2)
        let ids = windowIDs(h, desk)
        let one = try makeView(h, desk: desk, "website+1", on: ids[0])
        let two = try makeView(h, desk: desk, "website+2", on: ids[0])
        let path = h.home.appendingPathComponent(logName).path
        _ = h.tmux(["set-hook", "-g", "session-window-changed[0]", "run-shell \"echo 'global #{hook_session}' >> '\(path)'\""])
        _ = h.tmux(["set-hook", "-t", one, "session-window-changed[1089]", "run-shell \"echo 'own #{hook_session}' >> '\(path)'\""])
        clearLog(h)
        _ = h.tmux(["select-window", "-t", one + ":" + ids[1]])
        _ = h.tmux(["select-window", "-t", two + ":" + ids[1]])
        try waitFor(seconds: 30) { log(h).count >= 2 }
        Thread.sleep(forTimeInterval: 0.5)
        #expect(log(h).sorted() == ["global \(two)", "own \(one)"], "\(log(h))")
    }

    // MARK: 5. Formats

    /// The formats a hook can decide with, read for a session named by its id (as if-shell -F -t and
    /// set-option -F -t read them): a user option of the session inside a window loop, the group's
    /// size, and the operators !, && and e|>.
    @Test func theFormatsAViewsHookCanDecideWith() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        let desk = try makeDesk(h, "website", windows: 2)
        let ids = windowIDs(h, desk)
        let one = try makeView(h, desk: desk, "website+1", on: ids[1])
        let read = { (sid: String, format: String) in
            h.tmux(["display-message", "-p", "-t", sid, format]).stdout.trimmingCharacters(in: .newlines)
        }
        let has = "#{W:#{?#{==:#{window_id},#{@w}},1,}}"
        _ = h.tmux(["set-option", "-t", one, "@w", ids[1]])
        #expect(read(one, has) == "1")
        #expect(read(one, "#{!:\(has)}") == "0")
        _ = h.tmux(["set-option", "-t", one, "@w", "@999"])
        #expect(read(one, has) == "")
        #expect(read(one, "#{!:\(has)}") == "1")
        // The option is the session's own: the desk has none.
        #expect(read(desk, "#{@w}") == "")
        #expect(read(one, "#{e|>:#{session_group_size},1}") == "1")
        #expect(read(one, "#{&&:#{@w},#{e|>:#{session_group_size},1}}") == "1")
        #expect(read(one, "#{&&:#{@none},1}") == "0")
        // -F on set-option expands for the session it names.
        _ = h.tmux(["set-option", "-F", "-t", one, "@w", "#{window_id}"])
        #expect(read(one, "#{@w}") == ids[1])
        #expect(h.tmux(["kill-session", "-t", desk]).exitCode == 0)
        #expect(read(one, "#{e|>:#{session_group_size},1}") == "0")
    }
}
}
