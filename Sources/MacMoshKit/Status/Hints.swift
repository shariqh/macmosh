import Foundation

/// What this Mac knows that helps explain why a workhorse doesn't answer. Hints only pick the
/// reason shown under "Can't reach it" and tell a Tailscale main address apart (design 7.4).
public struct Hints: Sendable, Equatable {
    public var tailscaleRunning: Bool?               // nil: Tailscale isn't installed
    public var peerOnline: Bool?                     // nil: the main address isn't one of the Tailscale devices
    public var hasNetwork: Bool
    public var otherVPN: Bool
    public var atHome: Bool?                         // nil: the home network isn't known yet

    public init(tailscaleRunning: Bool?, peerOnline: Bool?, hasNetwork: Bool, otherVPN: Bool, atHome: Bool?) {
        self.tailscaleRunning = tailscaleRunning
        self.peerOnline = peerOnline
        self.hasNetwork = hasNetwork
        self.otherVPN = otherVPN
        self.atHome = atHome
    }
}

/// One of the other devices on the tailnet, from `tailscale status --json`.
public struct TailscalePeer: Sendable, Equatable {
    public var hostName, dnsName, os: String
    /// "Connected to Tailscale's servers", not "reachable" (design 7.4).
    public var online: Bool
    /// Its Tailscale addresses (`TailscaleIPs`), IPv4 and IPv6.
    public var addresses: [String]

    public init(hostName: String, dnsName: String, os: String, online: Bool, addresses: [String] = []) {
        self.hostName = hostName
        self.dnsName = dnsName
        self.os = os
        self.online = online
        self.addresses = addresses
    }
}

/// The parts of `tailscale status --json` MacMosh reads.
public struct TailscaleStatus: Sendable, Equatable {
    public var running: Bool
    public var peers: [TailscalePeer]

    public init(running: Bool, peers: [TailscalePeer]) {
        self.running = running
        self.peers = peers
    }

    private struct Raw: Decodable {
        var BackendState: String?
        var Peer: [String: RawPeer]?
    }
    private struct RawPeer: Decodable {
        var HostName: String?
        var DNSName: String?
        var OS: String?
        var Online: Bool?
        var TailscaleIPs: [String]?
    }

    /// `running` is `BackendState == "Running"`. Peers come in the order of their keys, so the
    /// result doesn't depend on the order of the JSON object. Missing fields are empty or false.
    public static func parse(json: Data) throws -> TailscaleStatus {
        let raw = try JSONDecoder().decode(Raw.self, from: json)
        let peers = (raw.Peer ?? [:]).sorted { $0.key < $1.key }.map { _, p in
            TailscalePeer(hostName: p.HostName ?? "", dnsName: p.DNSName ?? "", os: p.OS ?? "",
                          online: p.Online ?? false, addresses: p.TailscaleIPs ?? [])
        }
        return TailscaleStatus(running: raw.BackendState == "Running", peers: peers)
    }

    /// The device `address` names, in any case: its full DNS name (with or without the trailing
    /// dot), its DNS name without the tailnet suffix, one of its Tailscale addresses, or its host
    /// name. The closest kind of match wins, in that order, so a device whose host name happens to
    /// be another device's short name is not picked over that device.
    public func peer(matching address: String) -> TailscalePeer? {
        let wanted = Self.normalized(address)
        guard !wanted.isEmpty else { return nil }
        let tests: [(TailscalePeer) -> Bool] = [
            { Self.normalized($0.dnsName) == wanted },
            { $0.addresses.contains { Self.normalized($0) == wanted } },
            { Self.shortName(Self.normalized($0.dnsName)) == wanted },
            { Self.normalized($0.hostName) == wanted },
        ]
        for test in tests {
            if let peer = peers.first(where: test) { return peer }
        }
        return nil
    }

    /// Lower case, without surrounding spaces or a trailing dot.
    private static func normalized(_ name: String) -> String {
        var s = name.trimmingCharacters(in: .whitespaces).lowercased()
        while s.hasSuffix(".") { s.removeLast() }
        return s
    }

    /// The first label of a MagicDNS name: the name without the tailnet suffix.
    private static func shortName(_ dnsName: String) -> String {
        String(dnsName.prefix { $0 != "." })
    }
}

/// Gives the hints for a workhorse. Tests use a stand-in.
public protocol HintsProvider: Sendable { func hints(for workhorse: Workhorse) async -> Hints }

/// Hints from this Mac: the Tailscale command, the default route, the VPN list and its own addresses.
public struct SystemHints: HintsProvider {
    public static let tailscaleAppPath = "/Applications/Tailscale.app/Contents/MacOS/Tailscale"
    static let routePath = "/sbin/route"
    static let scutilPath = "/usr/sbin/scutil"
    /// Every command gets this long to answer.
    static let timeLimit: Duration = .seconds(5)

    private let runner: CommandRunner
    private let isExecutable: @Sendable (String) -> Bool
    private let searchPath: String?
    private let ownAddresses: @Sendable () -> [String]

    public init(runner: CommandRunner) {
        self.init(runner: runner,
                  isExecutable: { FileManager.default.isExecutableFile(atPath: $0) },
                  searchPath: ProcessInfo.processInfo.environment["PATH"],
                  ownAddresses: { SystemHints.ownIPv4Addresses() })
    }

    /// `isExecutable` decides which Tailscale command exists, `searchPath` is the `PATH` to look on,
    /// and `ownAddresses` gives this Mac's IPv4 addresses.
    init(runner: CommandRunner, isExecutable: @escaping @Sendable (String) -> Bool, searchPath: String?,
         ownAddresses: @escaping @Sendable () -> [String]) {
        self.runner = runner
        self.isExecutable = isExecutable
        self.searchPath = searchPath
        self.ownAddresses = ownAddresses
    }

    public func hints(for workhorse: Workhorse) async -> Hints {
        async let fromTailscale = tailscale(mainAddress: workhorse.mainAddress)
        async let network = hasNetwork()
        async let vpn = otherVPN()
        let (running, peerOnline) = await fromTailscale
        let home = Self.atHome(ownAddresses: ownAddresses(), homeAddress: workhorse.homeAddress,
                               homePrefix: workhorse.homePrefix)
        return Hints(tailscaleRunning: running, peerOnline: peerOnline, hasNetwork: await network,
                     otherVPN: await vpn, atHome: home)
    }

    /// The Tailscale app's own command, else `tailscale` on the path. Nil when neither is there.
    private func tailscaleCommand() -> String? {
        if isExecutable(Self.tailscaleAppPath) { return Self.tailscaleAppPath }
        return ToolFinder.find("tailscale", path: searchPath, isExecutable: isExecutable)
    }

    /// Whether Tailscale is running, and whether the workhorse's main address is a Tailscale device
    /// that is online. Both nil when Tailscale isn't installed or its command didn't answer in time.
    /// An answer that isn't a status (Tailscale's app not started, say) means not running.
    private func tailscale(mainAddress: String) async -> (Bool?, Bool?) {
        guard let command = tailscaleCommand() else { return (nil, nil) }
        let result = await runner.run(command, ["status", "--json"], environment: ["TAILSCALE_BE_CLI": "1"],
                                      stdin: nil, timeout: Self.timeLimit)
        if result.timedOut { return (nil, nil) }
        guard let status = try? TailscaleStatus.parse(json: Data(result.stdout.utf8)) else { return (false, nil) }
        return (status.running, status.peer(matching: mainAddress)?.online)
    }

    /// A default route means a network. Any other answer, a command stopped at its time limit
    /// included, means none, as the plan says: a non-zero exit means no network.
    private func hasNetwork() async -> Bool {
        let result = await runner.run(Self.routePath, ["-n", "get", "default"], environment: [:],
                                      stdin: nil, timeout: Self.timeLimit)
        return result.exitCode == 0 && !result.timedOut
    }

    /// A connected VPN service other than Tailscale's own.
    private func otherVPN() async -> Bool {
        let result = await runner.run(Self.scutilPath, ["--nc", "list"], environment: [:],
                                      stdin: nil, timeout: Self.timeLimit)
        guard result.exitCode == 0, !result.timedOut else { return false }
        return result.stdout.split(whereSeparator: \.isNewline).contains { line in
            line.contains("(Connected)") && !line.contains("io.tailscale")
        }
    }

    // MARK: - At home

    /// Whether one of this Mac's IPv4 addresses is inside the workhorse's home network. Loopback,
    /// link-local and Tailscale's range never count. Nil when the home network isn't known, or the
    /// address or prefix can't be read.
    static func atHome(ownAddresses: [String], homeAddress: String?, homePrefix: Int?) -> Bool? {
        guard let homeAddress, let homePrefix, (1...32).contains(homePrefix),
              let home = IPv4.parse(homeAddress) else { return nil }
        let mask = IPv4.mask(homePrefix)
        return ownAddresses.contains { text in
            guard let own = IPv4.parse(text), !IPv4.neverHome(own) else { return false }
            return own & mask == home & mask
        }
    }

    /// This Mac's IPv4 addresses on interfaces that are up, read with `getifaddrs`.
    static func ownIPv4Addresses() -> [String] {
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0 else { return [] }
        defer { freeifaddrs(first) }
        var addresses: [String] = []
        var cursor = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            guard (entry.pointee.ifa_flags & UInt32(IFF_UP)) != 0,
                  let sa = entry.pointee.ifa_addr, sa.pointee.sa_family == sa_family_t(AF_INET) else { continue }
            var address = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
            var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            if inet_ntop(AF_INET, &address, &buffer, socklen_t(buffer.count)) != nil {
                let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
                addresses.append(String(decoding: bytes, as: UTF8.self))
            }
        }
        return addresses
    }
}

/// Dotted IPv4 addresses as numbers.
enum IPv4 {
    /// Four decimal numbers from 0 to 255, separated by dots. Anything else is nil.
    static func parse(_ text: String) -> UInt32? {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var value: UInt32 = 0
        for part in parts {
            guard !part.isEmpty, part.count <= 3, part.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let n = UInt32(part), n <= 255 else { return nil }
            value = value << 8 | n
        }
        return value
    }

    /// The network mask for a prefix length from 1 to 32.
    static func mask(_ prefix: Int) -> UInt32 {
        prefix >= 32 ? UInt32.max : ~(UInt32.max >> UInt32(prefix))
    }

    /// Loopback (127.0.0.0/8), link-local (169.254.0.0/16) and Tailscale's range (100.64.0.0/10).
    static func neverHome(_ address: UInt32) -> Bool {
        let ranges: [(network: UInt32, prefix: Int)] = [
            (0x7F00_0000, 8),     // 127.0.0.0/8
            (0xA9FE_0000, 16),    // 169.254.0.0/16
            (0x6440_0000, 10),    // 100.64.0.0/10
        ]
        return ranges.contains { address & mask($0.prefix) == $0.network }
    }
}
