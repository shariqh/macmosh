import Foundation
import Testing
@testable import MacMoshKit

private let appPath = SystemHints.tailscaleAppPath

private func tailscaleJSON() throws -> String { try fixture("tailscale/status.json") }

/// What the stand-in commands answer. Each defaults to a Mac with Tailscale on and a network.
private struct Answers: Sendable {
    var tailscale = FakeRunner.ok("")
    var route = FakeRunner.ok("   route to: default\ndestination: default\n")
    var scutil = FakeRunner.ok("Available network connection services in the current set (*=enabled):\n")
}

private func runner(_ answers: Answers) -> FakeRunner {
    FakeRunner { argv in
        switch argv.first ?? "" {
        case SystemHints.routePath: return answers.route
        case SystemHints.scutilPath: return answers.scutil
        default: return answers.tailscale
        }
    }
}

/// A `SystemHints` that sees only the Tailscale app (or nothing, with `tailscaleAt: nil`) and the
/// given addresses of its own.
private func systemHints(_ runner: FakeRunner, tailscaleAt path: String? = appPath,
                         ownAddresses: [String] = []) -> SystemHints {
    SystemHints(runner: runner, isExecutable: { $0 == path }, searchPath: "/usr/bin:/bin",
                ownAddresses: { ownAddresses })
}

private func answers(tailscale json: String) -> Answers {
    var a = Answers()
    a.tailscale = FakeRunner.ok(json)
    return a
}

@Suite struct HintsTests {
    // MARK: the plan's named tests

    @Test func parsesTailscaleStatus() throws {
        let status = try TailscaleStatus.parse(json: Data(tailscaleJSON().utf8))
        #expect(status.running)
        let names: [String] = status.peers.map(\.dnsName).sorted()
        let expected: [String] = ["media-box.example-tailnet.ts.net.", "workhorse.example-tailnet.ts.net."]
        #expect(names == expected)
        let workhorse = status.peers.first { $0.dnsName.hasPrefix("workhorse.") }
        let addresses: [String] = ["100.101.102.103", "fd7a:115c:a1e0::103"]
        #expect(workhorse?.hostName == "Spare MacBook Pro")
        #expect(workhorse?.os == "macOS")
        #expect(workhorse?.online == true)
        #expect(workhorse?.addresses == addresses)
        let mediaBox = status.peers.first { $0.hostName == "media-box" }
        #expect(mediaBox?.online == false)
        #expect(mediaBox?.os == "linux")
    }

    @Test func stoppedTailscaleIsNotRunning() throws {
        let status = try TailscaleStatus.parse(json: Data(#"{"BackendState": "Stopped", "Peer": null}"#.utf8))
        #expect(!status.running)
        #expect(status.peers.isEmpty)
    }

    @Test func findsAPeerByShortOrFullName() throws {
        let status = try TailscaleStatus.parse(json: Data(tailscaleJSON().utf8))
        let full = "workhorse.example-tailnet.ts.net"
        for address in ["workhorse", "WorkHorse", full, full + ".", full.uppercased(), "spare macbook pro",
                        "100.101.102.103", "FD7A:115C:A1E0::103"] {
            #expect(status.peer(matching: address)?.dnsName == full + ".", "address \(address)")
        }
        #expect(status.peer(matching: "media-box")?.hostName == "media-box")
        #expect(status.peer(matching: "laptop") == nil)
        #expect(status.peer(matching: "workhorse.local") == nil)
        #expect(status.peer(matching: "100.101.102.10") == nil)
        #expect(status.peer(matching: "") == nil)
    }

    @Test func tailscalesOwnLineIsNotAnotherVPN() async throws {
        var a = answers(tailscale: try tailscaleJSON())
        a.scutil = FakeRunner.ok(try fixture("hints/scutil-tailscale-only.txt"))
        let hints = await systemHints(runner(a)).hints(for: .sample())
        #expect(!hints.otherVPN)
    }

    @Test func aSecondConnectedServiceIsAnotherVPN() async throws {
        var a = answers(tailscale: try tailscaleJSON())
        a.scutil = FakeRunner.ok(try fixture("hints/scutil-other-vpn.txt"))
        let hints = await systemHints(runner(a)).hints(for: .sample())
        #expect(hints.otherVPN)
    }

    @Test func noDefaultRouteMeansNoNetwork() async throws {
        var a = answers(tailscale: try tailscaleJSON())
        a.route = FakeRunner.failed(1, stderr: "route: writing to routing socket: not in table\n")
        let hints = await systemHints(runner(a)).hints(for: .sample())
        #expect(!hints.hasNetwork)

        let withRoute = await systemHints(runner(answers(tailscale: try tailscaleJSON()))).hints(for: .sample())
        #expect(withRoute.hasNetwork)
    }

    @Test func atHomeWhenAnAddressIsInTheHomeNetwork() async {
        let home = Workhorse.sample(homeAddress: "192.168.1.20", homePrefix: 24)
        let atHome = await systemHints(runner(Answers()), ownAddresses: ["192.168.1.7"]).hints(for: home)
        #expect(atHome.atHome == true)

        let away = await systemHints(runner(Answers()), ownAddresses: ["10.0.0.5"]).hints(for: home)
        #expect(away.atHome == false)

        let unknown = await systemHints(runner(Answers()), ownAddresses: ["192.168.1.7"]).hints(for: .sample())
        #expect(unknown.atHome == nil)
    }

    @Test func theTailscaleCommandGetsItsVariable() async throws {
        let fake = runner(answers(tailscale: try tailscaleJSON()))
        _ = await systemHints(fake).hints(for: .sample())
        let call = fake.calls.first { $0.argv.first == appPath }
        let expected: [String] = [appPath, "status", "--json"]
        #expect(call?.argv == expected)
        #expect(call?.environment["TAILSCALE_BE_CLI"] == "1")
    }

    // MARK: Tailscale

    @Test func findsTheWorkhorseAmongTheTailscaleDevices() async throws {
        let fake = runner(answers(tailscale: try tailscaleJSON()))
        let hints = await systemHints(fake).hints(for: .sample(mainAddress: "workhorse"))
        #expect(hints.tailscaleRunning == true)
        #expect(hints.peerOnline == true)

        let offline = await systemHints(fake).hints(for: .sample(mainAddress: "media-box.example-tailnet.ts.net"))
        #expect(offline.peerOnline == false)
    }

    @Test func aMainAddressThatIsNotATailscaleDeviceHasNoPeer() async throws {
        let fake = runner(answers(tailscale: try tailscaleJSON()))
        let hints = await systemHints(fake).hints(for: .sample(mainAddress: "192.168.1.20"))
        #expect(hints.tailscaleRunning == true)
        #expect(hints.peerOnline == nil)
    }

    @Test func noTailscaleRunsNoTailscaleCommand() async {
        let fake = runner(Answers())
        let hints = await systemHints(fake, tailscaleAt: nil).hints(for: .sample())
        #expect(hints.tailscaleRunning == nil)
        #expect(hints.peerOnline == nil)
        let programs: [String] = fake.calls.compactMap(\.argv.first).sorted()
        let expected: [String] = [SystemHints.routePath, SystemHints.scutilPath]
        #expect(programs == expected)
    }

    @Test func tailscaleOnThePathIsUsedWithoutTheApp() async throws {
        let onPath = "/opt/homebrew/bin/tailscale"
        let fake = runner(answers(tailscale: try tailscaleJSON()))
        let hints = await systemHints(fake, tailscaleAt: onPath).hints(for: .sample())
        #expect(hints.tailscaleRunning == true)
        let call = fake.calls.first { $0.argv.first == onPath }
        #expect(call?.environment["TAILSCALE_BE_CLI"] == "1")
    }

    @Test func aTailscaleCommandThatFailsMeansTailscaleIsOff() async {
        var a = Answers()
        a.tailscale = FakeRunner.failed(1, stderr: "failed to connect to local Tailscale service; is Tailscale running?\n")
        let hints = await systemHints(runner(a)).hints(for: .sample())
        #expect(hints.tailscaleRunning == false)
        #expect(hints.peerOnline == nil)
    }

    @Test func aTailscaleCommandThatHangsSaysNothing() async {
        var a = Answers()
        a.tailscale = CommandResult(exitCode: -1, stdout: "", stderr: "", timedOut: true)
        let hints = await systemHints(runner(a)).hints(for: .sample())
        #expect(hints.tailscaleRunning == nil)
        #expect(hints.peerOnline == nil)
    }

    @Test func stoppedTailscaleIsOffInTheHints() async {
        let fake = runner(answers(tailscale: #"{"BackendState": "Stopped", "Peer": null}"#))
        let hints = await systemHints(fake).hints(for: .sample())
        #expect(hints.tailscaleRunning == false)
    }

    // MARK: every command

    @Test func everyCommandHasAFiveSecondLimit() async throws {
        let fake = runner(answers(tailscale: try tailscaleJSON()))
        _ = await systemHints(fake).hints(for: .sample())
        #expect(fake.calls.count == 3)
        for call in fake.calls {
            #expect(call.timeout == .seconds(5), "\(call.argv)")
        }
    }

    @Test func onlyTheTailscaleCommandGetsTheVariable() async throws {
        let fake = runner(answers(tailscale: try tailscaleJSON()))
        _ = await systemHints(fake).hints(for: .sample())
        for call in fake.calls where call.argv.first != appPath {
            #expect(call.environment.isEmpty, "\(call.argv)")
        }
    }

    @Test func aRouteCommandThatHangsMeansNoNetwork() async {
        var a = Answers()
        a.route = CommandResult(exitCode: -1, stdout: "", stderr: "", timedOut: true)
        let hints = await systemHints(runner(a)).hints(for: .sample())
        #expect(!hints.hasNetwork)
    }

    // MARK: at home

    @Test func ownAddressesThatNeverCountAsHome() {
        // Loopback, link-local and Tailscale's range, each inside a home network that would hold it.
        #expect(SystemHints.atHome(ownAddresses: ["127.0.0.1"], homeAddress: "127.0.0.2", homePrefix: 8) == false)
        #expect(SystemHints.atHome(ownAddresses: ["169.254.10.20"], homeAddress: "169.254.10.1", homePrefix: 16) == false)
        #expect(SystemHints.atHome(ownAddresses: ["100.101.102.104"], homeAddress: "100.101.102.103", homePrefix: 10) == false)
        #expect(SystemHints.atHome(ownAddresses: ["100.64.0.1"], homeAddress: "100.64.0.2", homePrefix: 24) == false)
        #expect(SystemHints.atHome(ownAddresses: ["100.127.255.254"], homeAddress: "100.127.255.1", homePrefix: 24) == false)
    }

    @Test func addressesJustOutsideTailscalesRangeCanBeHome() {
        #expect(SystemHints.atHome(ownAddresses: ["100.63.255.7"], homeAddress: "100.63.255.1", homePrefix: 24) == true)
        #expect(SystemHints.atHome(ownAddresses: ["100.128.0.7"], homeAddress: "100.128.0.1", homePrefix: 24) == true)
    }

    @Test func anyOneOwnAddressInTheHomeNetworkIsEnough() {
        let own = ["127.0.0.1", "100.101.102.104", "10.0.0.5", "192.168.1.7"]
        #expect(SystemHints.atHome(ownAddresses: own, homeAddress: "192.168.1.20", homePrefix: 24) == true)
        #expect(SystemHints.atHome(ownAddresses: [], homeAddress: "192.168.1.20", homePrefix: 24) == false)
    }

    @Test func thePrefixDecidesTheHomeNetwork() {
        #expect(SystemHints.atHome(ownAddresses: ["192.168.2.7"], homeAddress: "192.168.1.20", homePrefix: 24) == false)
        #expect(SystemHints.atHome(ownAddresses: ["192.168.2.7"], homeAddress: "192.168.1.20", homePrefix: 16) == true)
        #expect(SystemHints.atHome(ownAddresses: ["192.168.1.20"], homeAddress: "192.168.1.20", homePrefix: 32) == true)
        #expect(SystemHints.atHome(ownAddresses: ["192.168.1.21"], homeAddress: "192.168.1.20", homePrefix: 32) == false)
    }

    @Test func anUnknownOrOddHomeNetworkIsNil() {
        #expect(SystemHints.atHome(ownAddresses: ["192.168.1.7"], homeAddress: nil, homePrefix: 24) == nil)
        #expect(SystemHints.atHome(ownAddresses: ["192.168.1.7"], homeAddress: "192.168.1.20", homePrefix: nil) == nil)
        #expect(SystemHints.atHome(ownAddresses: ["192.168.1.7"], homeAddress: "", homePrefix: 24) == nil)
        #expect(SystemHints.atHome(ownAddresses: ["192.168.1.7"], homeAddress: "192.168.1", homePrefix: 24) == nil)
        #expect(SystemHints.atHome(ownAddresses: ["192.168.1.7"], homeAddress: "192.168.1.256", homePrefix: 24) == nil)
        #expect(SystemHints.atHome(ownAddresses: ["192.168.1.7"], homeAddress: "192.168.1.20", homePrefix: 0) == nil)
        #expect(SystemHints.atHome(ownAddresses: ["192.168.1.7"], homeAddress: "192.168.1.20", homePrefix: 33) == nil)
    }

    @Test func thisMacsOwnAddressesIncludeLoopback() {
        #expect(SystemHints.ownIPv4Addresses().contains("127.0.0.1"))
    }

    // MARK: the stand-in

    @Test func fixedHintsAnswersWhatItWasGiven() async {
        let provider: any HintsProvider = FixedHints(.allFine)
        #expect(await provider.hints(for: .sample()) == .allFine)
    }
}
