import Combine
import Foundation

/// How one change on the Settings page ended.
public enum SettingOutcome: Sendable, Equatable {
    /// Saved: the grey line says so and what uses it next.
    case saved(SettingLine)
    /// Nothing was saved: the line says why, in one sentence.
    case refused(SettingLine)
    /// The value is what was stored already: nothing was written or logged.
    case unchanged
}

/// Writes one change to the saved files, off the main thread: `macmosh set`'s path for a workhorse setting
/// (`WorkhorseSetting.apply` inside `WorkhorseStore.update`, under the store's lock), and `macmosh settings
/// terminal`'s for the terminal (`applyTerminal`, `loadSettings`, `saveSettings`). Nothing here uses ssh or asks
/// anything.
public struct SettingsWriter: Sendable {
    public let store: WorkhorseStore
    /// The home folder, for a leading `~` in a key file's path when the file is looked for.
    let home: String
    /// Whether there is a file at that full path on this Mac.
    let keyFileExists: @Sendable (String) -> Bool

    public init(store: WorkhorseStore, home: String, keyFileExists: @escaping @Sendable (String) -> Bool) {
        self.store = store
        self.home = home
        self.keyFileExists = keyFileExists
    }

    /// One field of one workhorse. `name` is the workhorse's name as the page showed it, for the sentence when it
    /// has left the list. The value is decided against the record read now (`SettingsRules.plan`); then the store's
    /// `update` reads the record again under the lock and changes only that field, so a field another process or a
    /// background check wrote in between is kept. A refused value writes nothing at all.
    public func save(_ field: SettingField, of id: String, name: String, typed: String) -> SettingOutcome {
        func refused(_ words: String) -> SettingOutcome { .refused(SettingLine(field: field, words: words, isProblem: true)) }
        let current: Workhorse
        do {
            guard let found = try store.load().first(where: { $0.id == id }) else { return refused(SettingsWords.gone(name)) }
            current = found
        } catch {
            return refused(StatusFormat.storeMessage(error))
        }
        let plan = SettingsRules.plan(field, typed: typed, stored: current, keyFileExists: keyFileExists, home: home)
        switch plan {
        case .unchanged:
            return .unchanged
        case .refused(let why):
            return refused(why)
        case .set(let key, let value):
            var failure: Error?
            var after = current
            do {
                try store.update(id: id) { w in
                    do { try WorkhorseSetting.apply(key: key, value: value, to: &w) } catch { failure = error }
                    after = w
                }
            } catch StoreError.notFound {
                return refused(SettingsWords.gone(name))
            } catch {
                return refused(StatusFormat.storeMessage(error))
            }
            if let failure { return refused("\(failure)") }
            return .saved(SettingLine(field: field, words: SettingsWords.saved(field, after), isProblem: false))
        }
    }

    /// The terminal choice: `auto`, `iterm2` or `terminal`.
    public func saveTerminal(_ value: String) -> SettingOutcome {
        func refused(_ words: String) -> SettingOutcome { .refused(SettingLine(field: .terminal, words: words, isProblem: true)) }
        do {
            var settings = try store.loadSettings()
            switch SettingsRules.planTerminal(value, stored: settings) {
            case .unchanged:
                return .unchanged
            case .refused(let why):
                return refused(why)
            case .set:
                try WorkhorseSetting.applyTerminal(value, to: &settings)
                try store.saveSettings(settings)
                return .saved(SettingLine(field: .terminal, words: SettingsWords.saved(.terminal, nil), isProblem: false))
            }
        } catch {
            return refused(StatusFormat.storeMessage(error))
        }
    }
}

/// Runs the Settings page's saves (main window design, section 7.1 F, issue 157): one call per change, each a
/// `SettingsWriter` save off the main thread, then one fixed-words log line (`window action: setting ok` or
/// `failed`; nothing for a value left as it was), the section's line, a fresh read of the saved list and settings,
/// and, after a save, `saved`, which the app uses to have the window's board read the list again, so the sidebar
/// shows a new name at once. After a save of the connection or the terminal, which decide whether a desk shows one
/// line per window (`WindowLinesGate`, from the last check), it also calls `check`, which asks for one ordinary check
/// and returns at once: nothing here waits for a check, and nothing here uses ssh. The menu takes a new name from the
/// list its next check loads. It belongs to the app, like `WindowActionRunner`, so a save started just before the
/// window closes still ends.
@MainActor
public final class SettingsRunner: ObservableObject {
    /// The saved list as last read; empty when it can't be read (`listProblem`).
    @Published public private(set) var list: [Workhorse] = []
    @Published public private(set) var listProblem: String?
    /// The app's settings as last read; nil when the file can't be read (`settingsProblem`).
    @Published public private(set) var settings: AppSettings? = AppSettings()
    @Published public private(set) var settingsProblem: String?
    /// The last change's line, by section (`SettingsPage.thisMacID` or a workhorse id).
    @Published public private(set) var lines: [String: SettingLine] = [:]
    /// What Pick for me picks on this Mac, as last asked.
    @Published public private(set) var pickForMe: TerminalApp = .iterm2
    /// The changes being saved now, as "<section>.<field>". The same field is not saved twice at once: pressing
    /// Return and then leaving the field asks twice for one change.
    @Published public private(set) var saving: Set<String> = []

    private let writer: SettingsWriter
    private let pick: @Sendable () -> TerminalApp
    private let log: @Sendable (String) -> Void
    private let saved: @MainActor @Sendable () async -> Void
    private let check: @MainActor @Sendable () -> Void
    /// Tests only: runs after a read of the files and before it is shown, with the read's number.
    var holdRead: (@MainActor @Sendable (Int) async -> Void)?
    /// The reads started, and the newest one shown: a read that started before one already shown changes nothing,
    /// as in `BoardOnScreen.reloadList`.
    private var reads = 0
    private var shownRead = 0

    /// `store` is the saved list and settings (the real ones, or a sample's stand-in); `home` and `keyFileExists`
    /// check a key file's path; `pickForMe` is `TabOpener.terminal` with no setting; `log` takes `MenuLog`'s lines;
    /// `saved` runs after each save; `check` asks for one check without waiting for it (`SettingField.asksForCheck`).
    public init(store: WorkhorseStore, home: String, keyFileExists: @escaping @Sendable (String) -> Bool,
                pickForMe: @escaping @Sendable () -> TerminalApp,
                log: @escaping @Sendable (String) -> Void = { MenuLog.write($0) },
                saved: @escaping @MainActor @Sendable () async -> Void = {},
                check: @escaping @MainActor @Sendable () -> Void = {}) {
        writer = SettingsWriter(store: store, home: home, keyFileExists: keyFileExists)
        pick = pickForMe
        self.log = log
        self.saved = saved
        self.check = check
    }

    /// The page, from what was last read and the last change of each section.
    public var page: SettingsPage {
        SettingsPage(list: list, listProblem: listProblem, settings: settings, settingsProblem: settingsProblem,
                     pickForMe: pickForMe, lines: lines)
    }

    /// What is stored for that field now, as the page shows it: a field goes back to it after a refusal.
    public func stored(_ field: SettingField, of id: String) -> String {
        list.first { $0.id == id }.map { SettingsRules.shown(field, $0) } ?? ""
    }

    /// Reads the saved list and settings again, off the main thread. `clearingLines`, as when the page comes on
    /// screen again, forgets the "Saved." lines but keeps a refusal under its field, so a value refused as the page
    /// was left is still explained (a line about a workhorse no longer listed goes too). A read that started before
    /// one already shown changes nothing.
    public func reload(clearingLines: Bool = false) async {
        reads &+= 1
        let mine = reads
        let store = writer.store, pick = self.pick
        let read = await Task.detached { () -> (Result<[Workhorse], ReadProblem>, Result<AppSettings, ReadProblem>, TerminalApp) in
            let list: Result<[Workhorse], ReadProblem>
            do { list = .success(try store.load()) } catch { list = .failure(ReadProblem(StatusFormat.storeMessage(error))) }
            let settings: Result<AppSettings, ReadProblem>
            do { settings = .success(try store.loadSettings()) } catch {
                settings = .failure(ReadProblem(StatusFormat.storeMessage(error)))
            }
            return (list, settings, pick())
        }.value
        if let holdRead { await holdRead(mine) }
        guard mine > shownRead else { return }
        shownRead = mine
        switch read.0 {
        case .success(let list):
            self.list = list
            listProblem = nil
        case .failure(let problem):
            list = []
            listProblem = problem.words
        }
        switch read.1 {
        case .success(let settings):
            self.settings = settings
            settingsProblem = nil
        case .failure(let problem):
            settings = nil
            settingsProblem = problem.words
        }
        if pickForMe != read.2 { pickForMe = read.2 }
        if clearingLines {
            let listed = Set(list.map(\.id))
            lines = lines.filter { $0.value.isProblem && ($0.key == SettingsPage.thisMacID || listed.contains($0.key)) }
        }
    }

    /// Saves one field of one workhorse: a choice when it is clicked, a text field when it is left or Return is
    /// pressed. A value equal to the stored one does nothing. `shown` is what a text field showed before the person
    /// typed: text equal to it is no change, whatever the file holds now, so a field passed through without typing
    /// never writes back a value another writer (`macmosh set`) has changed since.
    @discardableResult
    public func save(_ field: SettingField, of id: String, typed: String, shown: String? = nil) async -> SettingOutcome {
        if let shown, SettingsRules.sameAsShown(field, typed: typed, shown: shown) { return .unchanged }
        let key = "\(id).\(field.rawValue)"
        guard !saving.contains(key) else { return .unchanged }
        saving.insert(key)
        defer { saving.remove(key) }
        let name = list.first { $0.id == id }?.name ?? id
        let writer = self.writer
        let outcome = await Task.detached { writer.save(field, of: id, name: name, typed: typed) }.value
        await finish(outcome, section: id, field: field)
        return outcome
    }

    /// Saves the terminal choice, when it is clicked.
    @discardableResult
    public func chooseTerminal(_ value: String) async -> SettingOutcome {
        let key = "\(SettingsPage.thisMacID).\(SettingField.terminal.rawValue)"
        guard !saving.contains(key) else { return .unchanged }
        saving.insert(key)
        defer { saving.remove(key) }
        let writer = self.writer
        let outcome = await Task.detached { writer.saveTerminal(value) }.value
        await finish(outcome, section: SettingsPage.thisMacID, field: .terminal)
        return outcome
    }

    private func finish(_ outcome: SettingOutcome, section: String, field: SettingField) async {
        switch outcome {
        case .unchanged:
            return
        case .saved(let line):
            log(MenuLog.windowSetting(ok: true))
            lines[section] = line
        case .refused(let line):
            log(MenuLog.windowSetting(ok: false))
            lines[section] = line
        }
        await reload()
        if case .saved = outcome {
            await saved()
            if field.asksForCheck { check() }
        }
    }
}

/// A saved file that can't be read, in the menu's words.
struct ReadProblem: Error {
    let words: String
    init(_ words: String) { self.words = words }
}
