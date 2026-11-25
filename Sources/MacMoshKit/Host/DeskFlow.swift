import Foundation

/// What the person typed for `desk new`. A missing name or folder makes it the interactive form.
///
/// A new desk comes back after a restart unless asked not to (`reopen`), and is removed for good when
/// its last shell exits unless it is `permanent`. The form that asks questions asks about neither, so
/// a desk made from the menu's `New desk…` comes back and is not permanent. It does ask for a command
/// to start, after the name and the folder, unless `command` was given. With script 0.12.0 or newer it also asks,
/// right after the desk's name, what the first window is called, unless `firstWindow` was given (issue 163).
public struct NewDeskRequest: Sendable, Equatable {
    public var name: String?
    public var folder: String?
    public var reopen: Bool
    public var keep: Bool
    public var permanent: Bool
    public var command: String?
    /// What the first window is called; nil when not given, and then nothing is sent unless the form asks.
    public var firstWindow: FirstWindow?

    public init(name: String? = nil, folder: String? = nil, reopen: Bool = true, keep: Bool = false,
                permanent: Bool = false, command: String? = nil, firstWindow: FirstWindow? = nil) {
        self.name = name
        self.folder = folder
        self.reopen = reopen
        self.keep = keep
        self.permanent = permanent
        self.command = command
        self.firstWindow = firstWindow
    }

    /// Reads `macmosh desk new`'s flags. `--no-reopen` turns reopening off; `--reopen` is still accepted
    /// and means the same as leaving both out. Giving both is a mistake. `--window-name` names the first window.
    public static func fromFlags(name: String?, folder: String?, reopen: Bool, noReopen: Bool, keep: Bool,
                                 permanent: Bool, command: String?, windowName: String? = nil) throws -> NewDeskRequest {
        if reopen && noReopen { throw DeskUsageError.reopenAndNoReopen }
        return NewDeskRequest(name: name, folder: folder, reopen: !noReopen, keep: keep, permanent: permanent,
                              command: command, firstWindow: windowName.map { .named($0) })
    }

    /// The form that asks questions. Everything given in the arguments is taken as it is; it never asks.
    public var isInteractive: Bool { name == nil || folder == nil }
}

/// What `desk name-window` was given for the name: a name as typed (checked by `WindowName` before anything is
/// sent), or `--auto`, to let the window follow its program's name again.
public enum WantedWindowName: Sendable, Equatable {
    case name(String)
    case afterItsProgram
}

/// A mistake in how `macmosh desk new` was typed. The text says what to type instead.
public enum DeskUsageError: Error, Equatable, CustomStringConvertible {
    case reopenAndNoReopen

    public var description: String {
        switch self {
        case .reopenAndNoReopen:
            return "Choose one: a new desk comes back after a restart unless you add --no-reopen. --reopen is the same as leaving both out."
        }
    }
}

/// How a desk command ended. `reason` is what to tell the person when `code` isn't 0; `output` is a
/// list a command prints (the folder names).
public struct DeskResult: Error, Sendable, Equatable {
    public var code: Int32
    public var reason: String?
    public var output: [String]
    /// The desk `newDesk` made, so a command that goes on to open it knows which one.
    public var desk: DeskName?

    public static let success = DeskResult(code: 0, reason: nil, output: [])
    public static func failure(_ reason: String) -> DeskResult { DeskResult(code: 1, reason: reason, output: []) }
}

/// The desk commands as a person meets them: the workhorse must be Ready, the address is the one that
/// answered, and every failure becomes words. The command files only pass things in and print the result.
public struct DeskFlow: Sendable {
    static let tries = 3

    private let commands: HostCommands
    /// Whose words its failures are in: a terminal tab's, which may name a `macmosh` command, or the
    /// MacMosh window's, which never do (`DeskFormat.Wording`).
    private let wording: DeskFormat.Wording

    public init(commands: HostCommands, wording: DeskFormat.Wording = .terminal) {
        self.commands = commands
        self.wording = wording
    }

    // MARK: - The commands

    public func newDesk(_ check: CheckResult, request: NewDeskRequest, ui: Interaction) async -> DeskResult {
        let address: String
        switch Self.gate(check, wording: wording) {
        case .failure(let result): return result
        case .success(let found): address = found
        }
        let w = check.workhorse

        let name: DeskName
        if let given = request.name {
            guard let valid = DeskNameRule.newName(given) else {
                return .failure(DeskNameRule.newNameProblem(given) ?? DeskFormat.nameRule)
            }
            name = valid
        } else {
            do { name = try askName(ui) } catch { return error as? DeskResult ?? .failure("\(error)") }
        }

        // The first window's name (issue 163): checked before anything is sent, and asked right after the desk's
        // name by the form that asks questions, only when the script can take it.
        let version = check.status?.scriptVersion ?? ""
        let canNameFirstWindow = HostInstaller.isAtLeast(version, Self.firstWindowNameNeeds)
        var firstWindow = request.firstWindow
        if let given = firstWindow, given != .afterItsProgram {
            guard canNameFirstWindow else {
                return .failure(DeskFormat.firstWindowNeedsNewerScript(w, version: version, for: wording))
            }
            if case .named(let text) = given, let problem = FirstWindow.problem(text, desk: name.value) {
                return .failure(problem)
            }
        }
        if firstWindow == nil && request.isInteractive && canNameFirstWindow {
            do { firstWindow = try askFirstWindow(name, ui) } catch { return error as? DeskResult ?? .failure("\(error)") }
        }

        let folder: String
        if let given = request.folder {
            folder = given
        } else {
            guard let chosen = await askFolder(w, address: address, ui: ui) else {
                return .failure("No folder was chosen, so MacMosh stopped.")
            }
            folder = chosen
        }

        // The form that asks questions asks a third, unless --command was given (#98).
        var command = request.command
        if request.isInteractive && command == nil { command = askCommand(ui) }

        do {
            try await commands.newDesk(on: w, address: address, name: name, folder: folder,
                                       reopen: request.reopen, keep: request.keep, permanent: request.permanent,
                                       command: command, windowName: firstWindow?.name(for: name))
        } catch {
            return .failure(DeskFormat.message(error, workhorse: w, for: wording))
        }
        DeskFormat.created(name, on: w).forEach(ui.say)
        return DeskResult(code: 0, reason: nil, output: [], desk: name)
    }

    public func removeDesk(_ check: CheckResult, name: String, kill: Bool, ui: Interaction) async -> DeskResult {
        await onDesk(check, name: name) { w, address, desk in
            try await commands.removeDesk(on: w, address: address, name: desk, kill: kill)
            ui.say(kill ? "Removed the desk \(desk.value) and closed its windows."
                        : "Removed the desk \(desk.value). Anything running in it keeps running.")
        }
    }

    static let removeQuestion = "Type yes to remove it: "
    static let yes = "yes"

    /// `desk remove --ask`, what the menu's `Remove <name>…` runs: names the desk and the windows that
    /// will close, from the check's report, and asks once. Only `yes` removes it, and then its windows
    /// close too, with whatever runs in them. A desk the report doesn't have is not asked about.
    public func removeDeskAsking(_ check: CheckResult, name: String, ui: Interaction) async -> DeskResult {
        await onDesk(check, name: name) { w, address, desk in
            let open = check.status?.desks.first { $0.name == desk }
            if open != nil || check.status?.definitions.contains(where: { $0.name == desk }) == true {
                ui.say(DeskFormat.removeSentence(desk, open: open))
            } else {
                throw HostCommandError.noSuchDesk
            }
            let answer = ui.ask(Self.removeQuestion).trimmingCharacters(in: .whitespacesAndNewlines)
            guard answer == Self.yes else { throw DeskResult.failure("Nothing was removed.") }
            try await commands.removeDesk(on: w, address: address, name: desk, kill: true)
            ui.say(open == nil ? "Removed the desk \(desk.value)." : "Removed the desk \(desk.value) and closed its windows.")
        }
    }

    /// With `new` nil it asks for the new name: that is the form the menu's `Rename <name>…` runs.
    /// An empty answer changes nothing.
    public func renameDesk(_ check: CheckResult, from old: String, to new: String?, ui: Interaction) async -> DeskResult {
        await onDesk(check, name: old) { w, address, desk in
            let target: DeskName
            if let new {
                guard let valid = DeskNameRule.newName(new) else {
                    throw DeskResult.failure(DeskNameRule.newNameProblem(new) ?? DeskFormat.nameRule)
                }
                target = valid
            } else {
                target = try askNewName(for: desk, ui)
            }
            try await commands.renameDesk(on: w, address: address, from: desk, to: target)
            ui.say("Renamed \(desk.value) to \(target.value). Tabs that are open on it keep working; their titles may still say \(desk.value).")
        }
    }

    public func newWindow(_ check: CheckResult, desk: String, ui: Interaction) async -> DeskResult {
        await onDesk(check, name: desk) { w, address, desk in
            try await commands.newWindow(on: w, address: address, desk: desk)
            ui.say("Added a window to \(desk.value).")
        }
    }

    // MARK: Naming a window (issue 144)

    /// `window-name` is in the workhorse script from this version on.
    public static let nameWindowNeeds = "0.11.0"

    /// Names one window of a desk, by its id, or lets it follow its program's name again: one call. What isn't
    /// given is asked, which is the form the menu's `Name a window…` runs: with no `window`, the desk's windows
    /// from the check's report, numbered as tmux numbers them, and which one (not asked when the desk has one
    /// window; an empty answer changes nothing); with no name, the name, where an empty answer lets the window
    /// follow its program's name again. A name is sent as typed once it keeps `WindowName`'s rule. Nothing is
    /// asked or sent when the workhorse's script is older than 0.11.0.
    public func nameWindow(_ check: CheckResult, desk: String, window: String?, to wanted: WantedWindowName?,
                           ui: Interaction) async -> DeskResult {
        await onDesk(check, name: desk) { w, address, name in
            let version = check.status?.scriptVersion ?? ""
            guard HostInstaller.isAtLeast(version, Self.nameWindowNeeds) else {
                throw DeskResult.failure(DeskFormat.nameWindowNeedsNewerScript(w, version: version, for: wording))
            }
            if let window, !HostStatus.isWindowId(window) { throw DeskResult.failure(DeskFormat.windowByID) }
            var naming: WindowNaming?
            switch wanted {
            case .name(let text)?:
                guard let valid = WindowName(text) else { throw DeskResult.failure(WindowName.problem(text) ?? WindowName.rule) }
                naming = .named(valid)
            case .afterItsProgram?: naming = .afterItsProgram
            case nil: break
            }
            let windows = check.status?.desks.first { $0.name == name }?.windows.filter { $0.id != nil }
            let id: String
            if let window {
                id = window
            } else {
                guard let windows else { throw HostCommandError.noSuchDesk }
                id = try askWindow(of: name, windows, ui)
            }
            let shown = windows?.first { $0.id == id }
            let label = shown.map { "window \($0.index)" } ?? "window \(id)"
            let chosen = try naming ?? askWindowName(label, now: shown?.name ?? "", ui)
            do {
                try await commands.nameWindow(on: w, address: address, desk: name, window: id, to: chosen)
            } catch WindowNameError.windowClosed {
                throw DeskResult.failure(DeskFormat.windowClosed)
            }
            ui.say(DeskFormat.windowNamed(name, window: label, chosen, on: w))
        }
    }

    static let whichWindow = "Which window? Type its number: "

    /// The desk's windows numbered, and which one, up to three tries. An empty answer stops with nothing changed.
    private func askWindow(of desk: DeskName, _ windows: [HostStatus.Window], _ ui: Interaction) throws -> String {
        guard !windows.isEmpty else { throw DeskResult.failure(DeskFormat.noWindowIDs(desk)) }
        if windows.count == 1, let only = windows[0].id { return only }
        ui.say("The windows of \(desk.value):")
        DeskFormat.numberedWindows(windows).forEach(ui.say)
        for _ in 0..<Self.tries {
            let answer = ui.ask(Self.whichWindow).trimmingCharacters(in: .whitespacesAndNewlines)
            if answer.isEmpty { throw DeskResult.failure(DeskFormat.nothingChanged) }
            if let number = Int(answer) {
                if let id = windows.first(where: { $0.index == number })?.id { return id }
                ui.say("There is no window \(number) in \(desk.value).")
            } else {
                ui.say("Type the number of a window from the list.")
            }
        }
        throw DeskResult.failure("That wasn't a window's number three times, so MacMosh stopped.")
    }

    /// The window's new name, up to three tries; an empty answer is "after its program", and end of input (Ctrl-D,
    /// stdin closed) changes nothing. The answer is not trimmed.
    private func askWindowName(_ label: String, now current: String, _ ui: Interaction) throws -> WindowNaming {
        let which = current.isEmpty ? label : "\(label) (\(current))"
        for _ in 0..<Self.tries {
            guard let answer = ui.askOrEnd("Name for \(which), or Enter alone to let it follow its program's name again: ")
            else { throw DeskResult.failure(DeskFormat.nothingChanged) }
            if answer.isEmpty { return .afterItsProgram }
            if let name = WindowName(answer) { return .named(name) }
            ui.say(WindowName.problem(answer) ?? WindowName.rule)
        }
        throw DeskResult.failure("That wasn't a window name three times, so MacMosh stopped. \(WindowName.rule)")
    }

    /// The names of the folders inside the projects folder, in `output`.
    public func folders(_ check: CheckResult) async -> DeskResult {
        let address: String
        switch Self.gate(check, wording: wording) {
        case .failure(let result): return result
        case .success(let found): address = found
        }
        do {
            let names = try await commands.folders(on: check.workhorse, address: address)
            return DeskResult(code: 0, reason: nil, output: names)
        } catch {
            return .failure(DeskFormat.message(error, workhorse: check.workhorse, for: wording))
        }
    }

    // MARK: - Pieces

    /// A desk command needs a Ready workhorse. Either kind of Ready will do. Anything else stops here,
    /// before any ssh, with the state's headline and hint, in the flow's words (`DeskFormat.notReady`).
    static func gate(_ check: CheckResult, wording: DeskFormat.Wording) -> Result<String, DeskResult> {
        guard case .ready = check.state else { return .failure(.failure(DeskFormat.notReady(check, for: wording))) }
        return .success(check.answeredAt ?? check.workhorse.mainAddress)
    }

    private func onDesk(_ check: CheckResult, name: String,
                        _ body: (Workhorse, String, DeskName) async throws -> Void) async -> DeskResult {
        let address: String
        switch Self.gate(check, wording: wording) {
        case .failure(let result): return result
        case .success(let found): address = found
        }
        guard let desk = DeskName(name) else { return .failure(DeskFormat.nameRule) }
        do {
            try await body(check.workhorse, address, desk)
            return .success
        } catch let stopped as DeskResult {
            return stopped
        } catch {
            return .failure(DeskFormat.message(error, workhorse: check.workhorse, for: wording))
        }
    }

    /// Asks for a desk's new name, up to three tries. An empty answer stops with nothing changed.
    private func askNewName(for desk: DeskName, _ ui: Interaction) throws -> DeskName {
        var problem = DeskFormat.nameRule
        for _ in 0..<Self.tries {
            let answer = ui.ask("New name for \(desk.value): ").trimmingCharacters(in: .whitespacesAndNewlines)
            if answer.isEmpty { throw DeskResult.failure("Nothing was changed.") }
            if let name = DeskNameRule.newName(answer) { return name }
            problem = DeskNameRule.newNameProblem(answer) ?? DeskFormat.nameRule
            ui.say(problem)
        }
        throw Self.gaveUp(problem)
    }

    /// Asks until it gets a valid name, up to three tries. After the third it stops.
    private func askName(_ ui: Interaction) throws -> DeskName {
        var problem = DeskFormat.nameRule
        for _ in 0..<Self.tries {
            let answer = ui.ask("Desk name: ").trimmingCharacters(in: .whitespacesAndNewlines)
            if let name = DeskNameRule.newName(answer) { return name }
            problem = DeskNameRule.newNameProblem(answer) ?? DeskFormat.nameRule
            ui.say(problem)
        }
        throw Self.gaveUp(problem)
    }

    /// Three answers that weren't a desk name: the stop names the rule the last one broke.
    private static func gaveUp(_ problem: String) -> DeskResult {
        .failure("That wasn't a desk name three times, so MacMosh stopped. \(problem)")
    }

    /// `desk-new --window-name` is in the workhorse script from this version on (issue 163).
    public static let firstWindowNameNeeds = "0.12.0"

    static func firstWindowQuestion(_ desk: DeskName) -> String {
        "Name for its first window (Enter for \(desk.value), - to name it after its program): "
    }

    static let noDeskMade = "No desk was made."

    /// The first window's name, up to three tries: Enter alone (or only spaces) is the desk's own name, `-` leaves it
    /// to tmux, which names it after its program, and anything else is a name as typed, checked by
    /// `FirstWindow.problem`. End of input (Ctrl-D, stdin closed) makes nothing.
    private func askFirstWindow(_ desk: DeskName, _ ui: Interaction) throws -> FirstWindow {
        for _ in 0..<Self.tries {
            guard let answer = ui.askOrEnd(Self.firstWindowQuestion(desk)) else { throw DeskResult.failure(Self.noDeskMade) }
            let trimmed = answer.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { return .deskName }
            if trimmed == "-" { return .afterItsProgram }
            if let problem = FirstWindow.problem(answer, desk: desk.value) {
                ui.say(problem)
                continue
            }
            return answer == desk.value ? .deskName : .named(answer)
        }
        throw DeskResult.failure("That wasn't a window name three times, so MacMosh stopped. \(WindowName.rule)")
    }

    static let commandQuestion = "Command to start in it (Enter for none): "

    /// The startup command, sent exactly as typed, or nil for Enter alone (or only spaces). A tab in it
    /// is sent too, and the workhorse refuses it as it refuses one in `--command`.
    private func askCommand(_ ui: Interaction) -> String? {
        let answer = ui.ask(Self.commandQuestion)
        return answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : answer
    }

    /// With a projects folder: its folders as a numbered list, "or type a path". Without one, just a path.
    /// A number picks from the list; anything else is a path, used as typed. nil after three empty or
    /// out-of-range answers.
    private func askFolder(_ w: Workhorse, address: String, ui: Interaction) async -> String? {
        var listed: [String] = []
        let projects = w.projectsFolder ?? ""
        if !projects.isEmpty {
            do {
                listed = try await commands.folders(on: w, address: address)
                if listed.isEmpty { ui.say("There are no folders in \(projects) on \(w.name).") }
            } catch {
                ui.say("Couldn't list the folders in \(projects): \(DeskFormat.message(error, workhorse: w, for: wording))")
            }
        }
        let prompt: String
        if listed.isEmpty {
            prompt = "Folder on \(w.name), a full path or one starting with ~: "
        } else {
            ui.say("Folders in \(projects):")
            DeskFormat.numberedFolders(listed).forEach(ui.say)
            prompt = "Pick a number, or type a path: "
        }
        for _ in 0..<Self.tries {
            let answer = ui.ask(prompt).trimmingCharacters(in: .whitespacesAndNewlines)
            if answer.isEmpty {
                ui.say(listed.isEmpty ? "Type a path." : "Type a number from the list, or a path.")
            } else if !listed.isEmpty, let number = Int(answer) {
                if (1...listed.count).contains(number) { return Self.join(projects, listed[number - 1]) }
                ui.say("There is no number \(number) in the list.")
            } else {
                return answer
            }
        }
        return nil
    }

    /// The projects folder as saved, a slash, the folder's name. A `~` stays for the workhorse to expand.
    static func join(_ projects: String, _ name: String) -> String {
        var base = projects
        while base.hasSuffix("/") { base.removeLast() }
        return base + "/" + name
    }
}
