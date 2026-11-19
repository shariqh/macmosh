import Foundation
import Testing

@Suite(.serialized) struct StatusReportTests {
    @Test func reportStartsWithTheHeaderAndEndsWithEnd() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        let lines = h.run(["status"]).stdout.split(separator: "\n").map(String.init)
        #expect(lines.first == "macmosh-host\t1\t" + h.scriptVersion)
        #expect(lines.last == "end")
    }

    @Test func serverIsDownBeforeStart() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        let out = h.run(["status"]).stdout
        #expect(out.contains("\nserver\tdown\n"))
        #expect(out.contains("\nsignins\tunknown\n"))
    }

    @Test func startKeepsAServerWithNoDesks() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        #expect(h.run(["start"]).exitCode == 0)
        #expect(h.tmux(["list-sessions"]).exitCode == 0)
        #expect(h.run(["status"]).stdout.contains("\nserver\tup\n"))
    }

    @Test func signInsFollowTheKeychainCheck() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        try h.stub("security", script: "exit 0")
        #expect(h.run(["start"]).exitCode == 0)
        #expect(h.run(["status"]).stdout.contains("\nsignins\tok\n"))
        try h.stub("security", script: "exit 36")
        #expect(h.run(["status"]).stdout.contains("\nsignins\toff\n"))
    }

    @Test func powerComesFromTheACSection() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        try h.stub("pmset", script: """
            if [ "$1 $2" = "-g custom" ]; then
            cat <<'OUT'
            Battery Power:
             lowpowermode         0
             sleep                1
             womp                 0
            AC Power:
             lowpowermode         0
             sleep                0
             womp                 1
            OUT
            fi
            """)
        #expect(h.run(["status"]).stdout
            .contains("\npower\tsleep=0\twomp=1\tautorestart=-\tdisablesleep=-\n"))
    }

    @Test func batteryOnALaptop() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        try h.stub("pmset", script: """
            if [ "$1 $2" = "-g batt" ]; then
            printf "Now drawing from 'AC Power'\\n"
            printf " -InternalBattery-0 (id=1234567)\\t76%%; AC attached; not charging present: true\\n"
            fi
            """)
        #expect(h.run(["status"]).stdout.contains("\nbattery\tpresent\tac\t76\n"))
    }

    @Test func batteryOnADesktop() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        try h.stub("pmset", script: """
            if [ "$1 $2" = "-g batt" ]; then
            printf "Now drawing from 'AC Power'\\n"
            fi
            """)
        #expect(h.run(["status"]).stdout.contains("\nbattery\tabsent\tac\t-\n"))
    }

    @Test func rootAtTheConsoleMeansNobody() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        try h.stub("stat", script: "echo root")
        #expect(h.run(["status"]).stdout.contains("\nconsole\t\n"))
        try h.stub("stat", script: "echo alex")
        #expect(h.run(["status"]).stdout.contains("\nconsole\talex\n"))
    }

    @Test func fileVaultAndAuthRestart() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        try h.stub("fdesetup", script: """
            case "$1" in
              status) echo "FileVault is On." ;;
              supportsauthrestart) echo true ;;
            esac
            """)
        let out = h.run(["status"]).stdout
        #expect(out.contains("\nfilevault\ton\n"))
        #expect(out.contains("\nauthrestart\tyes\n"))
    }

    @Test func homeLine() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        try h.stub("route", script: "printf '   route to: default\\n  interface: en0\\n'")
        try h.stub("ipconfig", script: """
            case "$1 $2 $3" in
              "getifaddr en0 ") echo 192.168.1.20 ;;
              "getoption en0 subnet_mask") echo 255.255.255.0 ;;
              *) exit 1 ;;
            esac
            """)
        try h.stub("scutil", script: "echo workhorse")
        #expect(h.run(["status"]).stdout.contains("\nhome\t192.168.1.20\t24\tworkhorse.local\n"))
    }

    @Test func homeIsNeverTheTailscaleAddress() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        try h.stub("route", script: "printf '  interface: utun4\\n'")
        try h.stub("ipconfig", script: """
            case "$1 $2 $3" in
              "getifaddr utun4 ") echo 100.101.102.103 ;;
              "getifaddr en0 ") echo 192.168.1.20 ;;
              "getoption en0 subnet_mask") echo 255.255.255.0 ;;
              *) exit 1 ;;
            esac
            """)
        try h.stub("scutil", script: "echo workhorse")
        #expect(h.run(["status"]).stdout.contains("\nhome\t192.168.1.20\t24\tworkhorse.local\n"))

        // The same when the route names a normal interface that happens to hold a Tailscale address.
        try h.stub("route", script: "printf '  interface: en5\\n'")
        try h.stub("ipconfig", script: """
            case "$1 $2 $3" in
              "getifaddr en5 ") echo 100.64.0.9 ;;
              "getifaddr en0 ") echo 192.168.1.20 ;;
              "getoption en0 subnet_mask") echo 255.255.255.0 ;;
              *) exit 1 ;;
            esac
            """)
        #expect(h.run(["status"]).stdout.contains("\nhome\t192.168.1.20\t24\tworkhorse.local\n"))
    }

    @Test func aFixedAddressStillGivesAPrefixLength() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        try h.stub("route", script: "printf '  interface: en0\\n'")
        try h.stub("ipconfig", script: """
            case "$1 $2 $3" in
              "getifaddr en0 ") echo 10.0.4.7 ;;
              *) exit 1 ;;
            esac
            """)
        try h.stub("ifconfig", script: "printf '\\tinet 10.0.4.7 netmask 0xfffff800 broadcast 10.0.7.255\\n'")
        try h.stub("scutil", script: "echo workhorse")
        #expect(h.run(["status"]).stdout.contains("\nhome\t10.0.4.7\t21\tworkhorse.local\n"))
    }

    @Test func firewallFollowsSocketFilterFirewall() throws {
        // The script calls the tool by its full path, so only the text it prints can be checked here:
        // the real tool is read-only. The mapping itself is checked on whatever the Mac prints.
        let h = try HostHarness(); defer { h.cleanUp() }
        let out = h.run(["status"]).stdout
        let line = out.split(separator: "\n").first { $0.hasPrefix("firewall\t") }
        #expect(["firewall\ton", "firewall\toff", "firewall\tunknown"].contains(line.map(String.init) ?? ""))
    }

    @Test func screenSharingFollowsLaunchctl() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        try h.stub("launchctl", script: #"echo '\#t"com.apple.screensharing" => enabled'"#)
        #expect(h.run(["status"]).stdout.contains("\nscreensharing\ton\n"))
        try h.stub("launchctl", script: #"echo '\#t"com.apple.screensharing" => disabled'"#)
        #expect(h.run(["status"]).stdout.contains("\nscreensharing\toff\n"))
        // The default stand-in prints nothing and exits 1.
        let fresh = try HostHarness(); defer { fresh.cleanUp() }
        #expect(fresh.run(["status"]).stdout.contains("\nscreensharing\tunknown\n"))
    }

    @Test func aNewHarnessHidesTheRealLaunchctl() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        let found = h.shell("command -v launchctl").stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(found.hasPrefix(h.stubFolder.path))
        let stat = h.shell("command -v stat").stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(stat.hasPrefix(h.stubFolder.path))
        // A status check reaches the stand-in, which keeps a log.
        _ = h.run(["status"])
        let log = try String(contentsOf: h.home.appendingPathComponent("launchctl.log"), encoding: .utf8)
        #expect(log.contains("print-disabled system"))
    }

    @Test func yourOwnTmuxSettingsWin() throws {
        // Without the file: the defaults.
        do {
            let h = try HostHarness(); defer { h.cleanUp() }
            #expect(h.run(["start"]).exitCode == 0)
            #expect(h.tmux(["show-options", "-gv", "history-limit"]).stdout
                .trimmingCharacters(in: .whitespacesAndNewlines) == "50000")
            #expect(h.tmux(["show-options", "-gv", "mouse"]).stdout
                .trimmingCharacters(in: .whitespacesAndNewlines) == "on")
        }
        // ~/.tmux.conf.
        do {
            let h = try HostHarness(); defer { h.cleanUp() }
            try "set -g history-limit 1234\n".write(to: h.home.appendingPathComponent(".tmux.conf"),
                                                    atomically: true, encoding: .utf8)
            #expect(h.run(["start"]).exitCode == 0)
            #expect(h.tmux(["show-options", "-gv", "history-limit"]).stdout
                .trimmingCharacters(in: .whitespacesAndNewlines) == "1234")
        }
        // ~/.config/tmux/tmux.conf.
        do {
            let h = try HostHarness(); defer { h.cleanUp() }
            let folder = h.home.appendingPathComponent(".config/tmux")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try "set -g history-limit 1234\n".write(to: folder.appendingPathComponent("tmux.conf"),
                                                    atomically: true, encoding: .utf8)
            #expect(h.run(["start"]).exitCode == 0)
            #expect(h.tmux(["show-options", "-gv", "history-limit"]).stdout
                .trimmingCharacters(in: .whitespacesAndNewlines) == "1234")
        }
    }

    @Test func theWrittenTmuxConfHasTheDocumentedLines() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        #expect(h.run(["start"]).exitCode == 0)
        let conf = try String(contentsOf: h.home.appendingPathComponent(".macmosh/tmux.conf"), encoding: .utf8)
        let expected = """
            # MacMosh defaults. Your own tmux settings are loaded next, so your settings win.
            set -g mouse on
            set -g history-limit 50000
            source-file -q "\(h.home.path)/.config/tmux/tmux.conf"
            set -s exit-empty off

            """
        #expect(conf == expected)
    }

    @Test func startTwiceLeavesTheServerAlone() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        #expect(h.run(["start"]).exitCode == 0)
        _ = h.tmux(["new-session", "-d", "-s", "keepme"])
        #expect(h.run(["start"]).exitCode == 0)
        #expect(h.tmux(["has-session", "-t", "=keepme"]).exitCode == 0)
    }

    @Test func desksAndTheirWindowsAreListed() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        #expect(h.run(["start"]).exitCode == 0)
        _ = h.tmux(["new-session", "-d", "-s", "website", "-n", "zsh"])
        _ = h.tmux(["new-window", "-t", "=website:", "-n", "vim"])
        let out = h.run(["status"]).stdout
        #expect(out.contains("\ndesk\twebsite\t2\t0\nwindow\twebsite\t0\tzsh\nwindow\twebsite\t1\tvim\n"))
    }

    @Test func aSessionWithABadNameIsLeftOut() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        #expect(h.run(["start"]).exitCode == 0)
        _ = h.tmux(["new-session", "-d", "-s", "has space"])
        _ = h.tmux(["new-session", "-d", "-s", "good_name-1"])
        let out = h.run(["status"]).stdout
        #expect(out.contains("\ndesk\tgood_name-1\t1\t0\n"))
        #expect(!out.contains("has space"))
    }

    @Test func definitionsComeFromDesksTsv() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        let folder = h.home.appendingPathComponent(".macmosh")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "website\t1\t0\t/Users/alex/Development/website\tnpm run dev\nplain\t0\t1\t/Users/alex\t\n"
            .write(to: folder.appendingPathComponent("desks.tsv"), atomically: true, encoding: .utf8)
        let out = h.run(["status"]).stdout
        #expect(out.contains("\ndef\twebsite\t1\t0\t/Users/alex/Development/website\tnpm run dev\n"))
        #expect(out.contains("\ndef\tplain\t0\t1\t/Users/alex\t\n"))
    }

    @Test func definitionsWithABadNameAreLeftOut() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        let folder = h.home.appendingPathComponent(".macmosh")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "bad name\t0\t0\t/tmp\t\ngood\t0\t0\t/tmp\t\n"
            .write(to: folder.appendingPathComponent("desks.tsv"), atomically: true, encoding: .utf8)
        let out = h.run(["status"]).stdout
        #expect(out.contains("\ndef\tgood\t"))
        #expect(!out.contains("bad name"))
    }

    @Test func aLongLogIsCutBack() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        let folder = h.home.appendingPathComponent(".macmosh")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let line = "2026-01-01T00:00:00+0000\tstatus\tok\n"
        try String(repeating: line, count: 40_000)
            .write(to: folder.appendingPathComponent("host.log"), atomically: true, encoding: .utf8)
        #expect(h.run(["version"]).exitCode == 0)
        let log = try String(contentsOf: folder.appendingPathComponent("host.log"), encoding: .utf8)
        #expect(log.split(separator: "\n").count <= 2001)
        #expect(log.contains("\tversion\t"))
    }

    @Test func toolsAreReported() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        try h.stub("brew", script: "exit 0")
        try h.stub("mosh-server", script: "echo 'mosh-server (mosh 1.4.0) [build mosh 1.4.0]' >&2")
        let out = h.run(["status"]).stdout
        let stubs = h.stubFolder.path
        #expect(out.contains("\ntool\tbrew\t\(stubs)/brew\t-\n"))
        #expect(out.contains("\ntool\tmosh-server\t\(stubs)/mosh-server\t1.4.0\n"))
        #expect(out.contains("\ntool\ttmux\t/"))
    }

    @Test func agentIsMissingUntilItsFileExists() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        #expect(h.run(["status"]).stdout.contains("\nagent\tmissing\n"))
        let folder = h.home.appendingPathComponent("Library/LaunchAgents")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "x".write(to: folder.appendingPathComponent("io.github.shariqh.macmosh.host.plist"),
                      atomically: true, encoding: .utf8)
        #expect(h.run(["status"]).stdout.contains("\nagent\tinstalled\n"))
    }

    @Test func versionAndUsage() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        let version = h.run(["version"])
        #expect(version.exitCode == 0)
        #expect(version.stdout == h.scriptVersion + "\n")
        #expect(version.stdout == "0.1.0\n")
        #expect(h.run([]).exitCode == 2)
        #expect(h.run(["nonsense"]).exitCode == 2)
    }

    @Test func everyTmuxCallNamesTheSocket() throws {
        let text = try String(contentsOf: HostHarness.repoRoot().appendingPathComponent("host/macmosh-host"),
                              encoding: .utf8)
        let allowed = [
            #"command tmux -L "$MACMOSH_SOCKET""#,
            #"exec tmux -L "$MACMOSH_SOCKET""#,
            "command -v tmux",
            "tmux -V",
            "mm_tool_record tmux ",       // the name of a report line, not a command
            "Your own tmux settings",     // the comment line written into tmux.conf
        ]
        let word = try Regex(#"(^|[^A-Za-z0-9_./-])tmux($|[^A-Za-z0-9_.-])"#)
        var offenders: [String] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") { continue }
            var rest = String(line)
            for pattern in allowed { rest = rest.replacingOccurrences(of: pattern, with: "") }
            if rest.contains(word) { offenders.append(String(line)) }
        }
        #expect(offenders.isEmpty, "tmux run outside the allowed forms: \(offenders)")
        #expect(text.contains("mm_tmux() { command tmux -L \"$MACMOSH_SOCKET\" \"$@\"; }"))
        // The two lines that hand the terminal over are the only `exec tmux` in the script.
        #expect(text.components(separatedBy: #"exec tmux -L "$MACMOSH_SOCKET""#).count - 1 == 2)
        // Only `start` starts the desk server, so tmux's start-server appears once, inside `cmd_start`.
        // (The subcommand `restart-server` ends in the same letters, so it is not counted.)
        let startServer = try Regex(#"(^|[^A-Za-z0-9_-])start-server"#)
        #expect(text.matches(of: startServer).count == 1)
        let startBody = try #require(text.components(separatedBy: "cmd_start() {\n").last?
            .components(separatedBy: "\n}\n").first)
        #expect(startBody.contains(startServer))
    }

    @Test func startWritesALogLine() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        #expect(h.run(["start"]).exitCode == 0)
        let log = try String(contentsOf: h.home.appendingPathComponent(".macmosh/host.log"), encoding: .utf8)
        #expect(log.contains("start"))
    }

    @Test func theHarnessKeepsTheRealTmuxOut() throws {
        // The harness builds its own socket name and drops the tmux variables; this checks both.
        let h = try HostHarness(); defer { h.cleanUp() }
        #expect(h.socket.hasPrefix("macmosh-test-"))
        #expect(h.socket != "macmosh")
        #expect(h.shell("echo \"${TMUX-unset}${TMUX_PANE-unset}\"").stdout == "unsetunset\n")
    }
}
