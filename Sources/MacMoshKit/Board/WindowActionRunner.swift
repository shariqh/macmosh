import Combine
import Foundation

/// The window's desk actions, in the log's words (main window design, section 7.3), naming a window among them
/// (issue 144), and Start again and Forget on an ended desk (step 5).
public enum WindowActionKind: String, Sendable, Equatable {
    case newDesk, rename, remove, nameWindow, startAgain, forget

    /// What the action's button reads while it runs.
    public var progress: String {
        switch self {
        case .newDesk: return NewDeskForm.Words.making
        case .rename: return RenameForm.Words.renaming
        case .remove: return RemoveConfirmation.removing
        case .nameWindow: return WindowNameForm.Words.naming
        case .startAgain: return EndedRow.starting
        case .forget: return EndedRow.forgetting
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

/// Runs the MacMosh window's New desk, Rename, Remove, naming a window (issue 144) and Start again on an ended desk
/// (step 5) in this process (main window design, section 7.2),
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
        // Before the call, so a check that lands while it runs doesn't count the old name as ended.
        refresher.expectGone(id: id, desk: desk)
        let result = await flow.renameDesk(check, from: desk, to: new.value, ui: QuietInteraction())
        busy[id]?[desk] = nil
        log(MenuLog.windowAction(.rename, ok: result.code == 0))
        guard result.code == 0 else { return failed(.rename, id: id, desk: desk, reason: result.reason, on: check.workhorse) }
        let line = DeskFormat.windowDone(.rename, desk: old, to: new, on: check.workhorse)
        follow(id, marking: desk, line: line, expecting: desk)
        return .done(line)
    }

    // MARK: Naming a window (issue 144)

    /// The sheet for that window of that desk, from the workhorse's last check; nil when the check has no such
    /// window or its windows can't be named.
    public func nameWindowForm(_ id: String, desk: String, window: String) -> WindowNameForm? {
        refresher.latest[id].flatMap { WindowNameForm(check: $0, desk: desk, window: window) }
    }

    /// Names the form's window (Name), or lets it follow its program's name again (Name it after the program running in it). The
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
            refresher.finishWindowAction(id: id, result: DeskFormat.windowFailed(.remove, desk: desk, reason: confirmation.changed),
                                         kind: .failed)
            return .failed(confirmation.changed)
        }
        refresher.expectGone(id: id, desk: desk)
        let result = await flow.removeDesk(check, name: desk, kill: true, ui: QuietInteraction())
        busy[id]?[desk] = nil
        log(MenuLog.windowAction(.remove, ok: result.code == 0))
        guard result.code == 0 else { return failed(.remove, id: id, desk: desk, reason: result.reason, on: check.workhorse) }
        let line = DeskFormat.windowDone(.remove, desk: name, to: nil, on: check.workhorse)
        follow(id, marking: desk, line: line, expecting: desk)
        return .done(line)
    }

    // MARK: Ended desks (step 5)

    /// Start again, or Start again and keep it (`keepIt`): makes the ended desk again as the report that last showed
    /// it open had it, through one `DeskFlow.newDesk` call: the same name, the folder exactly as the report gave it,
    /// its startup command, its reopen and keep flags, and permanent only with `keepIt`. Nothing is sent when the
    /// name is taken again by the script's rule in the last check, or, with `keepIt`, when the workhorse's script is
    /// older than 0.5.0. A desk open again by the time of the call is refused by the script; that says so in one
    /// line, and nothing open is touched.
    ///
    /// When it worked, it does what New desk does after making a desk: the entry leaves the list, the new row is
    /// marked arriving until the check after it lands, a tab opens on it, and the result line says so. When it
    /// failed, the entry stays with the reason in one line; after a timeout the reason is the unsure one, and the
    /// entry stays until a check shows the desk open.
    public func startAgain(_ id: String, desk: String, keepIt: Bool) async -> WindowActionResult {
        if let refused = startRefused(id, desk) { return refused }
        guard let check = refresher.latest[id] else { return .failed(Self.noCheck(refresher.lastReady[id]?.workhorse.name ?? id)) }
        let w = check.workhorse
        guard let entry = refresher.ended[id]?.first(where: { $0.name == desk }), let name = DeskName(desk) else {
            return .failed("\(desk) is no longer among the ended desks of \(w.name).")
        }
        let taken = DeskNameRule.taken(check)
        if taken.contains(desk), let why = DeskNameRule.problem(desk, taken: taken, workhorse: w.name) {
            return .failed(why)
        }
        let version = check.status?.scriptVersion ?? ""
        if keepIt, case .ready = check.state, !HostInstaller.isAtLeast(version, WorkhorsePage.keepClosedNeeds) {
            return .failed("Start again and keep it needs the workhorse script \(WorkhorsePage.keepClosedNeeds) or newer, "
                           + "and \(w.name) has \(version.isEmpty ? "an older one" : version).")
        }
        busy[id, default: [:]][desk] = .startAgain
        let request = NewDeskRequest(name: desk, folder: entry.folder, reopen: entry.reopen, keep: entry.keep,
                                     permanent: keepIt, command: entry.command)
        let result = await flow.newDesk(check, request: request, ui: QuietInteraction())
        busy[id]?[desk] = nil
        log(MenuLog.windowAction(.startAgain, ok: result.code == 0))
        guard result.code == 0 else {
            var why = result.reason ?? "It didn't work."
            // The script's "already exists": open again since the last check, or taken by a permanent desk.
            if why == DeskFormat.message(HostCommandError.alreadyExists, workhorse: w, for: .window) {
                why = DeskNameRule.problem(desk, taken: [desk], workhorse: w.name) ?? why
            }
            let outcome = failed(.startAgain, id: id, desk: desk, reason: why, on: w)
            if case .failed(let line) = outcome { refresher.endedFailed(id: id, desk: desk, reason: line) }
            return outcome
        }
        refresher.forgetEnded(id: id, desk: desk)
        var line = DeskFormat.windowDone(.startAgain, desk: name, to: nil, on: w)
        if keepIt { line += " " + DeskFormat.keptWhenItExits }
        follow(id, marking: desk, isNew: true, line: line, open: ButtonRules.connect(workhorse: id, desk: desk),
               title: "Open \(desk)")
        return .done(line)
    }

    /// Forget: takes the ended desk off the list. Nothing is sent. Not while an action for that name runs.
    public func forget(_ id: String, desk: String) {
        guard startRefused(id, desk) == nil else { return }
        refresher.forgetEnded(id: id, desk: desk)
        log(MenuLog.windowAction(.forget, ok: true))
    }

    // MARK: Pieces

    private func startRefused(_ id: String, _ desk: String) -> WindowActionResult? {
        busy[id]?[desk] == nil ? nil : .failed("Wait for the action on \(desk) to finish.")
    }

    /// A failed action: its result line and the menu's notice say what did not happen and why, and a check
    /// follows, as after any action. A call that passed the time limit may still have done its work on the
    /// workhorse, so its line claims neither outcome and a renamed or removed desk's row waits for the check.
    ///
    /// A desk the window was removing or renaming keeps its mark for the ended desks (`MenuRefresher.expectGone`)
    /// until that check after a timeout, and loses it at once after any other failure, when nothing was done.
    private func failed(_ kind: WindowActionKind, id: String, desk: String, reason: String?, on w: Workhorse) -> WindowActionResult {
        let why = reason ?? "It didn't work."
        let marked = kind == .rename || kind == .remove ? desk : nil
        if why == HostCommands.noAnswer {
            let unsure = DeskFormat.windowUnsure(kind, desk: desk, on: w)
            // It may have worked there: neither done nor failed until the next check shows which.
            refresher.finishWindowAction(id: id, result: unsure, kind: .unknown)
            // A desk made by New desk or Start again has no row to mark until a check brings it.
            follow(id, marking: kind == .newDesk || kind == .startAgain ? nil : desk, line: nil, expecting: marked)
            return .failed(unsure)
        }
        if let marked { refresher.stopExpecting(id: id, desk: marked) }
        refresher.finishWindowAction(id: id, result: DeskFormat.windowFailed(kind, desk: desk, reason: why), kind: .failed)
        follow(id, marking: nil, line: nil)
        return .failed(why)
    }

    /// What follows an action, in a task of the runner's own: the row marked "Updating…"; the new desk's tab
    /// when asked for, run through the refresher as the menu's line runs; the result line and the notice (with
    /// what the tab said, when it said anything); then a check, and the mark taken off once it has landed.
    /// `expecting` is a desk the window removed or renamed, whose mark for the ended desks is taken back then too.
    private func follow(_ id: String, marking desk: String?, isNew: Bool = false, line: String?, open: MenuAction? = nil,
                        title: String = "", expecting gone: String? = nil) {
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
                refresher.finishWindowAction(id: id, result: said, kind: .done)
            }
            await checkAndWait()
            if let gone { refresher.stopExpecting(id: id, desk: gone) }
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
