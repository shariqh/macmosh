import Foundation

public enum HostStatusError: Error, Equatable {
    /// No line of the text is the report's header.
    case noHeader
    /// The header is there but the `end` line is not: the report was cut off.
    case truncated
    /// The report is from a script that speaks another protocol.
    case unsupportedProtocol(Int)
}

/// Whether a workhorse can be unlocked over ssh after a restart: Apple silicon and macOS 26 or later
/// (design 5.5, 7.12). A value that is missing or can't be read counts as able, so the button is not
/// hidden on a guess.
public enum OSSupport {
    public static let firstMacOSWithSSHUnlock = 26

    public static func canUnlockOverSSH(osVersion: String?, arch: String?) -> Bool {
        if let arch, !arch.isEmpty, arch != "arm64" { return false }
        if let osVersion, let major = Int(osVersion.split(separator: ".").first ?? "") {
            return major >= firstMacOSWithSSHUnlock
        }
        return true
    }
}

/// The workhorse's status report (protocol 1, "Shared interfaces" in the plan), read into values.
///
/// The reader is strict where that protects the user and lenient where it helps later versions:
/// - lines before the header are skipped, and a report with no header is `.noHeader`;
/// - a header with another protocol number is `.unsupportedProtocol`, whatever follows it;
/// - a report with no `end` line is `.truncated`, and nothing after the `end` line is read;
/// - a record type this version doesn't know is ignored;
/// - a known record with too few fields, or a number that isn't one, gives that value as unknown
///   or nil. Where a value has no unknown (a desk's window count, a definition's reopen flag), the
///   whole desk or definition is left out. A desk or definition whose name is not a valid
///   `DeskName` is left out too.
public struct HostStatus: Sendable, Equatable {
    public enum Tri: String, Sendable { case yes, no, unknown }
    public struct Power: Sendable, Equatable {
        public var sleepOnPower, wakeForNetwork, autoRestart, disableSleep: Int?
    }
    public struct Battery: Sendable, Equatable {
        public var present: Bool
        public var onAC: Bool?
        public var percent: Int?
    }
    public struct Home: Sendable, Equatable {
        public var address: String?
        public var prefix: Int?
        public var localName: String?
    }
    public struct Tool: Sendable, Equatable {
        public var name: String
        public var path: String?
        public var version: String?
    }
    public struct Window: Sendable, Equatable {
        public var index: Int
        public var name: String
    }
    public struct Desk: Sendable, Equatable {
        public var name: DeskName
        public var windows: [Window]
        public var windowCount: Int
        public var attached: Int
    }
    public struct Definition: Sendable, Equatable {
        public var name: DeskName
        public var reopen, keep: Bool
        public var folder, command: String
    }

    public static let supportedProtocol = 1

    public var protocolVersion: Int = HostStatus.supportedProtocol
    public var scriptVersion: String = ""
    public var osVersion: String = ""
    public var arch: String = ""
    /// nil: nobody is logged in at the screen.
    public var consoleUser: String?
    public var serverUp: Bool = false
    public var signIns: Tri = .unknown
    public var fileVault: Tri = .unknown
    public var authRestart: Tri = .unknown
    public var firewall: Tri = .unknown
    public var screenSharing: Tri = .unknown
    public var agentInstalled: Bool = false
    public var power = Power()
    public var battery = Battery(present: false)
    public var home = Home()
    public var tools: [Tool] = []
    public var desks: [Desk] = []
    public var definitions: [Definition] = []

    /// A workhorse with a battery is a laptop.
    public var isLaptop: Bool { battery.present }

    /// `OSSupport` with this report's macOS version and chip.
    public var canUnlockOverSSH: Bool {
        OSSupport.canUnlockOverSSH(osVersion: osVersion.isEmpty ? nil : osVersion,
                                   arch: arch.isEmpty ? nil : arch)
    }

    public static func parse(_ text: String) throws -> HostStatus {
        // "\r\n" is one Character in Swift, so it is turned into "\n" before the text is split.
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }

        // The header: the first line that has the header's name and a protocol number.
        var headerAt: Int?
        var protocolNumber = 0
        for (i, f) in lines.enumerated() where f.count >= 2 && f[0] == "macmosh-host" {
            if let n = Int(f[1]) {
                headerAt = i
                protocolNumber = n
                break
            }
        }
        guard let start = headerAt else { throw HostStatusError.noHeader }
        guard protocolNumber == supportedProtocol else { throw HostStatusError.unsupportedProtocol(protocolNumber) }

        guard let end = lines[(start + 1)...].firstIndex(where: { $0 == ["end"] }) else {
            throw HostStatusError.truncated
        }

        var s = HostStatus()
        s.protocolVersion = protocolNumber
        s.scriptVersion = lines[start].count > 2 ? lines[start][2] : ""

        var windows: [String: [Window]] = [:]
        for f in lines[(start + 1)..<end] {
            switch f[0] {
            case "os":
                s.osVersion = field(f, 1)
                s.arch = field(f, 2)
            case "console":
                let user = field(f, 1)
                s.consoleUser = user.isEmpty ? nil : user
            case "server": s.serverUp = field(f, 1) == "up"
            case "signins": s.signIns = tri(field(f, 1), yes: "ok", no: "off")
            case "filevault": s.fileVault = tri(field(f, 1), yes: "on", no: "off")
            case "authrestart": s.authRestart = tri(field(f, 1), yes: "yes", no: "no")
            case "firewall": s.firewall = tri(field(f, 1), yes: "on", no: "off")
            case "screensharing": s.screenSharing = tri(field(f, 1), yes: "on", no: "off")
            case "agent": s.agentInstalled = field(f, 1) == "installed"
            case "power": s.power = power(f)
            case "battery":
                let percent = Int(field(f, 3))
                s.battery = Battery(present: field(f, 1) == "present",
                                    onAC: field(f, 2) == "ac" ? true : (field(f, 2) == "battery" ? false : nil),
                                    percent: percent.flatMap { (0...100).contains($0) ? $0 : nil })
            case "home":
                s.home = Home(address: nonEmpty(field(f, 1)), prefix: Int(field(f, 2)),
                              localName: nonEmpty(field(f, 3)))
            case "tool":
                let name = field(f, 1)
                if !name.isEmpty {
                    s.tools.append(Tool(name: name, path: dashIsNil(field(f, 2)), version: dashIsNil(field(f, 3))))
                }
            case "desk":
                if let name = DeskName(field(f, 1)), let count = Int(field(f, 2)), let attached = Int(field(f, 3)) {
                    s.desks.append(Desk(name: name, windows: [], windowCount: count, attached: attached))
                }
            case "window":
                if let index = Int(field(f, 2)) {
                    windows[field(f, 1), default: []].append(Window(index: index, name: field(f, 3)))
                }
            case "def":
                // The startup command is the last field. A report with no tab after the folder has none.
                if let name = DeskName(field(f, 1)), let reopen = flag(field(f, 2)), let keep = flag(field(f, 3)),
                   f.count >= 5 {
                    let command = f.count > 5 ? f[5...].joined(separator: "\t") : ""
                    s.definitions.append(Definition(name: name, reopen: reopen, keep: keep,
                                                    folder: f[4], command: command))
                }
            default:
                break   // a record type from a later version
            }
        }

        // A window line may come before its desk's line, so windows are attached once all are read.
        s.desks = s.desks.map { desk in
            var desk = desk
            desk.windows = (windows[desk.name.value] ?? []).sorted { $0.index < $1.index }
            return desk
        }
        return s
    }

    // MARK: - Reading fields

    /// Field `i` of a record, or "" when the record is too short.
    private static func field(_ f: [String], _ i: Int) -> String { i < f.count ? f[i] : "" }

    private static func tri(_ value: String, yes: String, no: String) -> Tri {
        switch value {
        case yes: return .yes
        case no: return .no
        default: return .unknown
        }
    }

    private static func nonEmpty(_ value: String) -> String? { value.isEmpty ? nil : value }

    /// `-` and "" both mean the script found nothing.
    private static func dashIsNil(_ value: String) -> String? { value.isEmpty || value == "-" ? nil : value }

    private static func flag(_ value: String) -> Bool? {
        switch value {
        case "1": return true
        case "0": return false
        default: return nil
        }
    }

    /// `power`: `key=value` fields. A key this version doesn't know is ignored; `-` or a non-number is nil.
    private static func power(_ f: [String]) -> Power {
        var p = Power()
        for item in f.dropFirst() {
            let parts = item.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let value = Int(parts[1])
            switch parts[0] {
            case "sleep": p.sleepOnPower = value
            case "womp": p.wakeForNetwork = value
            case "autorestart": p.autoRestart = value
            case "disablesleep": p.disableSleep = value
            default: break
            }
        }
        return p
    }
}
