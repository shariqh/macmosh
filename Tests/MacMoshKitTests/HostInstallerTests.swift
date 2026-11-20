import Foundation
import Testing
@testable import MacMoshKit

@Suite struct HostInstallerTests {
    @Test(arguments: [(nil, "0.1.0", HostInstaller.Decision.install), ("0.1.0", "0.1.0", .keep),
                      ("0.0.9", "0.1.0", .replace), ("0.2.0", "0.1.0", .tooNew), ("0.9.0", "0.10.0", .replace)])
    func decidesByVersion(installed: String?, builtIn: String, expected: HostInstaller.Decision) {
        #expect(HostInstaller.decide(installed: installed, builtIn: builtIn) == expected)
    }

    @Test func installPipesTheScriptThenLoadsTheAgent() async throws {
        let runner = FakeRunner { _ in FakeRunner.ok() }
        try await HostInstaller(runner: runner, paths: .test).install(on: .sample(), address: "workhorse")
        #expect(runner.calls.count == 2)
        #expect(runner.calls[0].stdin == Data(HostScript.source.utf8))
        #expect(runner.calls[0].argv.last == "mkdir -p ~/.macmosh && cat > ~/.macmosh/macmosh-host.new && chmod 755 ~/.macmosh/macmosh-host.new && mv ~/.macmosh/macmosh-host.new ~/.macmosh/macmosh-host")
        #expect(runner.calls[1].argv.last == "~/.macmosh/macmosh-host install-agent")
    }

    @Test func bothCallsAreBatchSSHWithThePinnedKeyAndATimeLimit() async throws {
        let runner = FakeRunner { _ in FakeRunner.ok() }
        let w = Workhorse.sample()
        try await HostInstaller(runner: runner, paths: .test).install(on: w, address: "192.168.1.20")
        for call in runner.calls {
            #expect(call.argv.first == "ssh")
            #expect(sshTarget(call.argv) == "alex@192.168.1.20")
            #expect(call.argv.contains("BatchMode=yes"))
            #expect(call.argv.contains("StrictHostKeyChecking=yes"))
            #expect(call.argv.contains("HostKeyAlias=\(w.hostKeyAlias)"))
            #expect(call.timeout <= .seconds(60))
        }
        #expect(runner.calls[1].stdin == nil)
    }

    @Test func aFailedCopyStopsBeforeTheAgent() async {
        let runner = FakeRunner { _ in FakeRunner.failed(1, stderr: "mv: rename failed\n") }
        await #expect(throws: HostInstallerError.self) {
            try await HostInstaller(runner: runner, paths: .test).install(on: .sample(), address: "workhorse")
        }
        #expect(runner.calls.count == 1)
    }

    @Test func aFailedAgentLoadIsAnError() async {
        let runner = FakeRunner { argv in
            argv.last == "~/.macmosh/macmosh-host install-agent" ? FakeRunner.failed(5, stderr: "Bootstrap failed\n") : FakeRunner.ok()
        }
        await #expect(throws: HostInstallerError.self) {
            try await HostInstaller(runner: runner, paths: .test).install(on: .sample(), address: "workhorse")
        }
        #expect(runner.calls.count == 2)
    }

    @Test func noSSHRunsWithoutAUsableKey() async throws {
        let paths = try temporaryPaths()
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: paths.defaultIdentity.path)
        let runner = FakeRunner { _ in FakeRunner.ok() }
        await #expect(throws: HostInstallerError.self) {
            try await HostInstaller(runner: runner, paths: paths).install(on: .sample(), address: "workhorse")
        }
        #expect(runner.calls.isEmpty)
    }
}
