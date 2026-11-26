import Foundation
import Testing
@testable import MacMoshKit

/// Lines written to the log, collected behind a lock.
private final class Lines: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    func add(_ line: String) { lock.withLock { lines.append(line) } }
    var all: [String] { lock.withLock { lines } }
}

/// What the stand-in checks find, changed by a test between checks, and how many checks ran.
private final class Checks: @unchecked Sendable {
    private let lock = NSLock()
    private var status: HostStatus
    private var state: WorkhorseState
    private var count = 0
    init(_ status: HostStatus, state: WorkhorseState = .ready(signIns: true)) {
        self.status = status
        self.state = state
    }
    func set(_ change: (inout HostStatus) -> Void) { lock.withLock { change(&status) } }
    func setState(_ s: WorkhorseState) { lock.withLock { state = s } }
    var done: Int { lock.withLock { count } }
    func gather(_ list: [Workhorse]) -> [Gathered] {
        lock.withLock {
            count += 1
            return list.map { .checked(.sample(state, workhorse: $0, status: status, answeredAt: "192.168.1.20")) }
        }
    }
}

/// A command runner that holds every call until released, so a test can act while one runs.
private final class HeldRunner: CommandRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var made: [[String]] = []
    var calls: [[String]] { lock.withLock { made } }
    var held: Int { lock.withLock { waiting.count } }

    func run(_ executable: String, _ arguments: [String], environment: [String: String],
             stdin: Data?, timeout: Duration) async -> CommandResult {
        await withCheckedContinuation { c in
            lock.withLock {
                made.append([executable] + arguments)
                waiting.append(c)
            }
        }
        return FakeRunner.ok()
    }

    func release() {
        let all = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            defer { waiting = [] }
            return waiting
        }
        all.forEach { $0.resume() }
    }

    /// Waits until `count` calls are held, giving the other tasks turns; false if they never come.
    func waitFor(_ count: Int) async -> Bool {
        for _ in 0..<5_000 {
            if held >= count { return true }
            try? await Task.sleep(for: .milliseconds(2))
        }
        return false
    }
}

private func board() throws -> HostStatus {
    try HostStatus.parse(fixture("status/desks-board.txt"))
}

/// Everything one test needs: Attic saved in a temporary store, a refresher that has checked it once, the
/// stand-in ssh, the tabs, the log, and the runner.
@MainActor private struct Rig {
    let paths: Paths
    let store: WorkhorseStore
    let checks: Checks
    let refresher: MenuRefresher
    let tabs: RecordingTabs
    let lines: Lines
    let runner: WindowActionRunner

    init(ssh: CommandRunner, projects: String? = "~/Development", last: String? = nil,
         state: WorkhorseState = .ready(signIns: true), tabs: RecordingTabs = RecordingTabs()) async throws {
        paths = try temporaryPaths()
        store = WorkhorseStore(paths: paths)
        var attic = Workhorse.sample(id: "attic", name: "Attic", user: "alex", projectsFolder: projects)
        attic.lastDeskCommand = last
        try store.save([attic])
        let checks = Checks(try board(), state: state)
        self.checks = checks
        let lines = Lines()
        self.lines = lines
        let store = self.store
        refresher = MenuRefresher(load: { try store.load() }, gather: { checks.gather($0) }, save: { _ in },
                                  log: { lines.add($0) }, pause: { _ in })
        self.tabs = tabs
        let menuActions = MenuActionRunner(macmoshPath: "/Applications/MacMosh.app/Contents/Helpers/macmosh", tabs: tabs,
                                           runner: FakeRunner { _ in FakeRunner.ok() }, records: scratchTabRecords())
        runner = WindowActionRunner(refresher: refresher, commands: ssh, paths: paths, menuActions: menuActions,
                                    log: { lines.add($0) })
        await refresher.refresh()
    }

    /// A New desk form for garden-planner with `command`, not opening a tab unless asked.
    func form(command: String = "", openInTab: Bool = false) async throws -> NewDeskForm {
        var f = try #require(await runner.newDeskForm("attic"))
        f.folders = .listed(["garden-planner"])
        f.choose("garden-planner")
        f.command = command
        f.openInTab = openInTab
        return f
    }
}

private func ok(_ stdout: String = "") -> FakeRunner { FakeRunner { _ in FakeRunner.ok(stdout) } }

/// The window's desk actions (main window design, sections 7.2 and 7.5): one key-only ssh call each, with
/// nothing that can wait on a question, then a log line, a result line, and a check.
@MainActor @Suite struct WindowActionRunnerTests {
    // MARK: the exact ssh arguments

    @Test func newDeskIsOneKeyOnlyCallWithTheCommandAsOneArgument() async throws {
        let ssh = ok()
        let rig = try await Rig(ssh: ssh)
        let command = #"claude --continue "fix it" $HOME; echo 'done'"#
        let result = await rig.runner.newDesk(try await rig.form(command: command))
        #expect(result == .done("Created the desk garden-planner on Attic."))
        #expect(ssh.calls.count == 1)
        let call = try #require(ssh.calls.first)
        #expect(call.stdin == nil)
        #expect(call.timeout == .seconds(15))
        #expect(call.argv.first == "ssh")
        #expect(call.argv.contains("BatchMode=yes"))
        #expect(call.argv.contains("IdentitiesOnly=yes"))
        // To the address that last answered, not the saved one.
        let dash = try #require(call.argv.firstIndex(of: "--"))
        #expect(call.argv[dash + 1] == "alex@192.168.1.20")
        #expect(call.argv.count == dash + 3)
        #expect(call.argv.last == #"~/.macmosh/macmosh-host desk-new garden-planner '~/Development/garden-planner' --reopen --command 'claude --continue "fix it" $HOME; echo '\''done'\'''"#)
    }

    @Test func theFormsFlagsGoIntoTheArguments() async throws {
        let ssh = ok()
        let rig = try await Rig(ssh: ssh)
        var f = try await rig.form()
        f.comesBack = false
        f.keepClosed = true
        _ = await rig.runner.newDesk(f)
        #expect(ssh.calls.first?.argv.last == "~/.macmosh/macmosh-host desk-new garden-planner '~/Development/garden-planner' --no-reopen --permanent")
    }

    /// With script 0.12.0 the form names the first window (issue 163): after the desk at first, or a name of its own,
    /// or nothing when the box is clear and the field empty. The result line is unchanged.
    @Test func theFirstWindowsNameGoesIntoTheArguments() async throws {
        let ssh = ok()
        let rig = try await Rig(ssh: ssh)
        rig.checks.set { $0.scriptVersion = "0.12.0" }
        await rig.refresher.refresh()
        let ticked = try await rig.form()
        #expect(await rig.runner.newDesk(ticked) == .done("Created the desk garden-planner on Attic."))
        var named = try await rig.form()
        named.windowSameAsDesk = false
        named.windowName = "build logs"
        _ = await rig.runner.newDesk(named)
        var empty = try await rig.form()
        empty.windowSameAsDesk = false
        _ = await rig.runner.newDesk(empty)
        #expect(ssh.calls.map { $0.argv.last } == [
            "~/.macmosh/macmosh-host desk-new garden-planner '~/Development/garden-planner' --reopen --window-name garden-planner",
            "~/.macmosh/macmosh-host desk-new garden-planner '~/Development/garden-planner' --reopen --window-name 'build logs'",
            "~/.macmosh/macmosh-host desk-new garden-planner '~/Development/garden-planner' --reopen",
        ])
    }

    @Test func renameAndRemoveSendTheirArguments() async throws {
        let ssh = ok()
        let rig = try await Rig(ssh: ssh)
        var rename = try #require(rig.runner.renameForm("attic", desk: "api"))
        rename.name = "api-v2"
        #expect(await rig.runner.rename(rename) == .done("Renamed api to api-v2 on Attic."))
        let remove = try #require(rig.runner.removeConfirmation("attic", desk: "website"))
        #expect(await rig.runner.remove(remove) == .done("Removed the desk website from Attic."))
        #expect(ssh.calls.map { $0.argv.last } == [
            "~/.macmosh/macmosh-host desk-rename api api-v2",
            "~/.macmosh/macmosh-host desk-remove website --kill",
        ])
        #expect(ssh.calls.allSatisfy { $0.stdin == nil && $0.timeout == .seconds(15) && $0.argv.contains("BatchMode=yes") })
    }

    // MARK: failures

    @Test func aRefusalIsAPlainSentenceAndTheResultLineSaysSo() async throws {
        let ssh = FakeRunner { _ in FakeRunner.failed(7, stderr: "macmosh-host: the desk garden-planner already exists\n") }
        let rig = try await Rig(ssh: ssh)
        let result = await rig.runner.newDesk(try await rig.form())
        #expect(result == .failed("Attic already has a desk with that name. Pick another name."))
        await rig.runner.idle()
        #expect(rig.refresher.results["attic"] == "The desk garden-planner wasn't made. Attic already has a desk with that name. Pick another name.")
        #expect(rig.refresher.resultKinds["attic"] == .failed)
        #expect(rig.refresher.notice == rig.refresher.results["attic"])
        #expect(rig.lines.all.contains("window action: newDesk failed"))
        #expect(try rig.store.load().first?.lastDeskCommand == nil)
    }

    @Test func aWorkhorseThatIsNotReadyGetsNoSSH() async throws {
        let ssh = ok()
        let rig = try await Rig(ssh: ssh)
        let f = try await rig.form()
        rig.checks.setState(.locked)
        await rig.refresher.refresh()
        guard case .failed(let reason) = await rig.runner.newDesk(f) else {
            Issue.record("a Locked workhorse made a desk")
            return
        }
        #expect(reason.hasPrefix("Attic · Locked"))
        #expect(ssh.calls.isEmpty)
    }

    @Test func aFormWithAProblemSendsNothing() async throws {
        let ssh = ok()
        let rig = try await Rig(ssh: ssh)
        var f = try await rig.form()
        f.setName("website")
        #expect(await rig.runner.newDesk(f) == .failed("Attic already has a desk called website."))
        f.setName("ok")
        f.command = "a\nb"
        #expect(await rig.runner.newDesk(f) == .failed("A command to start can't contain a tab or a new line."))
        #expect(ssh.calls.isEmpty)
    }

    @Test func renameAndRemoveFailuresAreWindowSentences() async throws {
        let ssh = FakeRunner { _ in FakeRunner.failed(4, stderr: "macmosh-host: no such desk: api\n") }
        let rig = try await Rig(ssh: ssh)
        var rename = try #require(rig.runner.renameForm("attic", desk: "api"))
        rename.name = "api-v2"
        #expect(await rig.runner.rename(rename) == .failed("Attic has no desk with that name now."))
        await rig.runner.idle()
        #expect(rig.refresher.results["attic"] == "api wasn't renamed. Attic has no desk with that name now.")
        #expect(rig.refresher.resultKinds["attic"] == .failed)
        #expect(rig.lines.all.contains("window action: rename failed"))
    }

    /// A workhorse that doesn't answer: the 15-second limit's sentence, and the desk free again at once.
    @Test func aCallThatTimesOutSaysSoAndFreesTheDesk() async throws {
        let ssh = FakeRunner { _ in CommandResult(exitCode: -1, stdout: "", stderr: "", timedOut: true) }
        let rig = try await Rig(ssh: ssh)
        var rename = try #require(rig.runner.renameForm("attic", desk: "api"))
        rename.name = "api-v2"
        #expect(await rig.runner.rename(rename)
                == .failed("MacMosh didn't hear back from Attic about api within 15 seconds. The next check shows whether it was renamed."))
        #expect(rig.runner.activity("attic").busy.isEmpty)
        #expect(await rig.runner.newDesk(try await rig.form())
                == .failed("MacMosh didn't hear back from Attic about garden-planner within 15 seconds. The next check shows whether it was made."))
        #expect(!rig.runner.activity("attic").making)
        await rig.runner.idle()
        #expect(rig.lines.all.contains("window action: rename failed") && rig.lines.all.contains("window action: newDesk failed"))
    }

    /// The script on the workhorse may finish after ssh here was stopped at the limit, so the result line and
    /// the notice don't say it didn't happen, and the row waits for the check.
    @Test func aTimedOutCallDoesNotClaimTheActionFailed() async throws {
        let ssh = FakeRunner { _ in CommandResult(exitCode: -1, stdout: "", stderr: "", timedOut: true) }
        let rig = try await Rig(ssh: ssh)
        let remove = try #require(rig.runner.removeConfirmation("attic", desk: "website"))
        let unsure = "MacMosh didn't hear back from Attic about website within 15 seconds. The next check shows whether it was removed."
        #expect(await rig.runner.remove(remove) == .failed(unsure))
        #expect(rig.runner.activity("attic").updating == ["website"])
        await rig.runner.idle()
        #expect(rig.runner.activity("attic").updating.isEmpty)
        #expect(rig.refresher.results["attic"] == unsure)
        // Neither done nor failed: the next check shows which.
        #expect(rig.refresher.resultKinds["attic"] == .unknown)
        #expect(rig.refresher.notice == unsure)
        #expect(rig.lines.all.contains("window action: remove failed"))
        #expect(try rig.store.load().first?.lastDeskCommand == nil)
    }

    // MARK: Remove hits only the desk the confirmation named

    /// The desk changed on the workhorse after the last check and no check has seen it yet: Remove checks
    /// again before it sends anything, as the menu's Remove does.
    @Test func removeChecksAgainBeforeSending() async throws {
        let ssh = ok()
        let rig = try await Rig(ssh: ssh)
        let changed = "website changed after you asked to remove it, so nothing was removed. Look at it again first."
        // Replaced: the same name with a new window.
        let replaced = try #require(rig.runner.removeConfirmation("attic", desk: "website"))
        rig.checks.set { s in
            let i = s.desks.firstIndex { $0.name.value == "website" }!
            s.desks[i].windows = [.init(index: 0, name: "zsh", id: "@40")]
            s.desks[i].windowCount = 1
        }
        let before = rig.checks.done
        #expect(await rig.runner.remove(replaced) == .failed(changed))
        #expect(rig.checks.done > before)
        #expect(ssh.calls.isEmpty)
        #expect(rig.runner.activity("attic").busy.isEmpty)
        #expect(rig.refresher.results["attic"] == "website wasn't removed. " + changed)
        // Gone: no check has seen it go.
        let gone = try #require(rig.runner.removeConfirmation("attic", desk: "website"))
        rig.checks.set { $0.desks.removeAll { $0.name.value == "website" } }
        #expect(await rig.runner.remove(gone) == .failed(changed))
        #expect(ssh.calls.isEmpty)
        #expect(rig.lines.all.filter { $0 == "window action: remove failed" }.count == 2)
    }

    @Test func removeRefusesWhenTheDeskHasGoneSince() async throws {
        let ssh = ok()
        let rig = try await Rig(ssh: ssh)
        let confirmation = try #require(rig.runner.removeConfirmation("attic", desk: "website"))
        rig.checks.set { $0.desks.removeAll { $0.name.value == "website" } }
        await rig.refresher.refresh()
        let result = await rig.runner.remove(confirmation)
        #expect(result == .failed("website changed after you asked to remove it, so nothing was removed. Look at it again first."))
        #expect(ssh.calls.isEmpty)
        #expect(rig.lines.all.contains("window action: remove failed"))
        #expect(rig.refresher.resultKinds["attic"] == .failed)
    }

    @Test func removeRefusesWhenAnotherDeskHasTakenTheName() async throws {
        let ssh = ok()
        let rig = try await Rig(ssh: ssh)
        let confirmation = try #require(rig.runner.removeConfirmation("attic", desk: "website"))
        rig.checks.set { s in
            let i = s.desks.firstIndex { $0.name.value == "website" }!
            s.desks[i].windows = [.init(index: 0, name: "zsh", id: "@40")]
            s.desks[i].windowCount = 1
        }
        await rig.refresher.refresh()
        guard case .failed = await rig.runner.remove(confirmation) else {
            Issue.record("removed a different desk")
            return
        }
        #expect(ssh.calls.isEmpty)
    }

    // MARK: one at a time

    @Test func oneActionPerDeskAndOneNewDeskPerWorkhorse() async throws {
        let ssh = HeldRunner()
        let rig = try await Rig(ssh: ssh)
        var rename = try #require(rig.runner.renameForm("attic", desk: "api"))
        rename.name = "api-v2"
        let first = Task { await rig.runner.rename(rename) }
        #expect(await ssh.waitFor(1))
        #expect(rig.runner.activity("attic").busy == ["api": .rename])
        let remove = try #require(rig.runner.removeConfirmation("attic", desk: "api"))
        #expect(await rig.runner.remove(remove) == .failed("Wait for the action on api to finish."))
        // Another desk is free.
        let other = try #require(rig.runner.removeConfirmation("attic", desk: "website"))
        let second = Task { await rig.runner.remove(other) }
        #expect(await ssh.waitFor(2))
        let form = try await rig.form()
        let made = Task { await rig.runner.newDesk(form) }
        #expect(await ssh.waitFor(3))
        #expect(rig.runner.activity("attic").making)
        #expect(await rig.runner.newDesk(form) == .failed("A new desk is being made on Attic. Wait for it to finish."))
        ssh.release()
        _ = await first.value
        _ = await second.value
        ssh.release()
        _ = await made.value
        await rig.runner.idle()
        #expect(ssh.calls.count == 3)
        #expect(rig.runner.activity("attic") == WindowActivity())
    }

    // MARK: afterwards

    @Test func afterwardsTheLogTheResultLineTheNoticeAndACheck() async throws {
        let rig = try await Rig(ssh: ok())
        let before = rig.checks.done
        let result = await rig.runner.newDesk(try await rig.form(command: "cyolo --continue"))
        #expect(result == .done("Created the desk garden-planner on Attic."))
        // The row says Updating… until the check that follows has landed.
        #expect(rig.runner.activity("attic").arriving == ["garden-planner"])
        await rig.runner.idle()
        #expect(rig.runner.activity("attic").arriving.isEmpty)
        #expect(rig.checks.done > before)
        #expect(rig.refresher.results["attic"] == "Created the desk garden-planner on Attic.")
        #expect(rig.refresher.resultKinds["attic"] == .done)
        #expect(rig.refresher.notice == "Created the desk garden-planner on Attic.")
        #expect(rig.lines.all.contains("window action: newDesk ok"))
        // Fixed words only: no desk name, no command.
        #expect(!rig.lines.all.contains { $0.contains("garden") || $0.contains("cyolo") || $0.contains("Attic") })
    }

    @Test func openItInATabNowRunsTheMenusOpenForTheNewDesk() async throws {
        let rig = try await Rig(ssh: ok())
        _ = await rig.runner.newDesk(try await rig.form(openInTab: true))
        await rig.runner.idle()
        #expect(rig.tabs.opened.map(\.line).count == 1)
        #expect(rig.tabs.opened.first?.line.hasSuffix("connect attic garden-planner") == true)
        #expect(rig.refresher.notice == "Created the desk garden-planner on Attic.")
        #expect(rig.lines.all.contains("menu action: tab connect (window)"))
    }

    /// The desk was made, so the result is done, its tick and all, even when its tab then failed to open; the tab's
    /// sentence follows the result's in the same line, as it does today (the coordinator's choice, pull request 169).
    @Test func aDeskMadeWhoseTabDidNotOpenIsStillDone() async throws {
        let rig = try await Rig(ssh: ok(), tabs: RecordingTabs(failure: LaunchError.failed("iTerm2 is not installed.")))
        let result = await rig.runner.newDesk(try await rig.form(openInTab: true))
        #expect(result == .done("Created the desk garden-planner on Attic."))
        await rig.runner.idle()
        #expect(rig.refresher.results["attic"]
                == "Created the desk garden-planner on Attic. The tab didn't open. iTerm2 is not installed.")
        #expect(rig.refresher.resultKinds["attic"] == .done)
    }

    @Test func theCommandSentIsTheNextFormsDefault() async throws {
        let rig = try await Rig(ssh: ok(), last: "claude")
        #expect(try #require(await rig.runner.newDeskForm("attic")).command == "claude")
        _ = await rig.runner.newDesk(try await rig.form(command: "cyolo --continue"))
        #expect(try rig.store.load().first?.lastDeskCommand == "cyolo --continue")
        #expect(try #require(await rig.runner.newDeskForm("attic")).command == "cyolo --continue")
        _ = await rig.runner.newDesk(try await rig.form(command: ""))
        #expect(try rig.store.load().first?.lastDeskCommand == nil)
        await rig.runner.idle()
    }

    @Test func renameAndRemoveMarkTheirRowUntilTheCheck() async throws {
        let rig = try await Rig(ssh: ok())
        let remove = try #require(rig.runner.removeConfirmation("attic", desk: "website"))
        _ = await rig.runner.remove(remove)
        #expect(rig.runner.activity("attic").updating == ["website"])
        await rig.runner.idle()
        #expect(rig.runner.activity("attic").updating.isEmpty)
        #expect(rig.lines.all.contains("window action: remove ok"))
    }

    // MARK: the folders and the projects folder

    @Test func theFoldersAreListedFromTheSavedProjectsFolder() async throws {
        let ssh = FakeRunner { argv in
            (argv.last ?? "").contains(" folders ") ? FakeRunner.ok("api\ngarden-planner\n") : FakeRunner.ok()
        }
        let rig = try await Rig(ssh: ssh)
        let f = try #require(await rig.runner.newDeskForm("attic"))
        #expect(await rig.runner.folders(for: f) == .listed(["api", "garden-planner"]))
        #expect(ssh.calls.last?.argv.last == "~/.macmosh/macmosh-host folders '~/Development'")
    }

    @Test func aListThatCantBeReadSaysWhy() async throws {
        let ssh = FakeRunner { _ in FakeRunner.failed(255, stderr: "ssh: connect to host 192.168.1.20 port 22: Operation timed out\n") }
        let rig = try await Rig(ssh: ssh)
        let f = try #require(await rig.runner.newDeskForm("attic"))
        guard case .failed(let why) = await rig.runner.folders(for: f) else {
            Issue.record("a failed listing was not a failure")
            return
        }
        #expect(!why.contains("macmosh "))
    }

    @Test func savingTheProjectsFolderFillsTheList() async throws {
        let ssh = FakeRunner { argv in
            (argv.last ?? "").contains(" folders ") ? FakeRunner.ok("garden-planner\n") : FakeRunner.ok()
        }
        let rig = try await Rig(ssh: ssh, projects: nil)
        var f = try #require(await rig.runner.newDeskForm("attic"))
        #expect(f.folders == .noProjectsFolder)
        #expect(await rig.runner.saveProjectsFolder("attic", "~/Code") == nil)
        #expect(try rig.store.load().first?.projectsFolder == "~/Code")
        f.projectsFolderSaved("~/Code")
        #expect(await rig.runner.folders(for: f) == .listed(["garden-planner"]))
        #expect(ssh.calls.last?.argv.last == "~/.macmosh/macmosh-host folders '~/Code'")
        #expect(await rig.runner.saveProjectsFolder("attic", "a\tb") == "The projects folder can't contain a tab or a new line.")
    }
}

/// Naming a window from the window's sheet (issue 144): one key-only ssh call like Rename's, a fixed-words log line,
/// a result line, one action per desk, and a check after it with the desk's row marked until it lands.
@MainActor @Suite struct NameWindowRunnerTests {
    /// The rig with Attic's script at 0.11.0, which names windows; desks-board.txt gives website's windows ids.
    private func rig(_ ssh: CommandRunner) async throws -> Rig {
        let rig = try await Rig(ssh: ssh)
        rig.checks.set { $0.scriptVersion = "0.11.0" }
        await rig.refresher.refresh()
        return rig
    }

    private func form(_ rig: Rig, _ name: String, window: String = "@3") throws -> WindowNameForm {
        var f = try #require(rig.runner.nameWindowForm("attic", desk: "website", window: window))
        f.name = name
        return f
    }

    @Test func theNameIsOneArgumentOfOneKeyOnlyCall() async throws {
        let ssh = ok()
        let r = try await rig(ssh)
        let f = try form(r, "front end")
        #expect(await r.runner.nameWindow(f, to: try #require(f.naming)) == .done("Named window 2 of website \"front end\" on Attic."))
        #expect(await r.runner.nameWindow(f, to: .afterItsProgram) == .done("Window 2 of website follows its program's name again on Attic."))
        #expect(ssh.calls.map { $0.argv.last } == [
            "~/.macmosh/macmosh-host window-name website @3 'front end'",
            "~/.macmosh/macmosh-host window-name website @3 --auto",
        ])
        #expect(ssh.calls.allSatisfy { $0.stdin == nil && $0.timeout == .seconds(15) && $0.argv.contains("BatchMode=yes") })
        let call = try #require(ssh.calls.first)
        let dash = try #require(call.argv.firstIndex(of: "--"))
        #expect(call.argv[dash + 1] == "alex@192.168.1.20")
        #expect(call.argv.count == dash + 3)
        await r.runner.idle()
    }

    @Test func afterwardsTheLogTheResultLineAndACheckWithTheRowMarked() async throws {
        let r = try await rig(ok())
        let before = r.checks.done
        let f = try form(r, "front end")
        #expect(await r.runner.nameWindow(f, to: try #require(f.naming)) == .done("Named window 2 of website \"front end\" on Attic."))
        #expect(r.runner.activity("attic").updating == ["website"])
        await r.runner.idle()
        #expect(r.runner.activity("attic").updating.isEmpty)
        #expect(r.checks.done > before)
        #expect(r.refresher.results["attic"] == "Named window 2 of website \"front end\" on Attic.")
        #expect(r.refresher.resultKinds["attic"] == .done)
        #expect(r.refresher.notice == r.refresher.results["attic"])
        #expect(r.lines.all.contains("window action: nameWindow ok"))
        #expect(!r.lines.all.contains { $0.contains("front") || $0.contains("website") || $0.contains("@3") })
    }

    @Test func aClosedWindowIsAPlainSentence() async throws {
        let ssh = FakeRunner { _ in FakeRunner.failed(4, stderr: "That window has closed.\n") }
        let r = try await rig(ssh)
        let f = try form(r, "api")
        #expect(await r.runner.nameWindow(f, to: try #require(f.naming)) == .failed("That window has closed."))
        await r.runner.idle()
        #expect(r.refresher.results["attic"] == "The window of website wasn't named. That window has closed.")
        #expect(r.refresher.resultKinds["attic"] == .failed)
        #expect(r.lines.all.contains("window action: nameWindow failed"))
    }

    @Test func aTimeoutSaysSoAndTheRowWaitsForTheCheck() async throws {
        let ssh = FakeRunner { _ in CommandResult(exitCode: -1, stdout: "", stderr: "", timedOut: true) }
        let r = try await rig(ssh)
        let unsure = "MacMosh didn't hear back from Attic about website within 15 seconds. The next check shows whether it was named."
        #expect(await r.runner.nameWindow(try form(r, "api"), to: .afterItsProgram) == .failed(unsure))
        #expect(r.runner.activity("attic").busy.isEmpty)
        #expect(r.runner.activity("attic").updating == ["website"])
        await r.runner.idle()
        #expect(r.refresher.results["attic"] == unsure)
        #expect(r.refresher.resultKinds["attic"] == .unknown)
        #expect(r.lines.all.contains("window action: nameWindow failed"))
    }

    @Test func oneActionPerDesk() async throws {
        let ssh = HeldRunner()
        let r = try await rig(ssh)
        let f = try form(r, "api")
        let first = Task { await r.runner.nameWindow(f, to: .afterItsProgram) }
        #expect(await ssh.waitFor(1))
        #expect(r.runner.activity("attic").busy == ["website": .nameWindow])
        #expect(await r.runner.nameWindow(try form(r, "logs", window: "@1"), to: .afterItsProgram)
                == .failed("Wait for the action on website to finish."))
        var rename = try #require(r.runner.renameForm("attic", desk: "website"))
        rename.name = "site"
        #expect(await r.runner.rename(rename) == .failed("Wait for the action on website to finish."))
        ssh.release()
        _ = await first.value
        await r.runner.idle()
        #expect(ssh.calls.count == 1)
        #expect(r.runner.activity("attic") == WindowActivity())
    }

    /// A name reaches the call only as a `WindowName`, so one that breaks the rule can't be sent: the form gives
    /// nothing to send for it, and Name stays off.
    @Test func aNameReachesTheCallOnlyAsAWindowName() async throws {
        let ssh = ok()
        let r = try await rig(ssh)
        let f = try form(r, "-x")
        #expect(f.naming == nil && !f.canName)
        #expect(ssh.calls.isEmpty)
        #expect(await r.runner.nameWindow(f, to: .named(WindowName("api")!)) == .done("Named window 2 of website \"api\" on Attic."))
        #expect(ssh.calls.count == 1)
        await r.runner.idle()
    }

    @Test func thereIsNoFormBefore0_11_0() async throws {
        let r = try await Rig(ssh: ok())
        #expect(r.runner.nameWindowForm("attic", desk: "website", window: "@3") == nil)
        let newer = try await rig(ok())
        #expect(newer.runner.nameWindowForm("attic", desk: "website", window: "@3")?.label == "Name for window 2 (vim)")
        #expect(newer.runner.nameWindowForm("attic", desk: "garden", window: "@3") == nil)
    }
}
