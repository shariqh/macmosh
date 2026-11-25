import Foundation

/// The rule the workhorse script uses for a taken desk name (`cmd_desk_new`, and `cmd_desk_rename` while the
/// desk server is up): a name is taken when a desk with that name is open, or a permanent desk holds it. Any
/// other leftover definition with that name is replaced, so it does not count (main window design, 5.2).
public enum DeskNameRule {
    public static func taken(_ check: CheckResult) -> Set<String> {
        let open = (check.status?.desks ?? []).map(\.name.value)
        let permanent = (check.status?.definitions ?? []).filter(\.permanent).map(\.name.value)
        return Set(open + permanent)
    }

    /// Why `name` can't be a new desk's name on that workhorse, or nil when it can: empty, not a desk name,
    /// or taken ("Attic already has a desk called api.").
    public static func problem(_ name: String, taken: Set<String>, workhorse: String) -> String? {
        if name.isEmpty { return "Give the desk a name." }
        guard DeskName(name) != nil else { return DeskFormat.nameRule }
        if taken.contains(name) { return "\(workhorse) already has a desk called \(name)." }
        return nil
    }

    /// A tab or a new line, which the script refuses in a folder or a command (`mm_has_tab_or_newline`).
    static func hasTabOrNewline(_ text: String) -> Bool {
        text.contains { $0 == "\t" || $0.isNewline }
    }
}

/// The window's New desk form (main window design, section 7.5): every rule and every word of it, with no
/// view. The sheet shows its fields, calls its methods as the person types and clicks, and sends `request`
/// through `WindowActionRunner` when `canMake`.
public struct NewDeskForm: Sendable, Equatable {
    /// The form's fixed words.
    public enum Words {
        public static let filter = "Filter"
        public static let hasADesk = "(has a desk)"
        public static let orAPath = "Or a path, full or starting with ~:"
        public static let name = "Name"
        public static let nameHelp = "Letters, digits, - and _ only."
        public static let command = "Command to start"
        public static let commandHelp = "Leave it empty for a plain shell."
        public static let afterARestart = "After a restart"
        public static let comesBack = "Comes back"
        public static let whenItsLastShellExits = "When its last shell exits"
        public static let removeTheDesk = "Remove the desk"
        public static let keepItClosed = "Keep it, closed"
        public static let openInATabNow = "Open it in a tab now"
        public static let cancel = "Cancel"
        public static let makeDesk = "Make desk"
        public static let making = "Making…"
        public static let save = "Save"
        public static let reading = "Reading the folders…"
        /// What the projects folder field holds before he types: the folder the design draws.
        public static let projectsFolderDefault = "~/Development"
    }

    /// The folders of the projects folder, as far as they are known.
    public enum Folders: Sendable, Equatable {
        /// Being read from the workhorse.
        case reading
        /// No projects folder is saved: the form shows the one line that saves one.
        case noProjectsFolder
        case listed([String])
        /// The list can't be read: why, in the window's words. The path field still works.
        case failed(String)
    }

    /// One folder of the list.
    public struct Row: Sendable, Equatable, Identifiable {
        public var id: String { name }
        public var name: String
        /// A desk on the board has this folder.
        public var hasDesk: Bool
        /// "(has a desk)", or nil.
        public var note: String? { hasDesk ? Words.hasADesk : nil }
    }

    public let workhorseID: String
    public let workhorseName: String
    /// The workhorse's user, for `~` in the projects folder: the report has no home folder (section 5.2).
    let user: String
    /// The saved projects folder, as typed (a leading `~` is the workhorse's to expand); nil when none.
    public private(set) var projectsFolder: String?
    /// The full folders of the desks the board shows (`ButtonRules.desks`).
    let deskFolders: Set<String>
    let takenNames: Set<String>
    /// "Keep it, closed" needs script 0.5.0 (section 7.2); with an older one it is hidden and never sent.
    public let canKeepClosed: Bool

    public var folders: Folders
    public var filter = ""
    /// The folder picked from the list, by its name.
    public private(set) var chosen: String?
    public private(set) var typedPath = ""
    public private(set) var name = ""
    /// The name is the folder's until he types one of his own.
    private var nameFollowsFolder = true
    public var command: String
    public var comesBack = true
    public var keepClosed = false
    public var openInTab = true
    /// The projects folder line's field, when none is saved.
    public var projectsFolderDraft = Words.projectsFolderDefault

    /// The form for a workhorse, from its last check (the desks and the script's version) and its saved
    /// record (the projects folder and the last command, which a check doesn't change).
    public init(check: CheckResult, saved: Workhorse) {
        workhorseID = saved.id
        workhorseName = check.workhorse.name
        user = saved.user
        let projects = saved.projectsFolder.flatMap { $0.isEmpty ? nil : $0 }
        projectsFolder = projects
        deskFolders = Set(ButtonRules.desks(check).compactMap { $0.definition.map { Self.normal($0.folder) } })
        takenNames = DeskNameRule.taken(check)
        canKeepClosed = check.status.map { HostInstaller.isAtLeast($0.scriptVersion, "0.5.0") } ?? false
        folders = projects == nil ? .noProjectsFolder : .reading
        command = saved.lastDeskCommand ?? ""
    }

    // MARK: Words

    public var title: String { "New desk on \(workhorseName)" }
    /// "Folder in ~/Development".
    public var folderHeading: String { "Folder in \(projectsFolder ?? "")" }
    /// "Projects folder on Attic:", before the field and Save.
    public var projectsFolderLine: String { "Projects folder on \(workhorseName):" }

    // MARK: Changes

    /// Picks a folder of the list; the name follows it unless he has typed one.
    public mutating func choose(_ folder: String) {
        chosen = folder
        followFolder()
    }

    /// A typed path, which wins over the list while it holds anything.
    public mutating func setTypedPath(_ path: String) {
        typedPath = path
        followFolder()
    }

    /// A name he typed. Once it differs from the folder's, choosing a folder keeps it; cleared, it follows again.
    public mutating func setName(_ text: String) {
        name = text
        nameFollowsFolder = text.isEmpty || text == folderPath.map(Self.name(fromFolder:))
    }

    /// The projects folder was saved: the list is read from it next.
    public mutating func projectsFolderSaved(_ folder: String) {
        projectsFolder = folder.isEmpty ? nil : folder
        folders = projectsFolder == nil ? .noProjectsFolder : .reading
    }

    private mutating func followFolder() {
        if nameFollowsFolder { name = folderPath.map(Self.name(fromFolder:)) ?? "" }
    }

    // MARK: What it shows

    /// The listed folders that hold the filter, in any case, each marked when a desk has it.
    public var rows: [Row] {
        guard case .listed(let names) = folders else { return [] }
        let filter = self.filter.trimmingCharacters(in: .whitespaces)
        return names.filter { filter.isEmpty || $0.localizedCaseInsensitiveContains(filter) }.map { folder in
            Row(name: folder, hasDesk: projectsFolder.map { deskFolders.contains(Self.normal(full(DeskFlow.join($0, folder)))) } ?? false)
        }
    }

    /// The folder the desk gets: the typed path when there is one, else the projects folder and the chosen
    /// name. A `~` stays for the workhorse to expand.
    public var folderPath: String? {
        let typed = typedPath.trimmingCharacters(in: .whitespaces)
        if !typed.isEmpty { return typed }
        guard let chosen, let projectsFolder else { return nil }
        return DeskFlow.join(projectsFolder, chosen)
    }

    public var folderProblem: String? {
        guard let path = folderPath else { return "Pick a folder, or type a path." }
        if DeskNameRule.hasTabOrNewline(path) { return "A path can't contain a tab or a new line." }
        if !(path.hasPrefix("/") || path == "~" || path.hasPrefix("~/")) {
            return "A path is full, starting with /, or starts with ~."
        }
        return nil
    }

    /// Checked as he types: `DeskName`, and the script's own rule for a taken name.
    public var nameProblem: String? {
        DeskNameRule.problem(name, taken: takenNames, workhorse: workhorseName)
    }

    /// The line under the name field: its help line while it is empty or fine, else what is wrong with it.
    public var nameLine: String { nameLineIsProblem ? nameProblem ?? Words.nameHelp : Words.nameHelp }
    public var nameLineIsProblem: Bool { !name.isEmpty && nameProblem != nil }

    /// The line under the command field: its help line, or why it can't be sent.
    public var commandLine: String { commandProblem ?? Words.commandHelp }
    public var commandLineIsProblem: Bool { commandProblem != nil }

    public var commandProblem: String? {
        DeskNameRule.hasTabOrNewline(command) ? "A command to start can't contain a tab or a new line." : nil
    }

    /// Why Make desk is off, in the order of the fields; empty when it is on.
    public var problems: [String] { [folderProblem, nameProblem, commandProblem].compactMap { $0 } }

    public var canMake: Bool { problems.isEmpty }

    /// The command as sent and as saved for the next form: exactly as typed, or nil for a plain shell (empty,
    /// or only spaces, as the terminal form takes it).
    public var commandToSave: String? {
        command.trimmingCharacters(in: .whitespaces).isEmpty ? nil : command
    }

    /// What Make desk sends, or nil while it is off. Keep running is not offered (its help still says "not
    /// active yet"), so it is sent off.
    public var request: NewDeskRequest? {
        guard canMake, let folder = folderPath else { return nil }
        return NewDeskRequest(name: name, folder: folder, reopen: comesBack, keep: false,
                              permanent: canKeepClosed && keepClosed, command: commandToSave)
    }

    // MARK: Pieces

    /// The folder's last part, made to fit a desk name: every character other than a letter, digit, `-` or
    /// `_` becomes `-`, and it is cut at 64. Empty for `~` or `/`.
    public static func name(fromFolder folder: String) -> String {
        var path = Substring(folder)
        while path.hasSuffix("/") { path = path.dropLast() }
        let last = path.split(separator: "/").last.map(String.init) ?? ""
        if last == "~" { return "" }
        let fitted = last.map { c -> Character in
            guard let a = c.asciiValue else { return "-" }
            let ok = (a >= 97 && a <= 122) || (a >= 65 && a <= 90) || (a >= 48 && a <= 57) || c == "-" || c == "_"
            return ok ? c : "-"
        }
        return String(fitted.prefix(DeskName.maxLength))
    }

    /// A folder with `~` as the saved user's home folder, which is what the script saves.
    private func full(_ path: String) -> String {
        if path == "~" { return "/Users/\(user)" }
        if path.hasPrefix("~/") { return "/Users/\(user)/" + path.dropFirst(2) }
        return path
    }

    private static func normal(_ path: String) -> String {
        var p = Substring(path)
        while p.count > 1 && p.hasSuffix("/") { p = p.dropLast() }
        return String(p)
    }
}

/// The window's Rename form (main window design, section 7.2): one field, filled with the old name, checked
/// as the New desk form checks a name.
public struct RenameForm: Sendable, Equatable {
    public enum Words {
        public static let rename = "Rename"
        public static let renaming = "Renaming…"
        public static let cancel = "Cancel"
    }

    public let workhorseID: String
    public let workhorseName: String
    public let desk: String
    let takenNames: Set<String>
    public var name: String

    public init(check: CheckResult, desk: String) {
        workhorseID = check.workhorse.id
        workhorseName = check.workhorse.name
        self.desk = desk
        takenNames = DeskNameRule.taken(check)
        name = desk
    }

    public var title: String { "Rename \(desk)" }
    /// "New name for website".
    public var label: String { "New name for \(desk)" }

    /// Why the name can't be used; nil while it is still the old one, which only keeps Rename off.
    public var problem: String? {
        name == desk ? nil : DeskNameRule.problem(name, taken: takenNames, workhorse: workhorseName)
    }

    public var canRename: Bool { name != desk && problem == nil }

    public var newName: DeskName? { canRename ? DeskName(name) : nil }
}

/// The window's Remove confirmation (main window design, section 7.2): the sentence the terminal's `desk
/// remove --ask` prints, a destructive "Remove <desk>" and Cancel. It remembers which desk it named, so a
/// desk that has closed or been renamed since is not removed (`stillMatches`).
public struct RemoveConfirmation: Sendable, Equatable, Identifiable {
    public static let cancel = "Cancel"
    public static let removing = "Removing…"

    public var id: String { workhorseID + "/" + desk }
    public let workhorseID: String
    public let desk: String
    public let title: String
    public let message: String
    public let button: String
    let identity: Identity

    /// What tells one desk from another with the same name between two checks: open or closed, its windows
    /// (tmux's ids when the report has them, else their count), and its saved folder and permanence.
    struct Identity: Sendable, Equatable {
        var isOpen: Bool
        var windowCount: Int
        var windowIDs: [String]
        var folder: String?
        var permanent: Bool

        init?(_ check: CheckResult, desk: String) {
            guard let line = ButtonRules.desks(check).first(where: { $0.name == desk }) else { return nil }
            isOpen = line.session != nil
            windowCount = line.session?.windowCount ?? 0
            windowIDs = line.session?.windows.compactMap(\.id) ?? []
            folder = line.definition?.folder
            permanent = line.isPermanent
        }
    }

    /// nil when the check's board has no such desk.
    public init?(check: CheckResult, desk: String) {
        guard let identity = Identity(check, desk: desk), let name = DeskName(desk) else { return nil }
        workhorseID = check.workhorse.id
        self.desk = desk
        self.identity = identity
        title = "Remove \(desk)?"
        message = DeskFormat.removeSentence(name, open: check.status?.desks.first { $0.name == name })
        button = "Remove \(desk)"
    }

    /// The desk in `check` is the one this confirmation named.
    public func stillMatches(_ check: CheckResult) -> Bool {
        Identity(check, desk: desk) == identity
    }

    /// Why nothing was removed when it no longer matches.
    public var changed: String {
        "\(desk) changed after you asked to remove it, so nothing was removed. Look at it again first."
    }
}

extension NewDeskForm: Identifiable {
    /// One New desk form per workhorse at a time.
    public var id: String { workhorseID }
}

extension RenameForm: Identifiable {
    public var id: String { workhorseID + "/" + desk }
}
