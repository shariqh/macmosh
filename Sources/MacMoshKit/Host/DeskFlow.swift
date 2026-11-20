import Foundation

/// What the person typed for `desk new`. A missing name or folder makes it the interactive form.
public struct NewDeskRequest: Sendable, Equatable {
    public var name: String?
    public var folder: String?
    public var reopen: Bool
    public var keep: Bool
    public var command: String?

    public init(name: String? = nil, folder: String? = nil, reopen: Bool = false, keep: Bool = false,
                command: String? = nil) {
        self.name = name
        self.folder = folder
        self.reopen = reopen
        self.keep = keep
        self.command = command
    }

    /// The form that asks questions. Everything given in the arguments is taken as it is; it never asks.
    public var isInteractive: Bool { name == nil || folder == nil }
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

    public init(commands: HostCommands) {
        self.commands = commands
    }

    // MARK: - The commands

    public func newDesk(_ check: CheckResult, request: NewDeskRequest, ui: Interaction) async -> DeskResult {
        let address: String
        switch Self.gate(check) {
        case .failure(let result): return result
        case .success(let found): address = found
        }
        let w = check.workhorse

        let name: DeskName
        if let given = request.name {
            guard let valid = DeskName(given) else { return .failure(DeskFormat.nameRule) }
            name = valid
        } else {
            guard let asked = askName(ui) else {
                return .failure("That wasn't a desk name three times, so MacMosh stopped. \(DeskFormat.nameRule)")
            }
            name = asked
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

        do {
            try await commands.newDesk(on: w, address: address, name: name, folder: folder,
                                       reopen: request.reopen, keep: request.keep, command: request.command)
        } catch {
            return .failure(DeskFormat.message(error, workhorse: w))
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

    public func newWindow(_ check: CheckResult, desk: String, ui: Interaction) async -> DeskResult {
        await onDesk(check, name: desk) { w, address, desk in
            try await commands.newWindow(on: w, address: address, desk: desk)
            ui.say("Added a window to \(desk.value).")
        }
    }

    /// The names of the folders inside the projects folder, in `output`.
    public func folders(_ check: CheckResult) async -> DeskResult {
        let address: String
        switch Self.gate(check) {
        case .failure(let result): return result
        case .success(let found): address = found
        }
        do {
            let names = try await commands.folders(on: check.workhorse, address: address)
            return DeskResult(code: 0, reason: nil, output: names)
        } catch {
            return .failure(DeskFormat.message(error, workhorse: check.workhorse))
        }
    }

    // MARK: - Pieces

    /// A desk command needs a Ready workhorse. Either kind of Ready will do. Anything else stops here,
    /// before any ssh, with the state's headline and hint.
    static func gate(_ check: CheckResult) -> Result<String, DeskResult> {
        guard case .ready = check.state else { return .failure(.failure(DeskFormat.notReady(check))) }
        return .success(check.answeredAt ?? check.workhorse.mainAddress)
    }

    private func onDesk(_ check: CheckResult, name: String,
                        _ body: (Workhorse, String, DeskName) async throws -> Void) async -> DeskResult {
        let address: String
        switch Self.gate(check) {
        case .failure(let result): return result
        case .success(let found): address = found
        }
        guard let desk = DeskName(name) else { return .failure(DeskFormat.nameRule) }
        do {
            try await body(check.workhorse, address, desk)
            return .success
        } catch {
            return .failure(DeskFormat.message(error, workhorse: check.workhorse))
        }
    }

    /// Asks until it gets a valid name, up to three tries. nil after the third.
    private func askName(_ ui: Interaction) -> DeskName? {
        for _ in 0..<Self.tries {
            let answer = ui.ask("Desk name: ").trimmingCharacters(in: .whitespacesAndNewlines)
            if let name = DeskName(answer) { return name }
            ui.say(DeskFormat.nameRule)
        }
        return nil
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
                ui.say("Couldn't list the folders in \(projects): \(DeskFormat.message(error, workhorse: w))")
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
