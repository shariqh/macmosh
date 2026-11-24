import Foundation
import Testing
@testable import MacMoshKit

/// `macmosh connect <workhorse> <desk>` with `--window @<id>`, `--new-window` or `--view` (menu design 8.3):
/// a label, a tab record, and `attach --label <word>` with the matching option. Nothing here starts ssh or
/// mosh, and the records go to a temporary support folder.
@Suite struct ConnectTabTests {
    private static let label = "0123456789abcdef"

    private func plan(_ mode: ConnectionMode, tab: TabRequest?, paths: Paths) -> ConnectPlan {
        ConnectPlanner.plan(workhorse: .sample(id: "mbp", name: "MacBook Pro", user: "alex"),
                            desk: DeskName("website")!, mode: mode, address: "workhorse", paths: paths,
                            moshPath: "/opt/homebrew/bin/mosh", localeEnvironment: ["LANG": "en_GB.UTF-8"],
                            path: "/opt/homebrew/bin:/usr/bin:/bin", tab: tab)
    }

    /// The ssh options every line carries before its own, spelled out so a change shows here.
    private func sshOptions(_ paths: Paths) -> [String] {
        ["-o", "HostKeyAlias=macmosh-mbp",
         "-o", "UserKnownHostsFile=\"\(paths.knownHostsFile.path)\"",
         "-o", "GlobalKnownHostsFile=/dev/null",
         "-o", "StrictHostKeyChecking=yes",
         "-o", "UpdateHostKeys=no",
         "-o", "IdentitiesOnly=yes", "-i", paths.defaultIdentity.path,
         "-o", "IdentityAgent=none",
         "-o", "PasswordAuthentication=no", "-o", "KbdInteractiveAuthentication=no"]
    }

    private func moshLine(_ paths: Paths, remote: [String]) -> [String] {
        ["/opt/homebrew/bin/mosh",
         "--predict=adaptive",
         "--ssh=" + ShellQuote.join(["ssh"] + sshOptions(paths)),
         "--server=MOSH_SERVER_NETWORK_TMOUT=604800 PATH=\"$PATH:/opt/homebrew/bin:/usr/local/bin\" mosh-server",
         "alex@workhorse", "--"] + remote
    }

    private func sshLine(_ paths: Paths, remote: String) -> [String] {
        ["ssh"] + sshOptions(paths) + ["-o", "ServerAliveInterval=5", "-o", "ServerAliveCountMax=2",
                                       "-t", "--", "alex@workhorse", remote]
    }

    // MARK: The exact command lines

    @Test func plainConnectBuildsTodaysLines() throws {
        let paths = try temporaryPaths()
        #expect(plan(.mosh, tab: nil, paths: paths).argv == moshLine(paths, remote: [
            "/bin/sh", "-c", "exec \"$HOME/.macmosh/macmosh-host\" attach \"$1\"", "macmosh-host", "website"]))
        #expect(plan(.ssh, tab: nil, paths: paths).argv ==
            sshLine(paths, remote: "~/.macmosh/macmosh-host attach website"))
    }

    @Test(arguments: [
        (TabTarget.window("@3"), ["--label", "0123456789abcdef", "--window", "@3"]),
        (.newWindow, ["--label", "0123456789abcdef", "--new-window"]),
        (.view, ["--label", "0123456789abcdef"]),
    ])
    func theMoshLinePassesEveryWordAsItsOwnArgument(_ target: TabTarget, _ words: [String]) throws {
        let paths = try temporaryPaths()
        let p = plan(.mosh, tab: TabRequest(label: Self.label, target: target), paths: paths)
        #expect(p.argv == moshLine(paths, remote: [
            "/bin/sh", "-c", "exec \"$HOME/.macmosh/macmosh-host\" attach \"$@\"", "macmosh-host"] + words + ["website"]))
    }

    @Test(arguments: [
        (TabTarget.window("@3"), "~/.macmosh/macmosh-host attach --label 0123456789abcdef --window @3 website"),
        (.newWindow, "~/.macmosh/macmosh-host attach --label 0123456789abcdef --new-window website"),
        (.view, "~/.macmosh/macmosh-host attach --label 0123456789abcdef website"),
    ])
    func thePlainSSHLinePassesTheSameWords(_ target: TabTarget, _ remote: String) throws {
        let paths = try temporaryPaths()
        let p = plan(.ssh, tab: TabRequest(label: Self.label, target: target), paths: paths)
        #expect(p.argv == sshLine(paths, remote: remote))
        #expect(p.retryOnDrop == false)
    }

    /// Every added word stays one word under both quotings the lines use: the plain characters the menu's
    /// tab commands allow, which `ShellQuote` leaves bare.
    @Test(arguments: [TabTarget.window("@12345"), .newWindow, .view])
    func everyAddedWordIsSafeUnquoted(_ target: TabTarget) {
        let words = TabRequest(label: TabLabel.make(), target: target).attachArguments
        for word in words {
            #expect(word.range(of: "^[A-Za-z0-9@%+=:,./_-]+$", options: .regularExpression) != nil, "\(word)")
            #expect(ShellQuote.posix(word) == word)
        }
    }

    // MARK: The options

    @Test func noOptionIsNoTarget() throws {
        #expect(try TabTarget.from(window: nil, newWindow: false, view: false) == nil)
    }

    @Test func eachOptionAloneIsItsTarget() throws {
        #expect(try TabTarget.from(window: "@3", newWindow: false, view: false) == .window("@3"))
        #expect(try TabTarget.from(window: nil, newWindow: true, view: false) == .newWindow)
        #expect(try TabTarget.from(window: nil, newWindow: false, view: true) == .view)
    }

    @Test(arguments: [("@3", true, false), ("@3", false, true), (nil, true, true), ("@3", true, true)]
          as [(String?, Bool, Bool)])
    func twoOptionsTogetherAreAUsageError(_ window: String?, _ newWindow: Bool, _ view: Bool) {
        #expect(throws: TabTargetError.moreThanOne) {
            try TabTarget.from(window: window, newWindow: newWindow, view: view)
        }
        #expect(TabTargetError.moreThanOne.description == "Use one of --window, --new-window and --view, not two.")
    }

    @Test(arguments: ["3", "@", "@x", "@3a", "@-3", "", " @3", "@3\n"])
    func aWindowIdIsAtAndDigits(_ id: String) {
        #expect(throws: TabTargetError.badWindowId(id)) { try TabTarget.from(window: id, newWindow: false, view: false) }
        #expect(TabTargetError.badWindowId("x").description == "\"x\" isn't a window id: use @ and its number, such as @3.")
    }

    // MARK: The label

    @Test func aLabelIsSixteenHexCharactersFromTheRandomBytes() {
        let fixed = TabLabel.make { bytes in for i in bytes.indices { bytes[i] = UInt8(i * 17 + 1) } }
        #expect(fixed == "0112233445566778")
        let real = TabLabel.make()
        #expect(real.count == 16 && TabLabel.isValid(real))
        #expect(TabLabel.make() != real)
    }

    /// The script's rule is "each a digit or a letter from a to f", so a digit carrying a combining mark (one
    /// character to Swift, two scalars) breaks it.
    @Test(arguments: ["1\u{301}2\u{301}3\u{301}4\u{301}", "abcdé", "ABCD", "abc", String(repeating: "a", count: 33)])
    func aLabelIsOnlyPlainDigitsAndAToF(_ word: String) {
        #expect(!TabLabel.isValid(word))
        #expect(TabLabel.isValid("abcd") && TabLabel.isValid(String(repeating: "0", count: 32)))
    }

    // MARK: Running connect

    private func check(_ status: HostStatus? = nil) -> CheckResult {
        CheckResult(workhorse: .recoverySample(), state: .ready(signIns: true), status: status, probes: ProbeSet(),
                    answeredAt: "workhorse", homeReachable: nil, checkedAt: Date(timeIntervalSince1970: 1_800_000_000))
    }

    private func noting(_ paths: Paths, started: Int64? = 1_800_000_000_000_001, tty: String = "/dev/ttys009") -> TabNoting {
        TabNoting(store: TabRecordStore(paths: paths, probe: FakeProcessProbe(running: [777: 1_800_000_000_000_001])),
                  makeLabel: { Self.label }, pid: 777, started: started, tty: tty,
                  now: { Date(timeIntervalSince1970: 1_800_000_100) })
    }

    private func connect(_ result: CheckResult, mode: ConnectionMode?, tab: TabTarget?, noting: TabNoting,
                         environment: [String: String] = ["TERM_PROGRAM": "iTerm.app"],
                         interactive: FakeInteractive, ui: ScriptedInteraction = ScriptedInteraction()) async -> Int32 {
        await ConnectRunner(interactive: interactive, sleep: { _ in }, stateNow: { .ready(signIns: true) })
            .connect(result, desk: DeskName("website")!, requestedMode: mode, paths: noting.store.folder.supportPaths,
                     environment: environment, findMosh: { "/opt/homebrew/bin/mosh" }, ui: ui, tab: tab, noting: noting)
    }

    @Test func tabsModeRefusesTheOptionsAndRunsNothing() async throws {
        let paths = try temporaryPaths()
        for target in [TabTarget.window("@3"), .newWindow, .view] {
            let interactive = FakeInteractive(); let ui = ScriptedInteraction()
            let code = await connect(check(), mode: .tabs, tab: target, noting: noting(paths), interactive: interactive, ui: ui)
            #expect(code != 0 && interactive.calls.isEmpty)
            #expect(ui.said.contains("Tabs mode already shows every window as its own tab."))
            #expect(TabRecordStore(paths: paths).records().isEmpty)
        }
    }

    @Test func plainConnectWritesNoRecord() async throws {
        let paths = try temporaryPaths()
        let interactive = FakeInteractive()
        let code = await connect(check(), mode: .ssh, tab: nil, noting: noting(paths), interactive: interactive)
        #expect(code == 0)
        #expect(interactive.calls.first?.last == "~/.macmosh/macmosh-host attach website")
        #expect(!FileManager.default.fileExists(atPath: paths.tabsDir.path))
    }

    /// While the connection runs, the tab's record is on disk with this process and its start time; when the
    /// connection ends, it is gone.
    @Test(arguments: [ConnectionMode.mosh, .ssh])
    func theRecordIsThereWhileConnectedAndGoneAfter(_ mode: ConnectionMode) async throws {
        let paths = try temporaryPaths()
        let seen = Box<[TabRecord]>([])
        let interactive = FakeInteractive(onRun: { _ in seen.value = TabRecordStore(paths: paths).records() })
        let code = await connect(check(), mode: mode, tab: .window("@3"), noting: noting(paths),
                                 environment: ["TERM_PROGRAM": "Apple_Terminal"], interactive: interactive)
        #expect(code == 0)
        #expect(seen.value == [TabRecord(label: Self.label, workhorse: "mbp", desk: "website", askedWindow: "@3",
                                         target: "window", pid: 777, started: 1_800_000_000_000_001, tty: "/dev/ttys009",
                                         terminal: .terminal, openedAt: Date(timeIntervalSince1970: 1_800_000_100))])
        #expect(TabRecordStore(paths: paths).records().isEmpty)
        let words = mode == .mosh ? Array(interactive.calls[0].suffix(5)) : [interactive.calls[0].last ?? ""]
        #expect(words == (mode == .mosh ? ["--label", Self.label, "--window", "@3", "website"]
                                        : ["~/.macmosh/macmosh-host attach --label \(Self.label) --window @3 website"]))
    }

    @Test func aNewWindowOrAViewAsksForNoWindow() async throws {
        let paths = try temporaryPaths()
        for target in [TabTarget.newWindow, .view] {
            let seen = Box<[TabRecord]>([])
            let interactive = FakeInteractive(onRun: { _ in seen.value = TabRecordStore(paths: paths).records() })
            _ = await connect(check(), mode: .ssh, tab: target, noting: noting(paths), interactive: interactive)
            #expect(seen.value.map(\.askedWindow) == [""])
            #expect(seen.value.map(\.target) == [target.recordWord])
            #expect(seen.value.map(\.terminal) == [.iterm2])
        }
    }

    /// An older script refuses the option; its message is on the terminal already, and the tab says how
    /// attach ended, as for any failure. The record is still removed.
    @Test func anOlderScriptStillGetsTheOptionAndItsRefusalIsShown() async throws {
        let paths = try temporaryPaths()
        var status = HostStatus(); status.scriptVersion = "0.7.0"
        let interactive = FakeInteractive(exitCodes: [2]); let ui = ScriptedInteraction()
        let code = await connect(check(status), mode: .ssh, tab: .view, noting: noting(paths),
                                 interactive: interactive, ui: ui)
        #expect(code == 2)
        #expect(interactive.calls.first?.last == "~/.macmosh/macmosh-host attach --label \(Self.label) website")
        #expect(ui.said.last == "ssh ended with exit code 2.")
        #expect(ui.waits == 1)
        #expect(TabRecordStore(paths: paths).records().isEmpty)
    }

    /// Without its own start time the record could never be trusted, so none is written; the tab still opens.
    @Test func withoutAStartTimeNoRecordIsWrittenButTheTabOpens() async throws {
        let paths = try temporaryPaths()
        let seen = Box<[TabRecord]>([])
        let interactive = FakeInteractive(onRun: { _ in seen.value = TabRecordStore(paths: paths).records() })
        let ui = ScriptedInteraction()
        let code = await connect(check(), mode: .ssh, tab: .view, noting: noting(paths, started: nil),
                                 interactive: interactive, ui: ui)
        #expect(code == 0 && interactive.calls.count == 1)
        #expect(seen.value.isEmpty)
        #expect(ui.said.contains("MacMosh couldn't note this tab, so the menu may not find it later."))
    }

    /// When `tabs/` can't be written (here a plain file sits in its place), the tab still opens with its
    /// label and the person is told the menu may not find it.
    @Test func aRecordThatCantBeWrittenStillOpensTheTab() async throws {
        let paths = try temporaryPaths()
        try FileManager.default.createDirectory(at: paths.supportDir, withIntermediateDirectories: true)
        try Data("not a folder".utf8).write(to: paths.tabsDir)
        let interactive = FakeInteractive(); let ui = ScriptedInteraction()
        let code = await connect(check(), mode: .ssh, tab: .view, noting: noting(paths),
                                 interactive: interactive, ui: ui)
        #expect(code == 0 && interactive.calls.count == 1)
        #expect(interactive.calls.first?.last == "~/.macmosh/macmosh-host attach --label \(Self.label) website")
        #expect(ui.said.contains("MacMosh couldn't note this tab, so the menu may not find it later."))
    }

    @Test func thisProcessIsTheOneThatStaysAlive() {
        let live = TabNoting.thisProcess(paths: .test)
        #expect(live.pid == getpid())
        #expect(live.started == SystemProcessProbe().startTime(of: getpid()))
        #expect(live.store.folder == Paths.test.tabsDir)
        #expect(TabLabel.isValid(live.makeLabel()))
    }
}

private extension URL {
    /// The temporary `Paths` whose `tabs/` folder this is.
    var supportPaths: Paths { Paths(supportDir: deletingLastPathComponent(), sshDir: Paths.test.sshDir) }
}
