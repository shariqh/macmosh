import Foundation
import Testing
import MacMoshKit

extension HostScriptTests {
@Suite struct RoundTripTests {
    @Test func theRealScriptsReportParses() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        let folder = h.home.appendingPathComponent("web folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        #expect(h.run(["start"]).exitCode == 0)
        #expect(h.run(["desk-new", "web", folder.path, "--reopen", "--command", "echo hi"]).exitCode == 0)

        let report = h.run(["status"])
        #expect(report.exitCode == 0)
        let status = try HostStatus.parse(report.stdout)

        #expect(status.protocolVersion == HostStatus.supportedProtocol)
        #expect(status.scriptVersion == h.scriptVersion)
        #expect(status.serverUp)
        #expect(status.consoleUser == "tester")
        let deskNames: [String] = status.desks.map(\.name.value)
        #expect(deskNames == ["web"])
        #expect(status.definitions.count == 1)
        #expect(status.definitions[0].name.value == "web")
        #expect(status.definitions[0].folder == folder.path)
        #expect(status.definitions[0].command == "echo hi")
        #expect(status.definitions[0].reopen)
        #expect(!status.definitions[0].keep)
    }

    @Test func aReportFromAServerThatIsDownStillParses() throws {
        let h = try HostHarness(); defer { h.cleanUp() }
        let status = try HostStatus.parse(h.run(["status"]).stdout)
        #expect(!status.serverUp)
        #expect(status.signIns == .unknown)
        #expect(status.desks.isEmpty)
    }
}
}
