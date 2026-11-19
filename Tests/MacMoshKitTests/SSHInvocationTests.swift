import Foundation
import Testing
@testable import MacMoshKit

/// Splits `text` the way mosh splits its `--ssh` value: Perl's `Text::ParseWords::shellwords`.
private func moshSplit(_ text: String) async -> [String] {
    let r = await ProcessRunner().run("/usr/bin/perl", ["-MText::ParseWords", "-e", "print join(qq{\\n}, shellwords($ARGV[0]))", text],
                                      environment: [:], stdin: nil, timeout: .seconds(5))
    return r.stdout.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
}

/// Paths under a made-up home folder. Nothing is read or written there; the tests only look at the text.
private let alexPaths = Paths(supportDir: URL(fileURLWithPath: "/Users/alex/Library/Application Support/MacMosh"),
                              sshDir: URL(fileURLWithPath: "/Users/alex/.ssh"))

@Suite struct SSHInvocationTests {
    // MARK: options

    @Test func optionsPinTheHostKeyOnEveryCall() throws {
        let paths = Paths(supportDir: URL(fileURLWithPath: "/Users/alex/Library/Application Support/MacMosh"),
                          sshDir: URL(fileURLWithPath: "/Users/alex/.ssh"))
        let o = SSHInvocation.options(for: .sample(id: "mbp"), paths: paths, batch: true)
        #expect(o.contains("HostKeyAlias=macmosh-mbp"))
        #expect(o.contains("UserKnownHostsFile=\"/Users/alex/Library/Application Support/MacMosh/known_hosts\""))
        #expect(o.contains("GlobalKnownHostsFile=/dev/null"))
        #expect(o.contains("StrictHostKeyChecking=yes"))
        #expect(o.contains("UpdateHostKeys=no"))
        #expect(o.contains("IdentitiesOnly=yes"))
        #expect(o.contains("IdentityAgent=none"))
        #expect(o.contains("BatchMode=yes") && o.contains("ConnectTimeout=5"))
    }

    @Test func hostKeyOptionsAreTheFivePinningOptionsInOrder() {
        #expect(SSHInvocation.hostKeyOptions(for: .sample(id: "mbp"), paths: alexPaths) == [
            "-o", "HostKeyAlias=macmosh-mbp",
            "-o", "UserKnownHostsFile=\"/Users/alex/Library/Application Support/MacMosh/known_hosts\"",
            "-o", "GlobalKnownHostsFile=/dev/null",
            "-o", "StrictHostKeyChecking=yes",
            "-o", "UpdateHostKeys=no",
        ])
    }

    @Test func batchOptionsComeInThePlannedOrder() {
        let w = Workhorse.sample(id: "mbp")
        #expect(SSHInvocation.options(for: w, paths: alexPaths, batch: true)
                == SSHInvocation.hostKeyOptions(for: w, paths: alexPaths) + [
                    "-o", "IdentitiesOnly=yes",
                    "-i", "/Users/alex/.ssh/macmosh_ed25519",
                    "-o", "IdentityAgent=none",
                    "-o", "BatchMode=yes",
                    "-o", "ConnectTimeout=5",
                ])
    }

    @Test func interactiveOptionsHaveNoBatchMode() {
        let w = Workhorse.sample(id: "mbp")
        let o = SSHInvocation.options(for: w, paths: alexPaths, batch: false)
        #expect(!o.contains("BatchMode=yes"))
        #expect(!o.contains("ConnectTimeout=5"))
        #expect(o == SSHInvocation.hostKeyOptions(for: w, paths: alexPaths) + [
            "-o", "IdentitiesOnly=yes",
            "-i", "/Users/alex/.ssh/macmosh_ed25519",
            "-o", "IdentityAgent=none",
        ])
    }

    @Test func aCustomIdentityKeepsTheAgent() {
        let w = Workhorse.sample(id: "mbp", identityFile: "/Users/alex/.ssh/work_ed25519")
        for batch in [true, false] {
            let o = SSHInvocation.options(for: w, paths: alexPaths, batch: batch)
            let i = o.firstIndex(of: "-i")
            #expect(i.map { o[$0 + 1] } == "/Users/alex/.ssh/work_ed25519")
            #expect(!o.contains("IdentityAgent=none"))
            #expect(o.contains("IdentitiesOnly=yes"))
        }
    }

    @Test func aTildeInTheIdentityFileIsExpanded() {
        let w = Workhorse.sample(id: "mbp", identityFile: "~/keys/work_ed25519")
        let o = SSHInvocation.options(for: w, paths: alexPaths, batch: true)
        let expected = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("keys/work_ed25519").path
        #expect(o.firstIndex(of: "-i").map { o[$0 + 1] } == expected)
        #expect(!o.joined(separator: " ").contains("~"))
    }

    @Test func everyOptionValueIsItsOwnArgument() {
        let o = SSHInvocation.options(for: .sample(id: "mbp"), paths: alexPaths, batch: true)
        // Flags and values alternate: every even position is a flag, every odd one its value.
        #expect(o.count % 2 == 0)
        for (n, item) in o.enumerated() where n % 2 == 0 { #expect(item == "-o" || item == "-i") }
        for (n, item) in o.enumerated() where n % 2 == 1 { #expect(!item.hasPrefix("-")) }
    }

    /// ssh's own option parser takes the double quotes off the key file's value, so a path with
    /// spaces stays one path. `ssh -G` prints the settings it would use and opens no connection;
    /// `-F /dev/null` keeps the user's own ssh settings out of it.
    @Test func sshItselfReadsTheQuotedKnownHostsPath() async throws {
        let paths = try temporaryPaths(withSpaceInPath: true)
        let w = Workhorse.sample(id: "mbp")
        let r = await ProcessRunner().run("/usr/bin/ssh", ["-F", "/dev/null", "-G"]
                                          + SSHInvocation.options(for: w, paths: paths, batch: true)
                                          + ["alex@192.168.1.20"],
                                          environment: [:], stdin: nil, timeout: .seconds(10))
        #expect(r.exitCode == 0, "ssh -G failed: \(r.stderr)")
        let lines = r.stdout.split(separator: "\n").map(String.init)
        #expect(lines.contains("userknownhostsfile " + paths.knownHostsFile.path))
        #expect(lines.contains("globalknownhostsfile /dev/null"))
        #expect(lines.contains("hostkeyalias macmosh-mbp"))
        #expect(lines.contains("stricthostkeychecking true"))
        #expect(lines.contains("identityfile " + paths.defaultIdentity.path))
    }

    // MARK: the string mosh splits

    @Test func theMoshStringSplitsBackIntoTheSameArguments() async throws {
        let paths = try temporaryPaths(withSpaceInPath: true)
        let w = Workhorse.sample(id: "mbp")
        let s = SSHInvocation.sshStringForMosh(for: w, paths: paths)
        let r = await ProcessRunner().run("/usr/bin/perl", ["-MText::ParseWords", "-e", "print join(qq{\\n}, shellwords($ARGV[0]))", s],
                                          environment: [:], stdin: nil, timeout: .seconds(5))   // the splitter mosh itself uses
        #expect(r.stdout.split(separator: "\n").map(String.init)
                == ["ssh"] + SSHInvocation.options(for: w, paths: paths, batch: false) + SSHInvocation.noPasswordOptions)
    }

    @Test func theMoshStringSurvivesQuotesAndDollarsInPaths() async {
        let paths = Paths(supportDir: URL(fileURLWithPath: "/Users/alex/Alex's $HOME `x`/MacMosh"),
                          sshDir: URL(fileURLWithPath: "/Users/alex/my keys; é ☕"))
        let w = Workhorse.sample(id: "mbp")
        let split = await moshSplit(SSHInvocation.sshStringForMosh(for: w, paths: paths))
        #expect(split == ["ssh"] + SSHInvocation.options(for: w, paths: paths, batch: false) + SSHInvocation.noPasswordOptions)
    }

    @Test func theMoshStringRefusesPasswordsAndHasNoBatchMode() {
        let s = SSHInvocation.sshStringForMosh(for: .sample(id: "mbp"), paths: alexPaths)
        #expect(s.hasPrefix("ssh "))
        #expect(s.hasSuffix(" -o PasswordAuthentication=no -o KbdInteractiveAuthentication=no"))
        #expect(!s.contains("BatchMode"))
    }

    // MARK: argv

    @Test func argvPutsTheDestinationAfterEveryOption() {
        let w = Workhorse.sample(id: "mbp", user: "alex")
        let argv = SSHInvocation.argv(for: w, address: "192.168.1.20", paths: alexPaths, batch: true, tty: true,
                                      extraOptions: SSHInvocation.noPasswordOptions,
                                      remote: SSHInvocation.hostCommand(["status"]))
        #expect(argv == ["ssh"] + SSHInvocation.options(for: w, paths: alexPaths, batch: true)
                + SSHInvocation.noPasswordOptions + ["-t", "alex@192.168.1.20", "~/.macmosh/macmosh-host status"])
    }

    @Test func emptyRemoteIsAnInteractiveLogin() {
        let w = Workhorse.sample(id: "mbp", user: "alex")
        let argv = SSHInvocation.argv(for: w, address: "workhorse", paths: alexPaths, batch: false, tty: false, remote: [])
        #expect(argv.last == "alex@workhorse")
        #expect(!argv.contains("-t"))
    }

    @Test func hostCommandQuotesEachArgumentOnce() {
        #expect(SSHInvocation.hostCommand(["desk-new", "web", "/tmp/a b"]) == ["~/.macmosh/macmosh-host desk-new web '/tmp/a b'"])
    }

    @Test func hostCommandLeavesTheTildeForTheRemoteShell() {
        #expect(SSHInvocation.remoteScript == "~/.macmosh/macmosh-host")
        #expect(SSHInvocation.hostCommand(["folders", "~"]) == ["~/.macmosh/macmosh-host folders '~'"])
        #expect(SSHInvocation.hostCommand(["version"]) == ["~/.macmosh/macmosh-host version"])
    }

    // MARK: KeyManager

    @Test func identityURLDefaultsToMacMoshsOwnKey() throws {
        let paths = try temporaryPaths()
        let keys = KeyManager(paths: paths, runner: FakeRunner { _ in FakeRunner.ok() })
        #expect(keys.identityURL(for: .sample(identityFile: nil)) == paths.defaultIdentity)
        #expect(keys.identityURL(for: .sample(identityFile: "/Users/alex/.ssh/work_ed25519")).path == "/Users/alex/.ssh/work_ed25519")
        let home = FileManager.default.homeDirectoryForCurrentUser
        #expect(keys.identityURL(for: .sample(identityFile: "~/keys/k")).path == home.appendingPathComponent("keys/k").path)
    }

    @Test func keyStateFollowsTheFile() throws {
        let paths = try temporaryPaths()
        let keys = KeyManager(paths: paths, runner: FakeRunner { _ in FakeRunner.ok() })
        let fm = FileManager.default
        let key = paths.sshDir.appendingPathComponent("custom_ed25519")
        let w = Workhorse.sample(identityFile: key.path)

        #expect(keys.identityState(for: w) == .missing)

        try Data("stand-in".utf8).write(to: key)
        try fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: key.path)
        #expect(keys.identityState(for: w) == .badPermissions)

        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: key.path)
        #expect(keys.identityState(for: w) == .usable)

        try fm.setAttributes([.posixPermissions: 0o400], ofItemAtPath: key.path)
        #expect(keys.identityState(for: w) == .usable)

        try fm.setAttributes([.posixPermissions: 0o640], ofItemAtPath: key.path)
        #expect(keys.identityState(for: w) == .badPermissions)

        // The default key from temporaryPaths() has mode 0600.
        #expect(keys.identityState(for: .sample(identityFile: nil)) == .usable)
    }

    @Test func aFolderIsNotAUsableKey() throws {
        let paths = try temporaryPaths()
        let keys = KeyManager(paths: paths, runner: FakeRunner { _ in FakeRunner.ok() })
        let folder = paths.sshDir.appendingPathComponent("not_a_key")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o600])
        #expect(keys.identityState(for: .sample(identityFile: folder.path)) == .badPermissions)
    }
}
