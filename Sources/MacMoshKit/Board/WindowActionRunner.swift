import Combine
import Foundation

/// The window's desk actions, in the log's words (main window design, section 7.3), naming a window among them
/// (issue 144).
public enum WindowActionKind: String, Sendable, Equatable {
    case newDesk, rename, remove, nameWindow

    /// What the action's button reads while it runs.
    public var progress: String {
        switch self {
        case .newDesk: return NewDeskForm.Words.making
        case .rename: return RenameForm.Words.renaming
        case .remove: return RemoveConfirmation.removing
        case .nameWindow: return WindowNameForm.Words.naming
        }
    }
}

/// How a window action ended: the result line when it worked, or why it didn't, in the window's words.
public enum WindowActionResult: Sendable, Equatable {
    case done(String)
    case failed(String)
}

/// What is running on one workhorse's page, for `WorkhorsePage`: the desks with an action running and which,
/// whether a New desk is being made, and the desks marked "Updating…" until the check after their action lands.
public struct WindowActivity: Sendable, Equatable {
    public var busy: [String: WindowActionKind]
    public var making: Bool
    /// Desks renamed or removed, or a window of them named, until the check after it lands.
    public var updating: Set<String>
    /// Desks just made, until the check after it lands; each has a row before the check brings it.
    public var arriving: Set<String>

    public init(busy: [String: WindowActionKind] = [:], making: Bool = false, updating: Set<String> = [],
                arriving: Set<String> = []) {
        self.busy = busy
        self.making = making
        self.updating = updating
        self.arriving = arriving
    }

    /// "Updating…", on a row until the check after its action lands.
    public static let updatingWords = "Updating…"
}

/// Runs the MacMosh window's New desk, Rename, Remove and naming a window (issue 144) in this process (main window design, section 7.2),
/// through `DeskFlow` with a `QuietInteraction`, so nothing can wait on a question. Each is one key-only,
/// batch ssh call with its input closed and a 15-second limit (`HostCommands`), to the address that last
/// answered (the refresher's last check). It belongs to the app, not to the window, so an action started just
/// before the window closes still finishes.
///
/// While an action runs, `activity` says so (its button reads "Making…", "Renaming…" or "Removing…"). When it
/// ends, it writes one fixed-words log line, sets the workhorse's result line and the menu's notice through
/// `MenuRefresher.finishWindowAction`, asks for a check, and marks the row "Updating…" until that check has
/// landed. One action per desk at a time, and one New desk per workhorse.
@MainActor
public final class WindowActionRunner: ObservableObject {
    /// By workhorse id: the desks with an action running, and which.
    @Published public private(set) var busy: [String: [String: WindowActionKind]] = [:]
    /// The workhorses with a New desk being made.
    @Published public private(set) var making: Set<String> = []
    /// By workhorse id: the desks marked "Updating…": renamed or removed, and just made.
    @Published public private(set) var updating: [String: Set<String>] = [:]
    @Published public private(set) var arriving: [String: Set<String>] = [:]

    private let refresher: MenuRefresher
    private let flow: DeskFlow
    private let commands: HostCommands
    private let store: WorkhorseStore
    private let menuActions: MenuActionRunner
    private let log: @Sendable (String) -> Void
    /// What follows each action (the tab, the result line, the check), so `idle` can wait for it.
    private var followUps: [UUID: Task<Void, Never>] = [:]

    /// `commands` runs ssh; `paths` names the key, the pinned host keys and the saved list; `menuActions` opens
    /// the new desk's tab, as the menu's line would; `log` takes the lines of `MenuLog`.
    public init(refresher: MenuRefresher, commands: CommandRunner, paths: Paths, menuActions: MenuActionRunner,
                log: @escaping @Sendable (String) -> Void = { MenuLog.write($0) }) {
        self.refresher = refresher
        self.commands = HostCommands(runner: commands, paths: paths)
        flow = DeskFlow(commands: self.commands, wording: .window)
        store = WorkhorseStore(paths: paths)
        self.menuActions = menuActions
        self.log = log
    }

    /// What runs on that workhorse's page now.
    public func activity(_ id: String) -> WindowActivity {
        WindowActivity(busy: busy[id] ?? [:], making: making.contains(id), updating: updating[id] ?? [],
                       arriving: arriving[id] ?? [])
    }

    /// Waits until everything that follows the actions so far has finished. For tests.
    public func idle() async {
        while let next = followUps.values.first {
            await next.value
        }
    }

    // MARK: New desk

    /// A fresh New desk form for that workhorse, from its last check and its saved record; nil when it has
    /// not answered yet or is not on the saved list.
    public func newDeskForm(_ id: String) async -> NewDeskForm? {
        guard let check = refresher.latest[id], let saved = await saved(id) else { return nil }
        return NewDeskForm(check: check, saved: saved)
    }

    /// The folders in the form's projects folder, as the workhorse lists them. The check's own record was read
    /// before any Save in the form, so the folder comes from the form (section 7.5).
    public func folders(for form: NewDeskForm) async -> NewDeskForm.Folders {
        guard let projects = form.projectsFolder else { return .noProjectsFolder }
        guard var check = refresher.latest[form.workhorseID] else { return .failed(Self.noCheck(form.workhorseName)) }
        check.workhorse.projectsFolder = projects
        let result = await flow.folders(check)
        if result.code == 0 { return .listed(result.output) }
        return .failed(result.reason ?? Self.noCheck(form.workhorseName))
    }

    /// Saves the projects folder through `WorkhorseStore.update`, under the store's lock, with the checks of
    /// `macmosh set`. nil when it was saved; otherwise why not. The form trims it (`projectsFolderToSave`).
    public func saveProjectsFolder(_ id: String, _ folder: String) async -> String? {
        let store = self.store
        let value = folder
        return await Task.detached { () -> String? in
            do {
                var problem: String?
                try store.update(id: id) { w in
                    do { try WorkhorseSetting.apply(key: "projects-folder", value: value, to: &w) } catch {
                        problem = "\(error)"
                    }
                }
                return problem
            } catch {
                return StatusFormat.storeMessage(error)
            }
        }.value
    }

    /// Makes the desk the form describes. On success the form's command becomes the next form's default, and,
    /// with "Open it in a tab now", the menu's open action for the new desk runs.
    public func newDesk(_ form: NewDeskForm) async -> WindowActionResult {
        let id = form.workhorseID
        if making.contains(id) { return .failed("A new desk is being made on \(form.workhorseName). Wait for it to finish.") }
        guard let request = form.request, let name = DeskName(form.name) else {
            return .failed(form.problems.first ?? DeskFormat.nameRule)
        }
        guard let check = refresher.latest[id] else { return .failed(Self.noCheck(form.workhorseName)) }
        making.insert(id)
        let result = await flow.newDesk(check, request: request, ui: QuietInteraction())
        making.remove(id)
        log(MenuLog.windowAction(.newDesk, ok: result.code == 0))
        guard result.code == 0 else {
            return failed(.newDesk, id: id, desk: name.value, reason: result.reason, on: check.workhorse)
        }
        let command = form.commandToSave, store = self.store
        await Task.detached { try? store.update(id: id) { $0.lastDeskCommand = command } }.value
        let line = DeskFormat.windowDone(.newDesk, desk: name, to: nil, on: check.workhorse)
        let open = form.openInTab ? ButtonRules.connect(workhorse: id, desk: name.value) : nil
        follow(id, marking: name.value, isNew: true, line: line, open: open, title: "Open \(name.value)")
        return .done(line)
    }

    // MARK: Rename

    /// A Rename form for that desk, from the workhorse's last check; nil when there is none.
    public func renameForm(_ id: String, desk: String) -> RenameForm? {
        refresher.latest[id].map { RenameForm(check: $0, desk: desk) }
    }

    public func rename(_ form: RenameForm) async -> WindowActionResult {
        let id = form.workhorseID, desk = form.desk
        if let refused = startRefused(id, desk) { return refused }
        guard let new = form.newName else { return .failed(form.problem ?? DeskFormat.nameRule) }
        guard let check = refresher.latest[id], let old = DeskName(desk) else { return .failed(Self.noCheck(form.workhorseName)) }
        busy[id, default: [:]][desk] = .rename
        let result = await flow.renameDesk(check, from: desk, to: new.value, ui: QuietInteraction())
        busy[id]?[desk] = nil
        log(MenuLog.windowAction(.rename, ok: result.code == 0))
        guard result.code == 0 else { return failed(.rename, id: id, desk: desk, reason: result.reason, on: check.workhorse) }
        let line = DeskFormat.windowDone(.rename, desk: old, to: new, on: check.workhorse)
        follow(id, marking: desk, line: line)
        return .done(line)
    }

    // MARK: Naming a window (issue 144)

    /// The sheet for that window of that desk, from the workhorse's last check; nil when the check has no such
    /// window or its windows can't be named.
    public func nameWindowForm(_ id: String, desk: String, window: String) -> WindowNameForm? {
        refresher.latest[id].flatMap { WindowNameForm(check: $0, desk: desk, window: window) }
    }

    /// Names the form's window (Name), or lets it follow its program's name again (Use its program's name). The
    /// window is the form's by its id; its number is only in the words.
    public func nameWindow(_ form: WindowNameForm, to naming: WindowNaming) async -> WindowActionResult {
        let id = form.workhorseID, desk = form.desk
        if let refused = startRefused(id, desk) { return refused }
        guard let check = refresher.latest[id], let name = DeskName(desk) else { return .failed(Self.noCheck(form.workhorseName)) }
        let wanted: WantedWindowName
        switch naming {
        case .named(let given): wanted = .name(given.value)
        case .afterItsProgram: wanted = .afterItsProgram
        }
        busy[id, default: [:]][desk] = .nameWindow
        let result = await flow.nameWindow(check, desk: desk, window: form.windowID, to: wanted, ui: QuietInteraction())
        busy[id]?[desk] = nil
        log(MenuLog.windowAction(.nameWindow, ok: result.code == 0))
        guard result.code == 0 else {
            return failed(.nameWindow, id: id, desk: desk, reason: result.reason, on: check.workhorse)
        }
        let line = DeskFormat.windowNamed(name, window: "window \(form.number)", naming, on: check.workhorse)
        follow(id, marking: desk, line: line)
        return .done(line)
    }

    // MARK: Remove

    /// The Remove confirmation for that desk, from the workhorse's last check; nil when the board has no such desk.
    public func removeConfirmation(_ id: String, desk: String) -> RemoveConfirmation? {
        refresher.latest[id].flatMap { RemoveConfirmation(check: $0, desk: desk) }
    }

    /// Removes the desk the confirmation named, closing its windows, as the menu's Remove does after a typed
    /// yes. Like the menu's Remove, it checks the workhorse again first (the button reads "Removing…" while it
    /// does); when that check shows the desk closed, renamed or replaced since the confirmation, nothing is sent.
    /// What changes between that check and the call is caught only by the script's own lookup by name.
    public func remove(_ confirmation: RemoveConfirmation) async -> WindowActionResult {
        let id = confirmation.workhorseID, desk = confirmation.desk
        if let refused = startRefused(id, desk) { return refused }
        busy[id, default: [:]][desk] = .remove
        await checkAndWait()
        guard let check = refresher.latest[id], let name = DeskName(desk), confirmation.stillMatches(check) else {
            busy[id]?[desk] = nil
            log(MenuLog.windowAction(.remove, ok: false))
            refresher.finishWindowAction(id: id, result: DeskFormat.windowFailed(.remove, desk: desk, reason: confirmation.changed))
            return .failed(confirmation.changed)
        }
        let result = await flow.removeDesk(check, name: desk, kill: true, ui: QuietInteraction())
        busy[id]?[desk] = nil
        log(MenuLog.windowAction(.remove, ok: result.code == 0))
        guard result.code == 0 else { return failed(.remove, id: id, desk: desk, reason: result.reason, on: check.workhorse) }
        let line = DeskFormat.windowDone(.remove, desk: name, to: nil, on: check.workhorse)
        follow(id, marking: desk, line: line)
        return .done(line)
    }

    // MARK: Pieces

    private func startRefused(_ id: String, _ desk: String) -> WindowActionResult? {
        busy[id]?[desk] == nil ? nil : .failed("Wait for the action on \(desk) to finish.")
    }

    /// A failed action: its result line and the menu's notice say what did not happen and why, and a check
    /// follows, as after any action. A call that passed the time limit may still have done its work on the
    /// workhorse, so its line claims neither outcome and a renamed or removed desk's row waits for the check.
    private func failed(_ kind: WindowActionKind, id: String, desk: String, reason: String?, on w: Workhorse) -> WindowActionResult {
        let why = reason ?? "It didn't work."
        if why == HostCommands.noAnswer {
            let unsure = DeskFormat.windowUnsure(kind, desk: desk, on: w)
            refresher.finishWindowAction(id: id, result: unsure)
            follow(id, marking: kind == .newDesk ? nil : desk, line: nil)
            return .failed(unsure)
        }
        refresher.finishWindowAction(id: id, result: DeskFormat.windowFailed(kind, desk: desk, reason: why))
        follow(id, marking: nil, line: nil)
        return .failed(why)
    }

    /// What follows an action, in a task of the runner's own: the row marked "Updating…"; the new desk's tab
    /// when asked for, run through the refresher as the menu's line runs; the result line and the notice (with
    /// what the tab said, when it said anything); then a check, and the mark taken off once it has landed.
    private func follow(_ id: String, marking desk: String?, isNew: Bool = false, line: String?, open: MenuAction? = nil,
                        title: String = "") {
        if let desk {
            if isNew { arriving[id, default: []].insert(desk) } else { updating[id, default: []].insert(desk) }
        }
        let key = UUID()
        followUps[key] = Task { [weak self] in
            guard let self else { return }
            if let line {
                var said = line
                if let open {
                    await refresher.perform(open, title: title, from: .window, using: menuActions)
                    if let note = refresher.notice { said += " " + note }
                }
                refresher.finishWindowAction(id: id, result: said)
            }
            await checkAndWait()
            if let desk {
                if isNew {
                    arriving[id]?.remove(desk)
                    if arriving[id]?.isEmpty == true { arriving[id] = nil }
                } else {
                    updating[id]?.remove(desk)
                    if updating[id]?.isEmpty == true { updating[id] = nil }
                }
            }
            followUps[key] = nil
        }
    }

    /// Asks for a check and waits until one that started after this call has ended. A check running now began
    /// before the action ended, so it is the one after it that counts; `MenuRefresher.refresh` runs one more
    /// after a running one when asked. It waits on the count of checks, not on the refresher going quiet,
    /// which a steady stream of checks could hold off.
    /// Apple, Publisher.values (macOS 12.0, https://developer.apple.com/documentation/combine/publisher/values-1dm9r):
    /// "The elements produced by the publisher, as an asynchronous sequence."
    private func checkAndWait() async {
        let target = refresher.checksDone + (refresher.isRefreshing ? 2 : 1)
        await refresher.refresh()
        if refresher.checksDone >= target { return }
        for await done in refresher.$checksDone.values where done >= target { break }
    }

    /// The workhorse's saved record, read off the main thread.
    private func saved(_ id: String) async -> Workhorse? {
        let store = self.store
        return await Task.detached { try? store.load().first { $0.id == id } }.value
    }

    private static func noCheck(_ name: String) -> String {
        "MacMosh hasn't heard from \(name) yet. Wait for its check, then try again."
    }
}
