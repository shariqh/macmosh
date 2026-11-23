import Foundation

/// The power settings MacMosh can change on a workhorse (design 7.5).
public enum PowerSetting: String, Sendable, CaseIterable {
    case awake, autorestart
    /// Lid-closed mode (`pmset disablesleep`), the only setting with an on and an off (laptops only).
    case lid
}

/// What a person asked for on the command line: a setting and, for `lid`, on or off.
/// The other settings only ever turn on, so `turnOn` is true for them.
public struct PowerRequest: Sendable, Equatable {
    public var setting: PowerSetting
    public var turnOn: Bool

    public init(setting: PowerSetting, turnOn: Bool) {
        self.setting = setting
        self.turnOn = turnOn
    }

    /// Reads `macmosh power <workhorse> <setting> [on|off]`. `lid` needs the third word; the other two refuse it.
    public static func parse(setting: PowerSetting, word: String?) throws -> PowerRequest {
        switch setting {
        case .lid:
            switch word {
            case "on": return PowerRequest(setting: .lid, turnOn: true)
            case "off": return PowerRequest(setting: .lid, turnOn: false)
            default: throw PowerUsageError.lidNeedsOnOrOff
            }
        case .awake, .autorestart:
            if word != nil { throw PowerUsageError.onOffOnlyForLid(setting) }
            return PowerRequest(setting: setting, turnOn: true)
        }
    }
}

/// A mistake in how `macmosh power` was typed. The text says what to type.
public enum PowerUsageError: Error, Equatable, CustomStringConvertible {
    case lidNeedsOnOrOff
    case onOffOnlyForLid(PowerSetting)

    public var description: String {
        switch self {
        case .lidNeedsOnOrOff:
            return "Say whether to turn lid-closed mode on or off: macmosh power <workhorse> lid on, or macmosh power <workhorse> lid off."
        case .onOffOnlyForLid(let setting):
            return "\(setting.rawValue) takes no on or off. Only lid does: macmosh power <workhorse> lid on."
        }
    }
}

/// What will run on the workhorse and what it does, in words for the person who must say yes to it.
public struct PowerPlan: Sendable, Equatable {
    public var command: String
    public var explanation: String
    /// A command this one puts back: once it has run, `Remove` has nothing to list for that earlier command.
    public var undoes: String?

    public init(command: String, explanation: String, undoes: String? = nil) {
        self.command = command
        self.explanation = explanation
        self.undoes = undoes
    }
}

public enum PowerError: Error, Equatable {
    /// The setting doesn't apply to this workhorse; the text says why, in words for a person.
    case notApplicable(String)
}

/// Works out the one `pmset` command for a setting.
///
/// The commands are fixed text. Nothing a user typed or a workhorse reported (a name, a desk, a
/// path) is ever pasted into them: the command runs with `sudo`, so the report only decides whether a
/// setting applies at all.
public enum PowerPlanner {
    static let awakeCommand = "sudo pmset -c sleep 0 womp 1"
    static let autorestartCommand = "sudo pmset -a autorestart 1"
    static let lidOnCommand = "sudo pmset -a disablesleep 1"
    static let lidOffCommand = "sudo pmset -a disablesleep 0"

    static let lidOnWords = "Keeps the Mac running with its lid closed. It must stay plugged in: the setting also stops sleep on battery, so a closed Mac in a bag keeps running until its battery is empty. A closed Mac runs hotter. The setting stays on after a restart until you turn it off."
    static let lidOffWords = "The Mac sleeps again when its lid closes."

    /// `turnOn` matters only for `.lid`; the other settings only turn on.
    public static func plan(_ setting: PowerSetting, turnOn: Bool = true, status: HostStatus) throws -> PowerPlan {
        switch setting {
        case .awake:
            return PowerPlan(command: awakeCommand,
                             explanation: "Keeps the Mac awake while it is on power, and lets it wake for network access.")
        case .autorestart:
            if status.isLaptop {
                throw PowerError.notApplicable("This setting is for desktop Macs. A laptop carries on from its battery.")
            }
            return PowerPlan(command: autorestartCommand,
                             explanation: "Starts the Mac again by itself after a power cut.")
        case .lid:
            if !status.isLaptop {
                throw PowerError.notApplicable("This setting is for laptops. This Mac has no battery, so it has no lid to close.")
            }
            return turnOn
                ? PowerPlan(command: lidOnCommand, explanation: lidOnWords)
                : PowerPlan(command: lidOffCommand, explanation: lidOffWords, undoes: lidOnCommand)
        }
    }

    /// The power values a report carries, for showing after a change: "Sleep on power: 0 · Wake for
    /// network access: 1 · Restart after a power cut: not listed". A value the report doesn't list
    /// reads "not listed" (a laptop has no restart setting). A laptop's line ends with the lid-closed
    /// mode, off when the report doesn't list it (the workhorse leaves the line out until it was first turned on).
    public static func valuesLine(_ status: HostStatus) -> String {
        func value(_ n: Int?) -> String { n.map(String.init) ?? "not listed" }
        var parts = [
            "Sleep on power: \(value(status.power.sleepOnPower))",
            "Wake for network access: \(value(status.power.wakeForNetwork))",
            "Restart after a power cut: \(value(status.power.autoRestart))",
        ]
        if status.isLaptop { parts.append("Lid-closed mode: \(status.power.disableSleep == 1 ? "on" : "off")") }
        return parts.joined(separator: " · ")
    }
}
