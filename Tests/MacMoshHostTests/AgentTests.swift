import Foundation
import Testing

extension HostScriptTests {
@Suite struct AgentTests {
    private let agentLabel = "io.github.shariqh.macmosh.host"

    private func plistURL(_ h: HostHarness) -> URL {
        h.home.appendingPathComponent("Library/LaunchAgents/\(agentLabel).plist")
    }

    private func launchctlLog(_ h: HostHarness) -> [String] {
        let text = (try? String(contentsOf: h.home.appendingPathComponent("launchctl.log"), encoding: .utf8)) ?? ""
        return text.split(separator: "\n").map(String.init)
    }

    private func succeedingLaunchctl(_ h: HostHarness) throws {
        try h.stub("launchctl", script: """
            echo "$*" >> "$HOME/launchctl.log"
            exit 0
            """)
    }

    // Three made-up keys, each 68 characters of base64 as a real ed25519 key would be.
    private let keys = [
        "AAAAC3NzaC1lZDI1NTE5AAAAIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAC3NzaC1lZDI1NTE5AAAAIBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB",
        "AAAAC3NzaC1lZDI1NTE5AAAAICCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC",
    ]

    private func writeAuthorizedKeys(_ h: HostHarness, _ text: String, mode: Int = 0o600) throws -> URL {
        let dir = h.home.appendingPathComponent(".ssh")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("authorized_keys")
        try text.write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: file.path)
        return file
    }

    @Test func installAgentWritesTheFileAndLoadsIt() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        try succeedingLaunchctl(h)
        #expect(h.run(["install-agent"]).exitCode == 0)
        let data = try Data(contentsOf: plistURL(h))
        let plist = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        #expect(plist["Label"] as? String == agentLabel)
        #expect(plist["RunAtLoad"] as? Bool == true)
        #expect(plist["LimitLoadToSessionType"] as? String == "Aqua")
        #expect(plist["KeepAlive"] == nil)
        let arguments = try #require(plist["ProgramArguments"] as? [String])
        #expect(arguments == ["/bin/zsh", "-lc", "exec \"\(h.home.path)/.macmosh/macmosh-host\" start"])
        let uid = getuid()
        #expect(launchctlLog(h) == [
            "bootout gui/\(uid)/\(agentLabel)",
            "bootstrap gui/\(uid) \(plistURL(h).path)",
        ])
    }

    @Test func installAgentReturnsLaunchctlsCode() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        try h.stub("launchctl", script: """
            echo "$*" >> "$HOME/launchctl.log"
            if [ "$1" = "bootstrap" ]; then exit 5; fi
            exit 1
            """)
        #expect(h.run(["install-agent"]).exitCode == 5)
    }

    @Test func installAgentTwiceStillWorks() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        try succeedingLaunchctl(h)
        #expect(h.run(["install-agent"]).exitCode == 0)
        #expect(h.run(["install-agent"]).exitCode == 0)
        #expect(launchctlLog(h).count == 4)
        #expect(h.run(["status"]).stdout.contains("\nagent\tinstalled\n"))
    }

    @Test func uninstallRemovesOnlyMacMoshThings() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        try succeedingLaunchctl(h)
        let lines = keys.enumerated().map { "ssh-ed25519 \($0.element) person\($0.offset)@example" }
        let file = try writeAuthorizedKeys(h, lines.joined(separator: "\n") + "\n")
        _ = h.run(["start"])
        _ = h.run(["desk-new", "stay", h.home.path])
        #expect(h.run(["install-agent"]).exitCode == 0)
        #expect(FileManager.default.fileExists(atPath: plistURL(h).path))

        #expect(h.run(["uninstall", "--key", keys[1]]).exitCode == 0)

        let after = try String(contentsOf: file, encoding: .utf8)
        #expect(after == lines[0] + "\n" + lines[2] + "\n")
        let mode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        #expect(mode == 0o600)
        #expect(!FileManager.default.fileExists(atPath: h.home.appendingPathComponent(".macmosh").path))
        #expect(!FileManager.default.fileExists(atPath: plistURL(h).path))
        #expect(launchctlLog(h).contains("bootout gui/\(getuid())/\(agentLabel)"))
        // The desk server and the open desk are left running.
        #expect(h.tmux(["list-sessions"]).exitCode == 0)
        #expect(h.tmux(["has-session", "-t", "=stay"]).exitCode == 0)
        // No temporary file is left next to authorized_keys.
        let siblings = try FileManager.default.contentsOfDirectory(atPath: file.deletingLastPathComponent().path)
        #expect(siblings == ["authorized_keys"])
    }

    @Test func uninstallKeepsAnotherModeAndMatchesWholeFieldsOnly() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        try succeedingLaunchctl(h)
        // One line carries the key only inside a longer key text: it must stay.
        let longer = keys[1] + "ZZZZ"
        let text = """
            ssh-ed25519 \(keys[0]) first
            ssh-ed25519 \(longer) longer
            command="true" ssh-ed25519 \(keys[1]) with-options
            no-newline-at-end ssh-ed25519 \(keys[2]) last
            """
        let file = try writeAuthorizedKeys(h, text, mode: 0o640)
        #expect(h.run(["uninstall", "--key", keys[1]]).exitCode == 0)
        let after = try String(contentsOf: file, encoding: .utf8)
        #expect(after == """
            ssh-ed25519 \(keys[0]) first
            ssh-ed25519 \(longer) longer
            no-newline-at-end ssh-ed25519 \(keys[2]) last

            """)
        let mode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        #expect(mode == 0o640)
    }

    @Test func uninstallLeavesAnUnmatchedFileAlone() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        try succeedingLaunchctl(h)
        let text = "ssh-ed25519 \(keys[0]) first\nssh-ed25519 \(keys[2]) last\n"
        let file = try writeAuthorizedKeys(h, text)
        let before = try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date
        #expect(h.run(["uninstall", "--key", keys[1]]).exitCode == 0)
        #expect(try String(contentsOf: file, encoding: .utf8) == text)
        #expect(try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date == before)
    }

    @Test func uninstallWithNoAuthorizedKeysFileIsFine() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        try succeedingLaunchctl(h)
        #expect(h.run(["uninstall", "--key", keys[1]]).exitCode == 0)
        #expect(!FileManager.default.fileExists(atPath: h.home.appendingPathComponent(".ssh/authorized_keys").path))
    }

    @Test func uninstallRefusesAShortOrEmptyKey() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        try succeedingLaunchctl(h)
        let text = "ssh-ed25519 \(keys[0]) first\nssh-ed25519 \(keys[1]) second\n"
        let file = try writeAuthorizedKeys(h, text)
        _ = h.run(["start"])
        #expect(h.run(["uninstall", "--key", ""]).exitCode == 2)
        #expect(h.run(["uninstall", "--key", "AAAA"]).exitCode == 2)
        #expect(h.run(["uninstall"]).exitCode == 2)
        #expect(h.run(["uninstall", "--key"]).exitCode == 2)
        #expect(try Data(contentsOf: file) == Data(text.utf8))
        // Nothing else was touched either.
        #expect(FileManager.default.fileExists(atPath: h.home.appendingPathComponent(".macmosh").path))
        #expect(launchctlLog(h).isEmpty)
    }
}
}
