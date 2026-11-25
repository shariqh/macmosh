import Foundation

/// The words the desk commands print, and the JSON of `macmosh folders --json`.
public enum DeskFormat {
    public static let nameRule = "A desk name uses letters, digits, - and _ only, up to \(DeskName.maxLength) characters."
    /// A new desk name that starts with `-` (issue #147): the window's forms and the terminal's say it alike.
    public static let noLeadingDash = "A desk name can't start with -."

    /// What to say when the workhorse isn't Ready: its headline and the hint under it, which
    /// says what to do (design 5.2). No desk command goes near a workhorse in this state.
    ///
    /// For a terminal tab, the headline and the hint on two lines; the hint can be "Run: macmosh prepare
    /// attic --fix". For the window, one line with no `macmosh` command (issue #147): the headline as a
    /// sentence, then the hint's sentences that don't name one ("Attic · Desk server is off.").
    public static func notReady(_ r: CheckResult, for wording: Wording = .terminal, now: Date = Date(),
                                timeZone: TimeZone = .current) -> String {
        let hint = StatusFormat.hint(r, now: now, timeZone: timeZone)
        guard wording == .window else {
            return ([StatusFormat.headline(r)] + (hint.map { [$0] } ?? [])).joined(separator: "\n")
        }
        // A command reads "macmosh " with a space, as in `withoutCommand`; the key file's name does not.
        let kept = hint.map(sentences)?.filter { !$0.contains("macmosh ") } ?? []
        return ([StatusFormat.headline(r) + "."] + kept).joined(separator: " ")
            .replacingOccurrences(of: "\n", with: " ")
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
        case .badInput:
            // The script's exit 6. The window's forms check the name, the path's form and the command before
            // they send, so what is left is a folder that isn't there (issue #147).
            return "\(w.name) didn't accept the name or the folder. The folder must exist on \(w.name)."
        case .nobodyLoggedIn:
            return terminalMessage(error, workhorse: w)
        case .failed(_, let message):
            return withoutCommand(message)
        }
    }

    /// The sentences of `message` without any that names a `macmosh` command ("Check it with: macmosh
    /// status"). A message that is nothing but such a sentence is kept as it is.
    static func withoutCommand(_ message: String) -> String {
        let kept = sentences(message).filter { !$0.contains("macmosh ") }
        return kept.isEmpty ? message : kept.joined(separator: " ")
    }

    /// The sentences of `text`, split after each ". ".
    static func sentences(_ text: String) -> [String] {
        var sentences: [String] = []
        var rest = Substring(text)
        while let end = rest.range(of: ". ") {
            sentences.append(String(rest[..<end.lowerBound]) + ".")
            rest = rest[end.upperBound...]
        }
        if !rest.isEmpty { sentences.append(String(rest)) }
        return sentences
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
        case .nameWindow: return "Named a window of \(desk.value) on \(w.name)."   // the runner says which (windowNamed)
        }
    }

    /// The window's line after an action failed: what did not happen, then why.
    public static func windowFailed(_ kind: WindowActionKind, desk: String, reason: String) -> String {
        switch kind {
        case .newDesk: return "The desk \(desk) wasn't made. \(reason)"
        case .rename: return "\(desk) wasn't renamed. \(reason)"
        case .remove: return "\(desk) wasn't removed. \(reason)"
        case .nameWindow: return "The window of \(desk) wasn't named. \(reason)"
        }
    }

    /// The window's line when the workhorse didn't answer within the limit (`HostCommands.noAnswer`). ssh here
    /// was stopped, but the script there may still have finished, so the line claims neither outcome.
    public static func windowUnsure(_ kind: WindowActionKind, desk: String, on w: Workhorse) -> String {
        let seconds = Int(HostCommands.timeLimit.components.seconds)
        let done: String
        switch kind {
        case .newDesk: done = "made"
        case .rename: done = "renamed"
        case .remove: done = "removed"
        case .nameWindow: done = "named"
        }
        return "MacMosh didn't hear back from \(w.name) about \(desk) within \(seconds) seconds. The next check shows whether it was \(done)."
    }

    // MARK: Naming a window (issue 144)

    /// A script older than 0.11.0 has no `window-name`. The terminal's words say how to update it; the window's
    /// don't name a command.
    public static func nameWindowNeedsNewerScript(_ w: Workhorse, version: String, for wording: Wording) -> String {
        let has = version.isEmpty ? "an older one" : version
        let first = "Naming a window needs the workhorse script \(DeskFlow.nameWindowNeeds) or newer, and \(w.name) has \(has)."
        return wording == .window ? first : first + " Update it with: macmosh prepare \(w.id) --fix"
    }

    public static let windowByID = "A window is given by its id, such as @3."
    /// The script's exit code 4 for a window that isn't one of the desk's now, in its own words.
    public static let windowClosed = WindowNameError.closedLine
    public static let nothingChanged = "Nothing changed."

    static func noWindowIDs(_ desk: DeskName) -> String {
        "The workhorse's report doesn't say which windows \(desk.value) has, so MacMosh can't ask which one."
    }

    /// "  0  claude": the number tmux gives the window, then its name, or `(no name)`.
    public static func numberedWindows(_ windows: [HostStatus.Window]) -> [String] {
        windows.map { "  \($0.index)  \($0.name.isEmpty ? "(no name)" : $0.name)" }
    }

    /// What naming a window says when it worked, in the terminal and as the window's result line:
    /// `Named window 2 of website "front end" on Attic.`, `Window 2 of website follows its program's name again on
    /// Attic.` `window` is "window 2", or "window @7" for one the report didn't list.
    public static func windowNamed(_ desk: DeskName, window: String, _ naming: WindowNaming, on w: Workhorse) -> String {
        switch naming {
        case .named(let name):
            return "Named \(window) of \(desk.value) \"\(name.value)\" on \(w.name)."
        case .afterItsProgram:
            return window.prefix(1).uppercased() + window.dropFirst()
                + " of \(desk.value) follows its program's name again on \(w.name)."
        }
    }

    /// What `desk new` says when it worked.
    public static func created(_ name: DeskName, on w: Workhorse) -> [String] {
        ["Created the desk \(name.value) on \(w.name).",
         "Open it from the menu, or run: macmosh connect \(w.id) \(name.value)"]
    }
}
