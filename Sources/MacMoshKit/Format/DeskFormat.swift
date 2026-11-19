import Foundation

/// The words the desk commands print, and the JSON of `macmosh folders --json`.
public enum DeskFormat {
    public static let nameRule = "A desk name uses letters, digits, - and _ only, up to \(DeskName.maxLength) characters."

    /// What to say when the workhorse isn't Ready: its headline and the hint under it, which
    /// says what to do (design 5.2). No desk command goes near a workhorse in this state.
    public static func notReady(_ r: CheckResult, now: Date = Date(), timeZone: TimeZone = .current) -> String {
        var lines = [StatusFormat.headline(r)]
        if let hint = StatusFormat.hint(r, now: now, timeZone: timeZone) { lines.append(hint) }
        return lines.joined(separator: "\n")
    }

    /// A failure in plain words, naming the workhorse where that helps.
    public static func message(_ error: Error, workhorse w: Workhorse) -> String {
        guard let known = error as? HostCommandError else { return "\(error)" }
        return message(known, workhorse: w)
    }

    public static func message(_ error: HostCommandError, workhorse w: Workhorse) -> String {
        switch error {
        case .badInput:
            return "\(w.name) didn't accept that. A desk name uses letters, digits, - and _ only; a folder must exist on \(w.name) and be a full path or start with ~; a startup command can't contain a tab or a new line."
        case .alreadyExists:
            return "\(w.name) already has a desk with that name. Pick another name, or remove it with: macmosh desk remove \(w.id) <name>"
        case .noSuchDesk:
            return "\(w.name) has no desk with that name. See its desks with: macmosh desks \(w.id)"
        case .noProjectsFolder:
            return "No projects folder is set for \(w.name). Set one with: macmosh set \(w.id) projects-folder <path>"
        case .nobodyLoggedIn:
            return "Nobody is logged in at \(w.name)'s screen, so desks can't start. Log in at that Mac first."
        case .serverDidNotStart:
            return "The desk server on \(w.name) didn't start. Run: macmosh prepare \(w.id) --fix"
        case .failed(_, let message):
            return message
        }
    }

    /// "  1  alpha": the number a person types, then the folder.
    public static func numberedFolders(_ names: [String]) -> [String] {
        names.enumerated().map { "  \($0.offset + 1)  \($0.element)" }
    }

    /// For `macmosh folders --json`: an array of names, like `["alpha","beta"]`.
    public static func foldersJSON(_ names: [String]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return String(decoding: try encoder.encode(names), as: UTF8.self)
    }

    /// What `desk new` says when it worked.
    public static func created(_ name: DeskName, on w: Workhorse) -> [String] {
        ["Created the desk \(name.value) on \(w.name).",
         "Open it from the menu, or run: macmosh connect \(w.id) \(name.value)"]
    }
}
