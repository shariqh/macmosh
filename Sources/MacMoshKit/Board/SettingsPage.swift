import Foundation

/// One setting on the Settings page (main window design, section 7.1 F, issue 157): the terminal, which belongs to
/// this Mac, and the five of a workhorse that `macmosh set` changes.
public enum SettingField: String, Sendable, Equatable, CaseIterable {
    case terminal, name, connection, prediction, projectsFolder, keyFile

    /// `macmosh set`'s key for it; nil for the terminal, which `macmosh settings terminal` sets.
    public var setKey: String? {
        switch self {
        case .terminal: return nil
        case .name: return "name"
        case .connection: return "mode"
        case .prediction: return "prediction"
        case .projectsFolder: return "projects-folder"
        case .keyFile: return "identity"
        }
    }

    /// Whether a save asks for one ordinary check: the connection and the terminal decide whether a desk shows one
    /// line per window (`WindowLinesGate`), which the window and the menu take from the last check.
    public var asksForCheck: Bool { self == .connection || self == .terminal }
}

/// The grey line under a setting after a change: "Saved." and what uses it next, or why nothing was saved.
public struct SettingLine: Sendable, Equatable {
    public var field: SettingField
    public var words: String
    /// Nothing was saved: the words say what was wrong.
    public var isProblem: Bool

    public init(field: SettingField, words: String, isProblem: Bool) {
        self.field = field
        self.words = words
        self.isProblem = isProblem
    }

    /// A small green tick before it (look design 6.9): only a line that says "Saved.", never a refusal.
    public var showsTick: Bool { !isProblem && words.hasPrefix(SettingsWords.savedWord) }
}

/// One choice of a radio group: what it says, and the value `macmosh set` (or `settings terminal`) takes for it.
public struct SettingChoice: Sendable, Equatable, Identifiable {
    public var id: String { value }
    public var title: String
    public var value: String

    public init(title: String, value: String) {
        self.title = title
        self.value = value
    }
}

/// What a change on the page comes to before anything is written.
public enum SettingPlan: Sendable, Equatable {
    /// The same as what is stored: nothing is saved and nothing is logged.
    case unchanged
    /// Why it can't be saved, in one sentence; nothing is saved.
    case refused(String)
    /// `macmosh set <id> <key> <value>`, or for the terminal `macmosh settings terminal <value>` (key "terminal").
    case set(key: String, value: String)
}

/// Every word of the Settings page. The views take their words from here, never from their own text.
public enum SettingsWords {
    public static let heading = "Settings"
    public static let thisMac = "This Mac"
    public static let terminal = "Terminal"
    public static let name = "Name"
    public static let connection = "Connection"
    public static let prediction = "Typing prediction"
    public static let projectsFolder = "Projects folder"
    public static let advanced = "Advanced"
    public static let keyFile = "ssh key file"
    public static let removeMacMosh = "Remove MacMosh from this workhorse…"
    public static let noWorkhorses = "No workhorses yet. Add a Mac… in the sidebar adds one."
    /// Under the heading (issue 160 item 3, look design 7).
    public static let howSaved = "Each change is saved as you make it."
    /// The grey line under Remove MacMosh from this workhorse… (issue 160 item 1, look design 7).
    public static let removeMacMoshHelp = "Opens a terminal tab that lists what goes and asks first."
    /// Under Connection while a workhorse is on Tabs and this Mac opens tabs in Terminal (issue 160 item 2): the tab
    /// itself says "Tabs mode needs iTerm2, and this isn't iTerm2. Opening over mosh instead." (`ConnectRunner`).
    public static let tabsInTerminal = "This Mac opens tabs in Terminal, so Mosh is used instead."
    /// The word every line `saved(_:_:)` gives starts with.
    public static let savedWord = "Saved."

    /// In `WorkhorseSetting.applyTerminal`'s words.
    public static let terminalChoices = [SettingChoice(title: "Pick for me", value: "auto"),
                                         SettingChoice(title: "iTerm2", value: "iterm2"),
                                         SettingChoice(title: "Terminal", value: "terminal")]
    public static let connectionChoices = [SettingChoice(title: "Mosh", value: ConnectionMode.mosh.rawValue),
                                           SettingChoice(title: "Tabs", value: ConnectionMode.tabs.rawValue),
                                           SettingChoice(title: "Plain ssh", value: ConnectionMode.ssh.rawValue)]
    public static let predictionChoices = [SettingChoice(title: "Adaptive", value: Prediction.adaptive.rawValue),
                                           SettingChoice(title: "Always", value: Prediction.always.rawValue),
                                           SettingChoice(title: "Never", value: Prediction.never.rawValue),
                                           SettingChoice(title: "Experimental", value: Prediction.experimental.rawValue)]

    /// What Pick for me picks: `TabOpener.terminal`'s rule (the setting, else iTerm2 when `/Applications/iTerm.app` is
    /// there, else Terminal), and what that is on this Mac now.
    public static func pickForMe(_ app: TerminalApp) -> String {
        "Pick for me opens tabs in iTerm2 when it is in the Applications folder, and in Terminal when it isn't. "
            + "On this Mac that is \(app == .iterm2 ? "iTerm2" : "Terminal")."
    }

    /// The chosen connection's line, from the v1 design's "which one do I use?" table (section 5.4 there): what
    /// you get, what happens when the Wi-Fi drops or the lid closes, and what it needs. Its "Every tmux window" reads
    /// "Every window of a desk" here, the word the window uses (main window design, section 2).
    public static func connectionLine(_ mode: ConnectionMode) -> String {
        let drops = "When the Wi-Fi drops or the lid closes,"
        switch mode {
        case .mosh:
            return "One terminal tab per desk. \(drops) the tab picks up by itself when the network returns. Needs mosh on both Macs."
        case .tabs:
            return "Every window of a desk as a real iTerm2 tab. \(drops) the tabs close; your work keeps running, "
                + "and reconnecting brings the tabs back. Needs iTerm2."
        case .ssh:
            return "One terminal tab per desk. \(drops) the tab ends; your work keeps running. Needs nothing extra."
        }
    }

    /// What typing prediction is, what the chosen value does, and that only Mosh uses it. From mosh 1.4.0's manual
    /// (`--predict`: "adaptive" shows predictions "on slower links and to smooth out network glitches"; "Even on
    /// always, mosh will only show predictions when it is confident") and its `--help` ("experimental: aggressively
    /// echo even when incorrect").
    public static func predictionLine(_ p: Prediction) -> String {
        let what: String
        switch p {
        case .adaptive: what = "Adaptive shows it on slow links and through network glitches."
        case .always: what = "Always shows it on fast links too, once mosh is confident."
        case .never: what = "With Never, you see what you type only after the workhorse answers."
        case .experimental: what = "Experimental shows it even when it may be wrong."
        }
        return "Mosh can show what you type before the workhorse answers. \(what) Only Mosh uses this."
    }

    public static let projectsFolderNotSet = "Not set. New desk has no folders to list until it is."
    public static let keyFileHelp = "Leave it empty for MacMosh's own key, ~/.ssh/macmosh_ed25519."

    /// After a save: "Saved." and what reads it next. `w` is the workhorse as saved (nil for the terminal).
    /// - The terminal: `AppTabs` reads the setting each time it opens a tab.
    /// - The name: the window's board reads the list again at once; the menu is built from the list each check loads.
    /// - Connection and prediction: `macmosh connect`, which every desk's tab runs, reads the saved record when the
    ///   tab starts; prediction goes only into mosh's `--predict` (`ConnectPlanner`).
    /// - The projects folder: New desk reads the saved record when its form opens (and `macmosh desk new` too).
    /// - The key file: each check loads the list, and the window's desk actions use the last check's record.
    public static func saved(_ field: SettingField, _ w: Workhorse?) -> String {
        switch field {
        case .terminal: return "Saved. Used by the next tab MacMosh opens."
        case .name: return "Saved. The menu shows it at its next check."
        case .connection: return "Saved. Used by the next tab you open on a desk."
        case .prediction: return "Saved. Used by the next Mosh tab you open."
        case .projectsFolder:
            return w?.projectsFolder == nil ? "Saved. New desk has no folders to list until it is set." : "Saved. Used by the next New desk."
        case .keyFile:
            guard let w, w.identityFile != nil else { return "Saved. MacMosh's own key is used from the next check on." }
            return "Saved. Used for \(w.name) from the next check on."
        }
    }

    /// The workhorse left the saved list after the page was shown.
    public static func gone(_ name: String) -> String {
        "\(name) is no longer on MacMosh's list, so nothing was saved."
    }

    /// The window's own checks on an ssh key file, beyond `macmosh set` (the agent's call, for review): a typo there
    /// would leave the workhorse "Not paired" at its next check.
    /// The same sentence as New desk's path (issue 160 item 4, look design 7).
    public static let keyFileNotAPath = NewDeskForm.Words.typeAFullPath
    public static func noKeyFile(_ path: String) -> String {
        "There is no file at \(path) on this Mac, so it was not saved."
    }

    // MARK: About, at the end of the page (look design 6.9, look step 5b)

    public static let about = "About"
    public static let appName = "MacMosh"
    /// In neither design: the pull request of look step 5b asks the owner (its alternative: "MIT licence.").
    public static let licence = "Open source under the MIT licence."
    /// The two credit lines the v1 design fixes (v1 design, section 11), word for word.
    public static let creditLines = [
        "Mac and macOS are trademarks of Apple Inc., registered in the U.S. and other countries and regions.",
        "MacMosh is an independent project, not affiliated with Apple or with the mosh project.",
    ]

    /// "Version 0.1.0". In neither design: the pull request of look step 5b asks the owner (its alternative: the
    /// number alone).
    public static func version(_ number: String) -> String { "Version \(number)" }
}

/// What a change on the page saves, with `macmosh set`'s checks (`WorkhorseSetting`): pure, so it is tested.
public enum SettingsRules {
    /// What a field or a choice shows for a workhorse's stored value.
    public static func shown(_ field: SettingField, _ w: Workhorse) -> String {
        switch field {
        case .terminal: return ""
        case .name: return w.name
        case .connection: return w.mode.rawValue
        case .prediction: return w.prediction.rawValue
        case .projectsFolder: return w.projectsFolder ?? ""
        case .keyFile: return w.identityFile ?? ""
        }
    }

    /// The terminal's stored choice in `applyTerminal`'s words.
    public static func terminalValue(_ s: AppSettings) -> String {
        switch s.terminal {
        case .iterm2?: return "iterm2"
        case .appleTerminal?: return "terminal"
        case nil: return "auto"
        }
    }

    /// Whether text typed in a field is what the field showed (`shown`), compared as `plan` compares it with what is
    /// stored: the same after trimming, and for the key file, empty and `default` alike. Then it is no change.
    public static func sameAsShown(_ field: SettingField, typed: String, shown: String) -> Bool {
        func normal(_ text: String) -> String {
            switch field {
            case .name: return text.trimmingCharacters(in: .whitespacesAndNewlines)
            case .projectsFolder: return text.trimmingCharacters(in: .whitespaces)
            case .keyFile:
                let v = text.trimmingCharacters(in: .whitespaces)
                return v == "default" ? "" : v
            case .terminal, .connection, .prediction: return text
            }
        }
        return normal(typed) == normal(shown)
    }

    /// What `typed` saves into `field` of `stored`. Text fields are trimmed of spaces at both ends, as the New desk
    /// form trims its projects folder; the name is trimmed by `WorkhorseSetting` itself. A value equal to what is
    /// stored is `.unchanged`. An empty key file means MacMosh's own key (`identity default`); any other must be a
    /// full path or start with `~`, and a file must be there (`keyFileExists`, after a leading `~` is expanded for the
    /// check only: `~` and `~/` with `home`, `~user/` as ssh's key path is, `expandedForCheck`). What is stored is what `macmosh set` stores for the same value.
    public static func plan(_ field: SettingField, typed: String, stored w: Workhorse,
                            keyFileExists: (String) -> Bool, home: String) -> SettingPlan {
        guard let key = field.setKey else { return .refused("") }
        var value = typed
        switch field {
        case .name:
            if typed.trimmingCharacters(in: .whitespacesAndNewlines) == w.name { return .unchanged }
        case .connection, .prediction, .terminal:
            if typed == shown(field, w) { return .unchanged }
        case .projectsFolder:
            value = typed.trimmingCharacters(in: .whitespaces)
            if value == (w.projectsFolder ?? "") { return .unchanged }
        case .keyFile:
            value = typed.trimmingCharacters(in: .whitespaces)
            if value.isEmpty || value == "default" {
                if w.identityFile == nil || w.identityFile == "" { return .unchanged }
                value = "default"
            } else {
                if value == w.identityFile { return .unchanged }
                guard value.hasPrefix("/") || value.hasPrefix("~") else { return .refused(SettingsWords.keyFileNotAPath) }
                guard keyFileExists(expandedForCheck(value, home: home)) else { return .refused(SettingsWords.noKeyFile(value)) }
            }
        }
        var trial = w
        do { try WorkhorseSetting.apply(key: key, value: value, to: &trial) } catch {
            return .refused("\(error)")
        }
        return .set(key: key, value: value)
    }

    /// The terminal choice, with `macmosh settings terminal`'s check.
    public static func planTerminal(_ value: String, stored: AppSettings) -> SettingPlan {
        var trial = stored
        do { try WorkhorseSetting.applyTerminal(value, to: &trial) } catch { return .refused("\(error)") }
        return trial == stored ? .unchanged : .set(key: "terminal", value: value)
    }

    /// A leading `~` alone, or `~/`, as the home folder; `~user/` as that user's home folder, the way
    /// `KeyManager.identityURL` expands the stored path for ssh; anything else as it is. Apple, NSString
    /// expandingTildeInPath (https://developer.apple.com/documentation/foundation/nsstring/expandingtildeinpath):
    /// "A new string made by expanding the initial component of the receiver, if it begins with "~" or "~user", to
    /// its full path value. Returns a new string matching the receiver if the receiver's initial component can't be
    /// expanded."
    public static func expandedForCheck(_ path: String, home: String) -> String {
        if path == "~" { return home }
        if path.hasPrefix("~/") { return home + path.dropFirst(1) }
        return (path as NSString).expandingTildeInPath
    }
}

/// The Settings page (main window design, section 7.1 F): This Mac's terminal, then one section per saved
/// workhorse in the saved list's order, each with the line of its last change.
public struct SettingsPage: Sendable, Equatable {
    /// The key of This Mac's section among the lines. A workhorse id is lower-case, so it is never this.
    public static let thisMacID = "thisMac"

    public var heading: String
    /// Under the heading: "Each change is saved as you make it."
    public var howSaved = SettingsWords.howSaved
    public var thisMac: ThisMacSettings
    public var workhorses: [WorkhorseSettings]
    /// With no workhorse: "No workhorses yet…", or the store's sentence when the list can't be read.
    public var none: String?
    /// Lines for workhorses no longer on the list, shown at the top: "Den is no longer on MacMosh's list…".
    public var notices: [String]
    /// The About section, last on the page whatever the list holds, also with no workhorse or an unreadable list.
    public var about = AboutSection()

    /// `list` is the saved list (empty when `listProblem` says why it can't be read); `settings` the app's settings
    /// (nil when `settingsProblem` says why); `pickForMe` what Pick for me picks on this Mac now; `lines` the last
    /// change's line by section (`thisMacID` or a workhorse id).
    public init(list: [Workhorse], listProblem: String?, settings: AppSettings?, settingsProblem: String?,
                pickForMe: TerminalApp, lines: [String: SettingLine]) {
        heading = SettingsWords.heading
        thisMac = ThisMacSettings(settings: settings, problem: settingsProblem, pickForMe: pickForMe,
                                  line: lines[Self.thisMacID])
        // Where tabs open: `TabOpener.terminal`'s rule, the setting else Pick for me's; an unreadable file is Pick for me.
        let tabsOpenIn = settings?.terminal ?? pickForMe
        workhorses = list.map { WorkhorseSettings($0, line: lines[$0.id], tabsOpenIn: tabsOpenIn) }
        if list.isEmpty {
            none = listProblem ?? SettingsWords.noWorkhorses
        } else {
            none = nil
        }
        let ids = Set(list.map(\.id))
        notices = lines.filter { $0.key != Self.thisMacID && !ids.contains($0.key) }
            .sorted { $0.key < $1.key }.map(\.value.words)
    }
}

/// This Mac's section: the terminal tabs open in.
public struct ThisMacSettings: Sendable, Equatable {
    public var heading = SettingsWords.thisMac
    public var label = SettingsWords.terminal
    public var choices = SettingsWords.terminalChoices
    /// The stored choice's value; nil when the settings file can't be read.
    public var chosen: String?
    /// What Pick for me picks.
    public var pickLine: String
    /// The last change's line, or the store's sentence when the settings file can't be read.
    public var line: SettingLine?

    init(settings: AppSettings?, problem: String?, pickForMe: TerminalApp, line: SettingLine?) {
        chosen = settings.map(SettingsRules.terminalValue)
        pickLine = SettingsWords.pickForMe(pickForMe)
        if let problem {
            self.line = SettingLine(field: .terminal, words: problem, isProblem: true)
        } else {
            self.line = line
        }
    }
}

/// One workhorse's section: its stored values, the words beside them, its two buttons, and its last change's line.
public struct WorkhorseSettings: Sendable, Equatable, Identifiable {
    public var id: String
    /// Its name, as saved.
    public var heading: String
    public var labels = [SettingsWords.name, SettingsWords.connection, SettingsWords.prediction,
                         SettingsWords.projectsFolder, SettingsWords.advanced, SettingsWords.keyFile]
    public var name: String
    public var connection: String
    public var connectionChoices = SettingsWords.connectionChoices
    /// The one line under the Connection group, for the chosen one.
    public var connectionLine: String
    /// Under that line, only while it is on Tabs and this Mac opens tabs in Terminal: Mosh is used instead.
    public var connectionNote: String?
    public var prediction: String
    public var predictionChoices = SettingsWords.predictionChoices
    public var predictionLine: String
    /// Empty when none is saved.
    public var projectsFolder: String
    /// Empty for MacMosh's own key.
    public var keyFile: String
    public var keyFileHelp = SettingsWords.keyFileHelp
    /// Run the checklist…: the menu's own button, `prepare <id> --pause`.
    public var checklist: BoardButton
    /// Remove MacMosh from this workhorse…: the tab `remove <id>`, which lists what goes and asks first.
    public var remove: BoardButton
    /// The grey line under Remove: what it opens.
    public var removeHelp = SettingsWords.removeMacMoshHelp
    /// The line of its last change.
    public var line: SettingLine?

    init(_ w: Workhorse, line: SettingLine?, tabsOpenIn: TerminalApp) {
        id = w.id
        heading = w.name
        name = w.name
        connection = w.mode.rawValue
        connectionLine = SettingsWords.connectionLine(w.mode)
        connectionNote = w.mode == .tabs && tabsOpenIn == .appleTerminal ? SettingsWords.tabsInTerminal : nil
        prediction = w.prediction.rawValue
        predictionLine = SettingsWords.predictionLine(w.prediction)
        projectsFolder = w.projectsFolder ?? ""
        keyFile = w.identityFile ?? ""
        checklist = BoardButton(ButtonRules.checklist(w.id))
        remove = BoardButton(ButtonRules.removeMacMosh(w.id))
        self.line = line
    }

    /// Advanced opens by itself when the last change was a refused key file, so its sentence is seen: a refusal
    /// can land as the page is left (focus leaving sends the field), and the page opens again with Advanced closed.
    public var opensAdvanced: Bool { line?.field == .keyFile && line?.isProblem == true }

    /// The line under that setting: its last change's, or for an empty projects folder what New desk does then.
    public func under(_ field: SettingField) -> SettingLine? {
        if let line, line.field == field { return line }
        if field == .projectsFolder, projectsFolder.isEmpty {
            return SettingLine(field: .projectsFolder, words: SettingsWords.projectsFolderNotSet, isProblem: false)
        }
        return nil
    }
}
