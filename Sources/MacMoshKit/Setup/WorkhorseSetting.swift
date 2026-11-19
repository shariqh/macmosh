import Foundation

/// A setting that `macmosh set` can't accept, with the words for it. The message lists what is allowed.
public enum SettingError: Error, Equatable, CustomStringConvertible {
    case unknownKey(String)
    case badValue(key: String, message: String)

    public var description: String {
        switch self {
        case .unknownKey(let key):
            return "\"\(key)\" isn't a setting. You can set: \(WorkhorseSetting.keys.joined(separator: ", "))."
        case .badValue(_, let message):
            return message
        }
    }
}

/// `macmosh set <workhorse> <key> <value>`: one change to a workhorse's settings, as a pure function.
public enum WorkhorseSetting {
    public static let keys = ["name", "mode", "prediction", "projects-folder", "identity"]

    /// Changes one field of `w`. Nothing is saved here. Throws `SettingError` and leaves `w` as it was
    /// when the key or the value isn't accepted.
    public static func apply(key: String, value: String, to w: inout Workhorse) throws {
        switch key {
        case "name":
            let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else {
                throw SettingError.badValue(key: key, message: "The name can't be empty.")
            }
            // A name is printed on one line of the menu and the list.
            guard !name.contains(where: { $0.isNewline || $0 == "\t" }) else {
                throw SettingError.badValue(key: key, message: "The name can't contain a tab or a new line.")
            }
            w.name = name
        case "mode":
            guard let mode = ConnectionMode(rawValue: value) else {
                throw SettingError.badValue(key: key, message: notAllowed(value, "mode", ConnectionMode.allCases.map(\.rawValue)))
            }
            w.mode = mode
        case "prediction":
            guard let prediction = Prediction(rawValue: value) else {
                throw SettingError.badValue(key: key, message: notAllowed(value, "prediction", Prediction.allCases.map(\.rawValue)))
            }
            w.prediction = prediction
        case "projects-folder":
            // Stored as typed: a leading `~` is expanded on the workhorse, which knows its own home folder.
            guard !value.contains(where: { $0.isNewline || $0 == "\t" }) else {
                throw SettingError.badValue(key: key, message: "The projects folder can't contain a tab or a new line.")
            }
            w.projectsFolder = value.isEmpty ? nil : value
        case "identity":
            guard !value.isEmpty else {
                throw SettingError.badValue(key: key,
                                            message: "identity needs the path of an ssh key file, or the word default for MacMosh's own key.")
            }
            w.identityFile = value == "default" ? nil : value
        default:
            throw SettingError.unknownKey(key)
        }
    }

    /// The one line `macmosh set` prints after a change, for example `mode: tabs`.
    public static func describe(key: String, _ w: Workhorse) -> String {
        switch key {
        case "name": return "name: \(w.name)"
        case "mode": return "mode: \(w.mode.rawValue)"
        case "prediction": return "prediction: \(w.prediction.rawValue)"
        case "projects-folder": return "projects-folder: \(w.projectsFolder ?? "not set")"
        case "identity": return "identity: \(w.identityFile ?? "default (MacMosh's own key)")"
        default: return key
        }
    }

    private static func notAllowed(_ value: String, _ what: String, _ allowed: [String]) -> String {
        "\"\(value)\" isn't a \(what). Allowed: \(allowed.joined(separator: ", "))."
    }

    // MARK: The terminal

    public static let terminalChoices = ["iterm2", "terminal", "auto"]

    /// `macmosh settings terminal <iterm2|terminal|auto>`. `auto` clears the choice.
    public static func applyTerminal(_ value: String, to settings: inout AppSettings) throws {
        switch value {
        case "iterm2": settings.terminal = .iterm2
        case "terminal": settings.terminal = .appleTerminal
        case "auto": settings.terminal = nil
        default:
            throw SettingError.badValue(key: "terminal",
                                        message: notAllowed(value, "terminal", terminalChoices))
        }
    }

    public static func describeTerminal(_ settings: AppSettings) -> String {
        switch settings.terminal {
        case .iterm2?: return "terminal: iterm2"
        case .appleTerminal?: return "terminal: terminal"
        case nil: return "terminal: auto"
        }
    }
}
