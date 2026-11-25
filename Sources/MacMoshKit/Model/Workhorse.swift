import Foundation

public enum ConnectionMode: String, Codable, Sendable, CaseIterable { case mosh, tabs, ssh }
public enum Prediction: String, Codable, Sendable, CaseIterable { case adaptive, always, never, experimental }

public struct Workhorse: Codable, Sendable, Identifiable, Equatable {
    public var id: String                 // slug: a-z, 0-9, "-"; the ssh host-key alias is "macmosh-<id>"
    public var name: String               // shown in the menu
    public var user: String
    public var mainAddress: String        // what the user chose, normally the Tailscale name
    public var homeAddress: String?       // from the last status report
    public var homePrefix: Int?
    public var localName: String?         // "name.local"
    public var hostKey: String            // "ssh-ed25519 AAAA…", the pinned key
    public var paired: Bool
    public var mode: ConnectionMode       // default .mosh
    public var prediction: Prediction     // default .adaptive
    public var projectsFolder: String?
    public var identityFile: String?      // nil means ~/.ssh/macmosh_ed25519
    public var osVersion: String?
    public var arch: String?
    public var lastSeen: Date?
    public var lastKeyAccepted: Date?
    public var powerChanges: [String]     // pmset commands run through MacMosh, for "Remove"
    /// The startup command the window's New desk form last sent for this workhorse, the next form's
    /// default; nil the first time, or after a desk with a plain shell (main window design, section 7.3).
    /// A setting, never written to a log.
    public var lastDeskCommand: String?

    public init(id: String, name: String, user: String, mainAddress: String,
                homeAddress: String? = nil, homePrefix: Int? = nil, localName: String? = nil,
                hostKey: String, paired: Bool = false,
                mode: ConnectionMode = .mosh, prediction: Prediction = .adaptive,
                projectsFolder: String? = nil, identityFile: String? = nil,
                osVersion: String? = nil, arch: String? = nil,
                lastSeen: Date? = nil, lastKeyAccepted: Date? = nil,
                powerChanges: [String] = [], lastDeskCommand: String? = nil) {
        self.id = id
        self.name = name
        self.user = user
        self.mainAddress = mainAddress
        self.homeAddress = homeAddress
        self.homePrefix = homePrefix
        self.localName = localName
        self.hostKey = hostKey
        self.paired = paired
        self.mode = mode
        self.prediction = prediction
        self.projectsFolder = projectsFolder
        self.identityFile = identityFile
        self.osVersion = osVersion
        self.arch = arch
        self.lastSeen = lastSeen
        self.lastKeyAccepted = lastKeyAccepted
        self.powerChanges = powerChanges
        self.lastDeskCommand = lastDeskCommand
    }

    // Only the five fields a record can't do without are required when decoding. The optional
    // fields and the ones with defaults may be missing, so a later version can add a field and
    // still read a file an older version saved.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        user = try c.decode(String.self, forKey: .user)
        mainAddress = try c.decode(String.self, forKey: .mainAddress)
        hostKey = try c.decode(String.self, forKey: .hostKey)
        homeAddress = try c.decodeIfPresent(String.self, forKey: .homeAddress)
        homePrefix = try c.decodeIfPresent(Int.self, forKey: .homePrefix)
        localName = try c.decodeIfPresent(String.self, forKey: .localName)
        paired = try c.decodeIfPresent(Bool.self, forKey: .paired) ?? false
        mode = try c.decodeIfPresent(ConnectionMode.self, forKey: .mode) ?? .mosh
        prediction = try c.decodeIfPresent(Prediction.self, forKey: .prediction) ?? .adaptive
        projectsFolder = try c.decodeIfPresent(String.self, forKey: .projectsFolder)
        identityFile = try c.decodeIfPresent(String.self, forKey: .identityFile)
        osVersion = try c.decodeIfPresent(String.self, forKey: .osVersion)
        arch = try c.decodeIfPresent(String.self, forKey: .arch)
        lastSeen = try c.decodeIfPresent(Date.self, forKey: .lastSeen)
        lastKeyAccepted = try c.decodeIfPresent(Date.self, forKey: .lastKeyAccepted)
        powerChanges = try c.decodeIfPresent([String].self, forKey: .powerChanges) ?? []
        lastDeskCommand = try c.decodeIfPresent(String.self, forKey: .lastDeskCommand)
    }
}

extension Workhorse {
    /// A short, unique id made from a display name: lower-case a-z and 0-9, joined by single `-`.
    /// An empty result becomes `mac`. A taken id gets `-2`, `-3` and so on.
    public static func makeID(from name: String, existing: [String]) -> String {
        var slug = ""
        var pendingDash = false
        for scalar in name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .lowercased().unicodeScalars {
            if scalar.isASCII, ("a"..."z").contains(Character(scalar)) || ("0"..."9").contains(Character(scalar)) {
                if pendingDash, !slug.isEmpty { slug.append("-") }
                pendingDash = false
                slug.unicodeScalars.append(scalar)
            } else {
                pendingDash = true
            }
        }
        let base = slug.isEmpty ? "mac" : slug
        guard existing.contains(base) else { return base }
        var n = 2
        while existing.contains("\(base)-\(n)") { n += 1 }
        return "\(base)-\(n)"
    }

    /// The name ssh looks the pinned key up under, whichever address is used.
    public var hostKeyAlias: String { "macmosh-" + id }
}
