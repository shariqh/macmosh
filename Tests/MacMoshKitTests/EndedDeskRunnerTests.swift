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

private let recipesFolder = "/Users/alex/Development/my recipes"
private let recipesCommand = #"claude --continue "fix it" $HOME; echo 'done'"#

/// Attic's desks as the stand-in checks report them (script `version`), changed by a test between checks.
private final class Desks: @unchecked Sendable {
    private let lock = NSLock()
    /// name, open, reopen, keep, permanent, folder, command
    private var all: [(String, Bool, Bool, Bool, Bool, String, String)] = [
        ("api", true, true, false, false, "/Users/alex/Development/api", ""),
        ("recipes", true, false, true, false, recipesFolder, recipesCommand),
        ("garden", true, true, false, false, "/Users/alex/Development/garden", "claude"),
        ("blog", true, true, false, false, "/Users/alex/Development/blog", ""),
    ]
    private var version: String
    private var state: WorkhorseState = .ready(signIns: true)
    init(version: String) { self.version = version }

    func close(_ names: Set<String>) { lock.withLock { for i in all.indices where names.contains(all[i].0) { all[i].1 = false } } }
    func open(_ name: String, permanent: Bool = false) {
        lock.withLock {
            if let i = all.firstIndex(where: { $0.0 == name }) { all[i].1 = true; all[i].4 = permanent }
        }
    }
    func makePermanentClosed(_ name: String) {
        lock.withLock { if let i = all.firstIndex(where: { $0.0 == name }) { all[i].1 = false; all[i].4 = true } }
    }
    func setState(_ s: WorkhorseState) { lock.withLock { state = s } }
    func add(_ name: String, folder: String) { lock.withLock { all.append((name, true, true, false, false, folder, "")) } }

    func gather(_ list: [Workhorse]) -> [Gathered] {
        lock.withLock {
            var lines = ["macmosh-host\t1\t\(version)", "console\talex", "server\tup", "signins\tok", "agent\tinstalled"]
            for d in all where d.1 { lines += ["desk\t\(d.0)\t1\t0", "window\t\(d.0)\t0\tzsh"] }
            for d in all {
                lines.append("def\t\(d.0)\t\(d.2 ? 1 : 0)\t\(d.3 ? 1 : 0)\t\(d.4 ? 1 : 0)\t\(d.5)\t\(d.6)")
            }
            let status = try? HostStatus.parse((lines + ["end"]).joined(separator: "\n") + "\n")
            return list.map { .checked(.sample(state, workhorse: $0, status: status, answeredAt: "192.168.1.20", checkedAt: Date())) }
        }
    }
}

/// Attic saved in a temporary store, a refresher whose checks read `desks`, and the runner. Its first check sees
/// recipes, garden and blog open; its second, those three gone, and its third the same, so they are ended (garden
/// and blog have reopen, so they count one check later).
@MainActor private struct Rig {
    let store: WorkhorseStore
    let desks: Desks
    let refresher: MenuRefresher
    let tabs: RecordingTabs
    let lines: Lines
    let runner: WindowActionRunner

    init(ssh: CommandRunner, version: String = "0.11.0", desks: Desks? = nil) async throws {
        let paths = try temporaryPaths()
        store = WorkhorseStore(paths: paths)
        try store.save([Workhorse.sample(id: "attic", name: "Attic", user: "alex", projectsFolder: "~/Development")])
        let desks = desks ?? Desks(version: version)
        self.desks = desks
        let lines = Lines()
        self.lines = lines
        let store = self.store
        refresher = MenuRefresher(load: { try store.load() }, gather: { desks.gather($0) }, save: { _ in },
                                  log: { lines.add($0) }, pause: { _ in })
        tabs = RecordingTabs()
        let menuActions = MenuActionRunner(macmoshPath: "/Applications/MacMosh.app/Contents/Helpers/macmosh", tabs: tabs,
                                           runner: FakeRunner { _ in FakeRunner.ok() }, records: scratchTabRecords())
        runner = WindowActionRunner(refresher: refresher, commands: ssh, paths: paths, menuActions: menuActions,
                                    log: { lines.add($0) })
        await refresher.refresh()
        desks.close(["recipes", "garden", "blog"])
        await refresher.refresh()
        await refresher.refresh()
    }

    var ended: [String] { (refresher.ended["attic"] ?? []).map(\.name) }
    /// The window's log lines that the actions added (`window action: …`).
    var actionLines: [String] { lines.all.filter { $0.hasPrefix("window action:") } }
}

private func ok() -> FakeRunner { FakeRunner { _ in FakeRunner.ok() } }

/// Start again, Start again and keep it, and Forget (main window design, section 7.1 C), run by
/// `WindowActionRunner` as New desk is: one key-only ssh call, nothing that can wait on a question, a log line with
/// fixed words, a result line, and a check.
@MainActor @Suite struct EndedDeskRunnerTests {
    @Test func theRigHasThreeEndedDesks() async throws {
        let rig = try await Rig(ssh: ok())
        #expect(rig.ended == ["blog", "garden", "recipes"])
    }

    // MARK: Start again makes the same desk

    /// The same name, the folder as the report gave it (with its space), the command as one argument (spaces, a
    /// quote and a dollar sign), its reopen and keep flags, and permanent off; key-only, stdin closed, 15 seconds,
    /// to the address that last answered.
    @Test func startAgainSendsTheSameDesk() async throws {
        let ssh = ok()
        let rig = try await Rig(ssh: ssh)
        let result = await rig.runner.startAgain("attic", desk: "recipes", keepIt: false)
        #expect(result == .done("Started recipes again on Attic."))
        #expect(ssh.calls.count == 1)
        let call = try #require(ssh.calls.first)
        #expect(call.stdin == nil)
        #expect(call.timeout == .seconds(15))
        #expect(call.argv.first == "ssh" && call.argv.contains("BatchMode=yes") && call.argv.contains("IdentitiesOnly=yes"))
        let dash = try #require(call.argv.firstIndex(of: "--"))
        #expect(call.argv[dash + 1] == "alex@192.168.1.20")
        #expect(call.argv.last == #"~/.macmosh/macmosh-host desk-new recipes '/Users/alex/Development/my recipes' --no-reopen --keep --command 'claude --continue "fix it" $HOME; echo '\''done'\'''"#)
        // Read back as the workhorse's shell reads it, every argument is the one the report gave.
        #if DEBUG
        #expect(SampleSSH.split(try #require(call.argv.last)).dropFirst().map { $0 } == [
            "desk-new", "recipes", recipesFolder, "--no-reopen", "--keep", "--command", recipesCommand,
        ])
        #endif
    }

    @Test func startAgainAndKeepItSendsPermanent() async throws {
        let ssh = ok()
        let rig = try await Rig(ssh: ssh)
        let result = await rig.runner.startAgain("attic", desk: "garden", keepIt: true)
        #expect(result == .done("Started garden again on Attic. It is kept when it exits."))
        #expect(ssh.calls.map { $0.argv.last } == [
            "~/.macmosh/macmosh-host desk-new garden /Users/alex/Development/garden --reopen --permanent --command claude",
        ])
    }

    @Test func aDeskWithNoCommandSendsNone() async throws {
        let ssh = ok()
        let rig = try await Rig(ssh: ssh)
        _ = await rig.runner.startAgain("attic", desk: "blog", keepIt: false)
        #expect(ssh.calls.map { $0.argv.last } == ["~/.macmosh/macmosh-host desk-new blog /Users/alex/Development/blog --reopen"])
    }

    /// Then what the New desk form does after making a desk: the tab on it, the row marked as arriving until the
    /// check lands, the result line and the menu's notice; and the entry leaves the Ended list at once.
    @Test func afterItWorkedTheTabTheRowAndTheResultLine() async throws {
        let rig = try await Rig(ssh: ok())
        _ = await rig.runner.startAgain("attic", desk: "recipes", keepIt: false)
        #expect(rig.ended == ["blog", "garden"])
        #expect(rig.runner.activity("attic").arriving == ["recipes"])
        #expect(rig.runner.activity("attic").busy.isEmpty)
        rig.desks.open("recipes")   // the stand-in workhorse made it
        await rig.runner.idle()
        #expect(rig.runner.activity("attic").arriving.isEmpty)
        #expect(rig.tabs.opened.count == 1)
        #expect(rig.tabs.opened.first?.line.hasSuffix("connect attic recipes") == true)
        #expect(rig.refresher.results["attic"] == "Started recipes again on Attic.")
        #expect(rig.refresher.notice == "Started recipes again on Attic.")
        #expect(rig.refresher.latest["attic"]?.status?.desks.contains { $0.name.value == "recipes" } == true)
        #expect(rig.ended == ["blog", "garden"])
        #expect(rig.actionLines == ["window action: startAgain ok"])
    }

    // MARK: failures

    @Test func aFailureKeepsTheEntryWithItsReasonInOneLine() async throws {
        let ssh = FakeRunner { _ in FakeRunner.failed(1, stderr: "macmosh-host: could not create the desk\n") }
        let rig = try await Rig(ssh: ssh)
        guard case .failed(let reason) = await rig.runner.startAgain("attic", desk: "recipes", keepIt: false) else {
            Issue.record("a failed call said it worked"); return
        }
        #expect(!reason.contains("\n"))
        #expect(rig.ended == ["blog", "garden", "recipes"])
        let entry = try #require(rig.refresher.ended["attic"]?.first { $0.name == "recipes" })
        #expect(entry.problem == reason)
        await rig.runner.idle()
        #expect(rig.refresher.results["attic"] == "recipes wasn't started again. " + reason)
        #expect(rig.actionLines == ["window action: startAgain failed"])
        #expect(rig.tabs.opened.isEmpty)
        #expect(rig.runner.activity("attic").arriving.isEmpty)
    }

    /// The desk is open again by the time of the click (no check has seen it yet): the script refuses, and the
    /// window says so in one line. Nothing open is replaced or disturbed.
    @Test func aDeskOpenAgainIsRefusedByTheScriptInOneLine() async throws {
        let ssh = FakeRunner { _ in FakeRunner.failed(7, stderr: "macmosh-host: the desk recipes already exists\n") }
        let rig = try await Rig(ssh: ssh)
        let result = await rig.runner.startAgain("attic", desk: "recipes", keepIt: false)
        #expect(result == .failed("Attic already has a desk called recipes."))
        #expect(rig.refresher.ended["attic"]?.first { $0.name == "recipes" }?.problem == "Attic already has a desk called recipes.")
        await rig.runner.idle()
        #expect(rig.refresher.results["attic"] == "recipes wasn't started again. Attic already has a desk called recipes.")
    }

    /// The limit passed: it may have worked there, so the line claims neither, and the entry stays until a check
    /// shows the desk open.
    @Test func aTimeoutUsesTheUnsureWordsAndTheEntryWaitsForACheck() async throws {
        let ssh = FakeRunner { _ in CommandResult(exitCode: -1, stdout: "", stderr: "", timedOut: true) }
        let rig = try await Rig(ssh: ssh)
        let unsure = "MacMosh didn't hear back from Attic about recipes within 15 seconds. The next check shows whether it was started."
        #expect(await rig.runner.startAgain("attic", desk: "recipes", keepIt: false) == .failed(unsure))
        #expect(rig.ended.contains("recipes"))
        #expect(rig.refresher.ended["attic"]?.first { $0.name == "recipes" }?.problem == unsure)
        await rig.runner.idle()
        #expect(rig.refresher.results["attic"] == unsure)
        #expect(rig.actionLines == ["window action: startAgain failed"])
        // It had worked: the next check shows recipes open, and the entry goes.
        rig.desks.open("recipes")
        await rig.refresher.refresh()
        #expect(rig.ended == ["blog", "garden"])
    }

    /// Taken again by the script's rule (here a permanent desk of that name, closed): nothing is sent.
    @Test func aTakenNameSendsNothing() async throws {
        let ssh = ok()
        let rig = try await Rig(ssh: ssh)
        rig.desks.makePermanentClosed("blog")
        await rig.refresher.refresh()
        #expect(rig.ended.contains("blog"))
        #expect(await rig.runner.startAgain("attic", desk: "blog", keepIt: false) == .failed("Attic already has a desk called blog."))
        #expect(ssh.calls.isEmpty)
    }

    @Test func keepItOnAScriptOlderThan050SendsNothing() async throws {
        let ssh = ok()
        let rig = try await Rig(ssh: ssh, version: "0.4.2")
        #expect(await rig.runner.startAgain("attic", desk: "garden", keepIt: true)
                == .failed("Start again and keep it needs the workhorse script 0.5.0 or newer, and Attic has 0.4.2."))
        #expect(ssh.calls.isEmpty)
    }

    @Test func aWorkhorseThatIsNotReadyGetsNoSSH() async throws {
        let ssh = ok()
        let rig = try await Rig(ssh: ssh)
        rig.desks.setState(.locked)
        await rig.refresher.refresh()
        guard case .failed(let reason) = await rig.runner.startAgain("attic", desk: "recipes", keepIt: false) else {
            Issue.record("a Locked workhorse made a desk"); return
        }
        #expect(reason.hasPrefix("Attic · Locked"))
        #expect(ssh.calls.isEmpty)
    }

    @Test func aDeskNoLongerListedSendsNothing() async throws {
        let ssh = ok()
        let rig = try await Rig(ssh: ssh)
        #expect(await rig.runner.startAgain("attic", desk: "api", keepIt: false)
                == .failed("api is no longer among the ended desks of Attic."))
        #expect(ssh.calls.isEmpty)
    }

    // MARK: one action per desk name

    @Test func oneActionPerNameAtATimeOthersStayUsable() async throws {
        let ssh = HeldRunner()
        let rig = try await Rig(ssh: ssh)
        let first = Task { await rig.runner.startAgain("attic", desk: "recipes", keepIt: false) }
        #expect(await ssh.waitFor(1))
        #expect(rig.runner.activity("attic").busy == ["recipes": .startAgain])
        // The same name: refused at once, nothing sent; Forget too.
        #expect(await rig.runner.startAgain("attic", desk: "recipes", keepIt: true) == .failed("Wait for the action on recipes to finish."))
        rig.runner.forget("attic", desk: "recipes")
        #expect(rig.ended.contains("recipes"))
        // Another ended desk is usable meanwhile.
        let second = Task { await rig.runner.startAgain("attic", desk: "garden", keepIt: false) }
        #expect(await ssh.waitFor(2))
        #expect(ssh.calls.count == 2)
        ssh.release()
        #expect(await first.value == .done("Started recipes again on Attic."))
        #expect(await second.value == .done("Started garden again on Attic."))
        await rig.runner.idle()
        #expect(rig.runner.activity("attic").busy.isEmpty)
    }

    // MARK: Forget

    @Test func forgetTakesTheEntryAwayAndSendsNothing() async throws {
        let ssh = ok()
        let rig = try await Rig(ssh: ssh)
        rig.runner.forget("attic", desk: "blog")
        #expect(rig.ended == ["garden", "recipes"])
        #expect(ssh.calls.isEmpty)
        #expect(rig.actionLines == ["window action: forget ok"])
        // A later check doesn't bring it back.
        await rig.refresher.refresh()
        #expect(rig.ended == ["garden", "recipes"])
    }

    /// No log line the change adds names a desk, a folder or a command.
    @Test func theLogLinesHaveFixedWordsOnly() async throws {
        let rig = try await Rig(ssh: ok())
        _ = await rig.runner.startAgain("attic", desk: "recipes", keepIt: false)
        rig.runner.forget("attic", desk: "blog")
        await rig.runner.idle()
        #expect(rig.actionLines == ["window action: startAgain ok", "window action: forget ok"])
        #expect(MenuLog.windowAction(.startAgain, ok: false) == "window action: startAgain failed")
        for line in rig.lines.all where !line.hasPrefix("menu ") {
            #expect(!line.contains("recipes") && !line.contains("blog") && !line.contains("claude"), "\(line)")
        }
    }

    // MARK: the window's own Remove and Rename never show as ended

    @Test func aDeskRemovedFromTheWindowIsNotListed() async throws {
        let desks = Desks(version: "0.11.0")
        // The stand-in workhorse removes api when the call comes.
        let ssh = FakeRunner { _ in desks.close(["api"]); return FakeRunner.ok() }
        let rig = try await Rig(ssh: ssh, desks: desks)
        let remove = try #require(rig.runner.removeConfirmation("attic", desk: "api"))
        #expect(await rig.runner.remove(remove) == .done("Removed the desk api from Attic."))
        await rig.runner.idle()
        #expect(rig.refresher.latest["attic"]?.status?.desks.contains { $0.name.value == "api" } == false)
        #expect(!rig.ended.contains("api"))
    }

    /// Renamed to a name in another folder, so only the window's own mark keeps the old name out.
    @Test func aDeskRenamedFromTheWindowIsNotListed() async throws {
        let desks = Desks(version: "0.11.0")
        let ssh = FakeRunner { _ in desks.close(["api"]); desks.add("notes", folder: "/Users/alex/notes"); return FakeRunner.ok() }
        let rig = try await Rig(ssh: ssh, desks: desks)
        var rename = try #require(rig.runner.renameForm("attic", desk: "api"))
        rename.name = "notes"
        #expect(await rig.runner.rename(rename) == .done("Renamed api to notes on Attic."))
        await rig.runner.idle()
        #expect(!rig.ended.contains("api"))
    }

    @Test func aRemoveThatFailedLeavesNoMark() async throws {
        let ssh = FakeRunner { _ in FakeRunner.failed(1, stderr: "macmosh-host: could not lock the desk list\n") }
        let rig = try await Rig(ssh: ssh)
        rig.desks.open("blog")
        await rig.refresher.refresh()
        let remove = try #require(rig.runner.removeConfirmation("attic", desk: "blog"))
        _ = await rig.runner.remove(remove)
        await rig.runner.idle()
        // Its last shell exits later: it is listed, as the failed removal left no mark.
        rig.desks.close(["blog"])
        await rig.refresher.refresh()
        await rig.refresher.refresh()   // blog has reopen: one more check
        #expect(rig.ended.contains("blog"))
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

    func waitFor(_ count: Int) async -> Bool {
        for _ in 0..<5_000 {
            if held >= count { return true }
            try? await Task.sleep(for: .milliseconds(2))
        }
        return false
    }
}
