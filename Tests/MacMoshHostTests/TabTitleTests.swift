import Foundation
import Testing

extension HostScriptTests {
/// A terminal tab's title (issue 162, script 0.13.0): the name of the window the tab shows when that
/// window has a name of its own, and the desk's name otherwise. It follows, while the tab is open, the
/// window being named or renamed (by `window-name` and by tmux's own `rename-window`), the window going
/// back to its program's name, the desk being renamed and the tab moving to another window.
///
/// tmux writes the title itself: the script turns `set-titles` on, with a `set-titles-string` of its own,
/// on the tab's session only (a view, or the desk's own session for a tab attached to it). man tmux (3.8),
/// set-titles: "Attempt to set the client terminal title using the tsl and fsl terminfo(5) entries if they
/// exist. tmux automatically sets these to the \e]0;...\007 sequence if the terminal appears to be
/// xterm(1). This option is off by default." set-titles-string: "String used to set the client terminal
/// title if set-titles is on. Formats are expanded, see the FORMATS section." A window has a name of its
/// own exactly when its automatic-rename is off (automatic-rename: "This flag is automatically disabled
/// for an individual window when a name is specified at creation with new-window or new-session, or later
/// with rename-window, or with a terminal escape sequence.").
///
/// The clients here run in a pseudo terminal with TERM=xterm-256color, and what they are sent is recorded
/// byte for byte, so the titles checked are the ones tmux really writes. Every wait ends as soon as its
/// condition holds; the limits are long because CI runners are slow.
@Suite struct TabTitleTests {
    /// A harness whose commands run in a UTF-8 locale, as a tab opened by the app does (the Mosh
    /// connection sets one when the daily Mac has none), so names with accents come back as written.
    private func harness() throws -> HostHarness {
        let h = try HostHarness()
        h.setEnvironment("LC_ALL", "en_US.UTF-8")
        return h
    }

    private func hostLog(_ h: HostHarness) -> String {
        (try? String(contentsOf: h.home.appendingPathComponent(".macmosh/host.log"), encoding: .utf8)) ?? ""
    }

    private func wait(_ h: HostHarness, seconds: Double = 30, line: UInt = #line, _ condition: () -> Bool) throws {
        do {
            try waitFor(seconds: seconds, condition)
        } catch {
            let log = hostLog(h).split(separator: "\n").suffix(20).joined(separator: "\n")
            Issue.record(Comment(rawValue: "timed out after \(Int(seconds)) s (TabTitleTests.swift:\(line))\n"
                + "[host.log]\n\(log)\n[sessions]\n\(h.sessionNames())\n[clients]\n\(h.clients())"))
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

    private func windowIDs(_ h: HostHarness, _ sid: String) -> [String] {
        h.tmux(["list-windows", "-t", sid + ":", "-F", "#{window_id}"]).stdout.split(separator: "\n").map(String.init)
    }

    /// A desk with `count` windows, showing its first.
    private func deskWithWindows(_ h: HostHarness, _ name: String, _ count: Int) throws -> (String, [String]) {
        #expect(h.run(["desk-new", name, h.home.path]).exitCode == 0)
        let id = try sid(h, name)
        for _ in 1..<count { _ = h.tmux(["new-window", "-d", "-t", id + ":"]) }
        return (id, windowIDs(h, id))
    }

    /// The ids of a desk's views, found by MacMosh's tag, with the window each shows: `<view id>|<window>`.
    private func views(_ h: HostHarness, of deskID: String) -> [String] {
        h.tmux(["list-sessions", "-F", "#{session_id}|#{window_id}|#{@macmosh-view}"]).stdout
            .split(separator: "\n").map(String.init)
            .filter { $0.hasSuffix("|" + deskID) }
            .map { $0.split(separator: "|").prefix(2).joined(separator: "|") }
            .sorted()
    }

    private func view(_ h: HostHarness, of deskID: String, showing window: String) throws -> String {
        let line = try #require(views(h, of: deskID).first { $0.hasSuffix("|" + window) }, "no view on \(window): \(views(h, of: deskID))")
        return String(line.split(separator: "|")[0])
    }

    /// Opens a tab the way the app does, through the script's attach, recording what the tab is sent.
    private func openTab(_ h: HostHarness, _ label: String, _ arguments: [String]) throws -> URL {
        try h.startRecordedClient(label, ["/bin/bash", h.scriptURL.path, "attach"] + arguments)
    }

    /// The option set on this one session, or "" when it has none of its own.
    private func own(_ h: HostHarness, _ sessionID: String, _ option: String) -> String {
        h.tmux(["show-options", "-t", sessionID, "-v", option]).stdout
    }

    /// The title tmux makes for a client on this session: its set-titles-string, expanded for the window
    /// the session shows (`E:`, man tmux, FORMATS).
    private func title(_ h: HostHarness, _ sessionID: String) -> String? {
        h.sessionFormat(sessionID, "#{E:set-titles-string}")
    }

    /// The last title a recorded tab was sent, without its number, or nil.
    private func lastTitle(_ h: HostHarness, _ record: URL) -> String? {
        h.titles(in: record).last.map { String($0.drop(while: { $0 != ";" }).dropFirst()) }
    }

    /// Waits until both the expanded title and the last title the tab was sent are `want`.
    private func expectTitle(_ h: HostHarness, _ sessionID: String, _ record: URL, _ want: String, line: UInt = #line) throws {
        do {
            try waitFor(seconds: 30) { title(h, sessionID) == want && lastTitle(h, record) == want }
        } catch {
            Issue.record(Comment(rawValue: "TabTitleTests.swift:\(line): wanted [\(want)]; expanded [\(title(h, sessionID) ?? "nil")]; "
                + "sent \(h.titles(in: record).suffix(4))"))
            throw error
        }
        #expect(h.titles(in: record).last == "0;" + want, "TabTitleTests.swift:\(line)")
    }

    private func writeUserTmuxConf(_ h: HostHarness, _ text: String) throws {
        try text.write(to: h.home.appendingPathComponent(".tmux.conf"), atomically: true, encoding: .utf8)
    }

    // MARK: - What tmux 3.8 does

    /// The release-blocking question, answered on a throwaway socket. tmux's own rename refuses a C0
    /// control character (ESC, tab, newline) and DEL, and so does new-window -n; but it takes a C1 control
    /// character written in UTF-8 (U+009B is CSI, U+009D starts an OSC), and a title that shows such a
    /// name sends it to the terminal raw. So the title must not show a name like that. A test inside the
    /// format, `#{m/r:^[^[:cntrl:]]+$,...}`, tells every C1 control apart from ordinary text, also when
    /// the server is started with LC_ALL=C.
    @Test(arguments: ["LANG=en_US.UTF-8", "LC_ALL=C"])
    func aControlCharacterInAWindowNameReachesTheTerminalRawThroughATitle(locale: String) throws {
        let h = try harness(); defer { h.cleanUp() }
        // Only the server is started with this locale; the commands below run in a UTF-8 one, as a tab's do.
        _ = h.shell("env -u LANG -u LC_CTYPE \(locale) tmux -L \(h.socket) -f /dev/null new-session -d -s probe -x 80 -y 24")
        let probe = try sid(h, "probe")
        let name: () -> String = { h.sessionFormat(probe, "#{window_name}") ?? "" }
        _ = h.tmux(["rename-window", "-t", probe + ":", "--", "start"])
        for refused in ["a\u{1B}]0;x\u{07}b", "a\tb", "a\nb", "a\u{7F}b"] {
            #expect(h.tmux(["rename-window", "-t", probe + ":", "--", refused]).exitCode != 0, "\(refused.debugDescription)")
            #expect(name() == "start", "\(refused.debugDescription)")
        }
        #expect(h.tmux(["new-window", "-d", "-t", probe + ":", "-n", "a\u{1B}[31mb"]).exitCode != 0)

        let c1 = "x\u{9B}2J\u{9D}0;bad\u{9C}y"
        #expect(h.tmux(["rename-window", "-t", probe + ":", "--", c1]).exitCode == 0)
        #expect(name() == c1)
        _ = h.tmux(["set-option", "-t", probe, "set-titles", "on", ";", "set-option", "-t", probe, "set-titles-string", "#{window_name}"])
        let record = try h.startRecordedClient("probe", ["tmux", "-L", h.socket, "attach-session", "-t", probe])
        try wait(h) { h.titles(in: record).contains("0;" + c1) }

        // Every C1 control fails the test inside a format; ordinary text, accents included, passes it.
        let test = "^[^[:cntrl:]]+$"
        let all = (0x80...0x9F).map { "#{m/r:\(test),x\(Character(Unicode.Scalar($0)!))y}" }.joined()
        #expect(h.tmux(["display-message", "-p", "-t", probe, all]).stdout == String(repeating: "0", count: 32) + "\n")
        _ = h.tmux(["rename-window", "-t", probe + ":", "--", "café api_2.x"])
        #expect(h.tmux(["display-message", "-p", "-t", probe, "#{m/r:\(test),#{window_name}}"]).stdout == "1\n")
    }

    /// A window's name is never expanded again inside a title: a name that looks like a format or a #()
    /// command shows as it is, and the command never runs. (rename-window itself expands a format in the
    /// name it is given, so ## stands for one #.)
    @Test func aNameCannotRunAFormatOrACommandThroughTheTitle() throws {
        let h = try harness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        let (web, ids) = try deskWithWindows(h, "website", 1)
        let marker = h.home.appendingPathComponent("ran")
        let record = try openTab(h, "one", ["--label", "beef", "website"])
        try wait(h) { views(h, of: web).count == 1 && h.clients().count == 1 }
        let v = try view(h, of: web, showing: ids[0])
        try expectTitle(h, v, record, "website")

        _ = h.tmux(["rename-window", "-t", ids[0], "--", "##(touch \(marker.path))"])
        try expectTitle(h, v, record, "#(touch \(marker.path))")
        // Whatever rename-window made of the rest, the title is the name exactly as tmux keeps it.
        _ = h.tmux(["rename-window", "-t", ids[0], "--", "##{pid} %H ##[fg=red]"])
        let name = try #require(h.sessionFormat(v, "#{window_name}"))
        #expect(name.hasPrefix("#{pid} %H "), "\(name)")
        try expectTitle(h, v, record, name)
        Thread.sleep(forTimeInterval: 1)
        #expect(!FileManager.default.fileExists(atPath: marker.path))
    }

    // MARK: - Where the title is set

    @Test func theTitleIsSetOnTheTabsViewOnly() throws {
        let h = try harness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        let globalString = h.tmux(["show-options", "-gv", "set-titles-string"]).stdout
        let (web, ids) = try deskWithWindows(h, "website", 2)
        let (notes, _) = try deskWithWindows(h, "notes", 1)
        _ = try openTab(h, "one", ["--window", ids[1], "website"])
        try wait(h) { views(h, of: web).count == 1 && h.clients().count == 1 }
        let v = try view(h, of: web, showing: ids[1])

        #expect(own(h, v, "set-titles") == "on\n")
        let string = own(h, v, "set-titles-string")
        #expect(string.contains("#{window_name}") && string.contains("#{@macmosh-desk}") && string.contains("#{automatic-rename}"))
        // The string reads names through formats; no name is pasted into it.
        #expect(!string.contains("website"))
        for session in [web, notes] {
            #expect(own(h, session, "set-titles") == "", "\(session)")
            #expect(own(h, session, "set-titles-string") == "", "\(session)")
        }
        #expect(h.tmux(["show-options", "-gv", "set-titles"]).stdout == "off\n")
        #expect(h.tmux(["show-options", "-gv", "set-titles-string"]).stdout == globalString)
        #expect(!h.tmux(["show-options", "-s"]).stdout.contains("set-titles"))
        #expect(hostLog(h).contains("attach\twebsite (window \(ids[1]))"))
    }

    /// A Tabs-mode tab (attach --cc) is left exactly as before.
    @Test func aTabsModeAttachSetsNoTitle() throws {
        let h = try harness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        let (web, _) = try deskWithWindows(h, "website", 1)
        _ = try openTab(h, "cc", ["--cc", "website"])
        try wait(h) { h.clients().count == 1 }
        #expect(own(h, web, "set-titles") == "")
        #expect(own(h, web, "set-titles-string") == "")
    }

    // MARK: - The title follows

    @Test func theTitleFollowsTheWindowAndTheDesk() throws {
        let h = try harness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        let (web, ids) = try deskWithWindows(h, "website", 2)
        let record = try openTab(h, "one", ["--label", "beef", "--window", ids[0], "website"])
        try wait(h) { views(h, of: web).count == 1 && h.clients().count == 1 }
        let v = try view(h, of: web, showing: ids[0])

        // An unnamed window: the desk's name.
        try expectTitle(h, v, record, "website")
        // Named by the script, and back to its program's name.
        #expect(h.run(["window-name", "website", ids[0], "api"]).exitCode == 0)
        try expectTitle(h, v, record, "api")
        #expect(h.run(["window-name", "website", ids[0], "--auto"]).exitCode == 0)
        try expectTitle(h, v, record, "website")
        // The desk renamed.
        #expect(h.run(["desk-rename", "website", "garden"]).exitCode == 0)
        try expectTitle(h, v, record, "garden")
        // Named by tmux's own rename, with characters the script's rule would not take.
        _ = h.tmux(["rename-window", "-t", ids[0], "--", "café, logs/{x}"])
        try expectTitle(h, v, record, "café, logs/{x}")
        // The tab moves to another window, which has a name of its own.
        #expect(h.run(["window-name", "garden", ids[1], "blog"]).exitCode == 0)
        _ = h.tmux(["select-window", "-t", v + ":" + ids[1]])
        try expectTitle(h, v, record, "blog")
        // And back to the first.
        _ = h.tmux(["select-window", "-t", v + ":" + ids[0]])
        try expectTitle(h, v, record, "café, logs/{x}")
        // The tab was sent only escape 0 titles.
        #expect(h.titles(in: record).allSatisfy { $0.hasPrefix("0;") }, "\(h.titles(in: record))")
    }

    @Test func twoTabsOnOneDeskShowTheirOwnWindows() throws {
        let h = try harness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        let (web, ids) = try deskWithWindows(h, "website", 2)
        #expect(h.run(["window-name", "website", ids[1], "blog"]).exitCode == 0)
        let first = try openTab(h, "one", ["--window", ids[0], "website"])
        let second = try openTab(h, "two", ["--window", ids[1], "--label", "cafe", "website"])
        try wait(h) { views(h, of: web).count == 2 && h.clients().count == 2 }
        let one = try view(h, of: web, showing: ids[0])
        let two = try view(h, of: web, showing: ids[1])
        try expectTitle(h, one, first, "website")
        try expectTitle(h, two, second, "blog")

        #expect(h.run(["desk-rename", "website", "garden"]).exitCode == 0)
        try expectTitle(h, one, first, "garden")
        try expectTitle(h, two, second, "blog")
        #expect(h.run(["window-name", "garden", ids[1], "--auto"]).exitCode == 0)
        try expectTitle(h, two, second, "garden")
    }

    /// A window name holding a C1 control character is never shown: the title is the desk's name, and
    /// no such character reaches the tab.
    @Test func aWindowNameWithAControlCharacterShowsTheDesksName() throws {
        let h = try harness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        let (web, ids) = try deskWithWindows(h, "website", 1)
        let record = try openTab(h, "one", ["--label", "beef", "website"])
        try wait(h) { views(h, of: web).count == 1 && h.clients().count == 1 }
        let v = try view(h, of: web, showing: ids[0])
        try expectTitle(h, v, record, "website")
        _ = h.tmux(["rename-window", "-t", ids[0], "--", "x\u{9B}2J\u{9D}0;bad\u{9C}y"])
        #expect(h.sessionFormat(v, "#{automatic-rename}") == "0")
        _ = h.tmux(["rename-window", "-t", ids[0], "--", "ok"])
        try expectTitle(h, v, record, "ok")
        _ = h.tmux(["rename-window", "-t", ids[0], "--", "x\u{9B}2J\u{9D}0;bad\u{9C}y"])
        try expectTitle(h, v, record, "website")
        let sent = h.titles(in: record)
        #expect(!sent.contains { $0.unicodeScalars.contains { (0x80...0x9F).contains($0.value) } }, "\(sent)")
    }

    /// A tab attached to the desk's own session (attach with no option) gets the same rule, with the
    /// session's own name as the desk's name.
    @Test func aTabOnTheDesksOwnSessionGetsTheSameRule() throws {
        let h = try harness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        let (web, _) = try deskWithWindows(h, "website", 2)
        let record = try openTab(h, "plain", ["website"])
        try wait(h) { h.clients().contains { $0.hasPrefix(web + "|website|") } }
        #expect(views(h, of: web).isEmpty)
        #expect(own(h, web, "set-titles") == "on\n")
        try expectTitle(h, web, record, "website")
        let shown = try #require(h.currentWindow(web))
        #expect(h.run(["window-name", "website", shown, "api"]).exitCode == 0)
        try expectTitle(h, web, record, "api")
        #expect(h.run(["desk-rename", "website", "garden"]).exitCode == 0)
        try expectTitle(h, web, record, "api")
        #expect(h.run(["window-name", "garden", shown, "--auto"]).exitCode == 0)
        try expectTitle(h, web, record, "garden")
    }

    /// A desk named "0". A conditional in a format takes "0" as false (man tmux, FORMATS: "if the
    /// variable in the first of the pair exists and is not zero, the second of the pair is chosen"), so
    /// the desk's name is chosen by being empty or not, and a view shows "0", not its own session's name.
    @Test func aDeskNamedZeroShowsItsName() throws {
        let h = try harness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        let (zero, ids) = try deskWithWindows(h, "0", 1)
        let record = try openTab(h, "one", ["--label", "beef", "0"])
        try wait(h) { views(h, of: zero).count == 1 && h.clients().count == 1 }
        let v = try view(h, of: zero, showing: ids[0])
        try expectTitle(h, v, record, "0")
        let plain = try openTab(h, "plain", ["0"])
        try wait(h) { h.clients().count == 2 }
        try expectTitle(h, zero, plain, "0")
    }

    // MARK: - When MacMosh sets nothing

    /// A person who turned set-titles on in his own tmux settings keeps his own title.
    @Test func aPersonsOwnSetTitlesIsLeftAlone() throws {
        let h = try harness(); defer { h.cleanUp() }
        try writeUserTmuxConf(h, "set -g set-titles on\nset -g set-titles-string 'mine #S'\n")
        _ = h.run(["start"])
        let (web, ids) = try deskWithWindows(h, "website", 1)
        let record = try openTab(h, "one", ["--label", "beef", "website"])
        _ = try openTab(h, "plain", ["website"])
        try wait(h) { views(h, of: web).count == 1 && h.clients().count == 2 }
        let v = try view(h, of: web, showing: ids[0])
        for session in [v, web] {
            #expect(own(h, session, "set-titles") == "", "\(session)")
            #expect(own(h, session, "set-titles-string") == "", "\(session)")
        }
        try wait(h) { lastTitle(h, record)?.hasPrefix("mine website+") == true }
    }

    /// A person who turns set-titles on later (his settings reloaded, the server kept) gets his own title
    /// on the desk's own session too, although an earlier plain attach gave it MacMosh's.
    @Test func aPersonsLaterSetTitlesTakesOffAnEarlierTitle() throws {
        let h = try harness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        let (web, _) = try deskWithWindows(h, "website", 1)
        _ = try openTab(h, "plain", ["website"])
        try wait(h) { h.clients().count == 1 }
        #expect(own(h, web, "set-titles") == "on\n")
        _ = h.tmux(["set-option", "-g", "set-titles", "on"])
        _ = try openTab(h, "again", ["website"])
        try wait(h) { h.clients().count == 2 }
        try wait(h) { own(h, web, "set-titles") == "" && own(h, web, "set-titles-string") == "" }
    }

    /// tmux stand-ins that make the title fail on its way in: one changes the string set-option is given,
    /// the other makes the server's answer to the control-character test wrong. Either way the tab opens
    /// as before, with no title options of its own.
    @Test(arguments: ["mangle", "probe"])
    func aTitleThatDidNotComeThroughIsTakenOff(mode: String) throws {
        let h = try harness(); defer { h.cleanUp() }
        let real = h.shell("command -v tmux").stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        try #require(real.hasPrefix("/"), "no tmux: \(real)")
        try h.stub("tmux", script: """
            out=()
            prev=""
            for a in "$@"; do
                if [ "\(mode)" = mangle ] && [ "$prev" = set-titles-string ]; then a="$a x"; fi
                out+=("$a")
                prev="$a"
            done
            if [ "\(mode)" = probe ]; then
                case "$*" in *display-message*m/r:*) echo 11; exit 0 ;; esac
            fi
            exec '\(real)' "${out[@]}"
            """)
        _ = h.run(["start"])
        let (web, ids) = try deskWithWindows(h, "website", 1)
        _ = try openTab(h, "one", ["--label", "beef", "website"])
        _ = try openTab(h, "plain", ["website"])
        try wait(h) { views(h, of: web).count == 1 && h.clients().count == 2 }
        let v = try view(h, of: web, showing: ids[0])
        try wait(h) { h.sessionFormat(v, "#{destroy-unattached}") == "on" }
        for session in [v, web] {
            #expect(own(h, session, "set-titles") == "", "\(session)")
            #expect(own(h, session, "set-titles-string") == "", "\(session)")
        }
    }

    /// A view made before 0.13.0 has no title of its own, and nothing gives it one: a rename and a window
    /// name change only what they changed before.
    @Test func aTabOpenedBeforeTheUpdateIsLeftAsItWas() throws {
        let h = try harness(); defer { h.cleanUp() }
        _ = h.run(["start"])
        let (web, ids) = try deskWithWindows(h, "website", 1)
        let old = try #require(h.tmux(["new-session", "-d", "-t", web, "-s", "website+1", "-P", "-F", "#{session_id}"]).stdout
            .split(separator: "\n").first.map(String.init))
        _ = h.tmux(["set-option", "-t", old, "@macmosh-view", web, ";", "set-option", "-t", old, "@macmosh-desk", "website"])
        #expect(h.run(["window-name", "website", ids[0], "api"]).exitCode == 0)
        #expect(h.run(["desk-rename", "website", "garden"]).exitCode == 0)
        #expect(h.sessionFormat(old, "#{@macmosh-desk}") == "garden")
        for session in [old, web] {
            #expect(own(h, session, "set-titles") == "", "\(session)")
            #expect(own(h, session, "set-titles-string") == "", "\(session)")
        }
    }
}
}
