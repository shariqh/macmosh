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

    /// Who reads a sentence: a terminal tab, where a `macmosh` command can be typed, or the MacMosh
    /// window, where it can't (main window design, section 7.3).
    public enum Wording: Sendable {
        case terminal, window
    }

    /// A failure in plain words, naming the workhorse where that helps.
    public static func message(_ error: Error, workhorse w: Workhorse, for wording: Wording = .terminal) -> String {
        guard let known = error as? HostCommandError else { return "\(error)" }
        return message(known, workhorse: w, for: wording)
    }

    public static func message(_ error: HostCommandError, workhorse w: Workhorse, for wording: Wording = .terminal) -> String {
        guard wording == .window else { return terminalMessage(error, workhorse: w) }
        switch error {
        case .alreadyExists:
            return "\(w.name) already has a desk with that name. Pick another name."
        case .noSuchDesk:
            return "\(w.name) has no desk with that name now."
        case .noProjectsFolder:
            return "No projects folder is set for \(w.name)."
        case .serverDidNotStart:
            return "The desk server on \(w.name) didn't start. Run the checklist on its page to fix it."
        case .badInput, .nobodyLoggedIn:
            return terminalMessage(error, workhorse: w)
        case .failed(_, let message):
            return withoutCommand(message)
        }
    }

    /// The sentences of `message` without any that names a `macmosh` command ("Check it with: macmosh
    /// status"). A message that is nothing but such a sentence is kept as it is.
    static func withoutCommand(_ message: String) -> String {
        var sentences: [String] = []
        var rest = Substring(message)
        while let end = rest.range(of: ". ") {
            sentences.append(String(rest[..<end.lowerBound]) + ".")
            rest = rest[end.upperBound...]
        }
        if !rest.isEmpty { sentences.append(String(rest)) }
        let kept = sentences.filter { !$0.contains("macmosh ") }
        return kept.isEmpty ? message : kept.joined(separator: " ")
    }

    private static func terminalMessage(_ error: HostCommandError, workhorse w: Workhorse) -> String {
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

    /// What removing a desk closes, from the check's report: "This removes the desk website and closes its
    /// 3 windows (claude, zsh, vim), with whatever is running in them." for an open desk (`open`, its session),
    /// "This removes the desk notes. It has no open windows." for a closed one. The terminal's `desk remove
    /// --ask` and the window's Remove confirmation both say it.
    public static func removeSentence(_ name: DeskName, open: HostStatus.Desk?) -> String {
        guard let open else { return "This removes the desk \(name.value). It has no open windows." }
        let count = open.windowCount == 1 ? "1 window" : "\(open.windowCount) windows"
        let names = open.windows.map(\.name).filter { !$0.isEmpty }
        let list = names.isEmpty ? "" : " (" + names.joined(separator: ", ") + ")"
        return "This removes the desk \(name.value) and closes its \(count)\(list), with whatever is running in them."
    }

    /// The window's line after an action worked, for the workhorse's page and the menu's notice:
    /// "Created the desk garden-planner on Attic.", "Renamed api to api-v2 on Attic.", "Removed the desk
    /// website from Attic." `new` is the new name of a rename.
    public static func windowDone(_ kind: WindowActionKind, desk: DeskName, to new: DeskName?, on w: Workhorse) -> String {
        switch kind {
        case .newDesk: return "Created the desk \(desk.value) on \(w.name)."
        case .rename: return "Renamed \(desk.value) to \(new?.value ?? desk.value) on \(w.name)."
        case .remove: return "Removed the desk \(desk.value) from \(w.name)."
        }
    }

    /// The window's line after an action failed: what did not happen, then why.
    public static func windowFailed(_ kind: WindowActionKind, desk: String, reason: String) -> String {
        switch kind {
        case .newDesk: return "The desk \(desk) wasn't made. \(reason)"
        case .rename: return "\(desk) wasn't renamed. \(reason)"
        case .remove: return "\(desk) wasn't removed. \(reason)"
        }
    }

    /// What `desk new` says when it worked.
    public static func created(_ name: DeskName, on w: Workhorse) -> [String] {
        ["Created the desk \(name.value) on \(w.name).",
         "Open it from the menu, or run: macmosh connect \(w.id) \(name.value)"]
    }
}
