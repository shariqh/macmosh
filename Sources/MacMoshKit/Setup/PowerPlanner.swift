import Foundation

/// The power settings MacMosh can change on a workhorse (design 7.5).
public enum PowerSetting: String, Sendable, CaseIterable {
    case awake, autorestart
    // Task 25 adds `lid` here.
}

/// What will run on the workhorse and what it does, in words for the person who must say yes to it.
public struct PowerPlan: Sendable, Equatable {
    public var command: String
    public var explanation: String
}

public enum PowerError: Error, Equatable {
    /// The setting doesn't apply to this workhorse; the text says why, in words for a person.
    case notApplicable(String)
}

/// Works out the one `pmset` command for a setting.
///
/// The two commands are fixed text. Nothing a user typed or a workhorse reported (a name, a desk, a
/// path) is ever pasted into them: the command runs with `sudo`, so the report only decides whether a
/// setting applies at all.
public enum PowerPlanner {
    static let awakeCommand = "sudo pmset -c sleep 0 womp 1"
    static let autorestartCommand = "sudo pmset -a autorestart 1"

    public static func plan(_ setting: PowerSetting, status: HostStatus) throws -> PowerPlan {
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
        }
    }

    /// The power values a report carries, for showing after a change: "Sleep on power: 0 · Wake for
    /// network access: 1 · Restart after a power cut: not listed". A value the report doesn't list
    /// reads "not listed" (a laptop has no restart setting).
    public static func valuesLine(_ status: HostStatus) -> String {
        func value(_ n: Int?) -> String { n.map(String.init) ?? "not listed" }
        return [
            "Sleep on power: \(value(status.power.sleepOnPower))",
            "Wake for network access: \(value(status.power.wakeForNetwork))",
            "Restart after a power cut: \(value(status.power.autoRestart))",
        ].joined(separator: " · ")
    }
}
