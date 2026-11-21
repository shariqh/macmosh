import Foundation
import Testing
@testable import MacMoshKit

/// `macmosh connect`: the three command lines, the retry loop and the checks before anything runs.
/// Nothing here starts ssh or mosh: the terminal hand-over is `FakeInteractive`.
@Suite struct ConnectTests {
    // MARK: Samples

    private func plan(mode: ConnectionMode, prediction: Prediction = .adaptive,
                      moshPath: String = "/opt/homebrew/bin/mosh",
                      locale: [String: String] = ["LANG": "en_GB.UTF-8"],
                      path: String? = "/opt/homebrew/bin:/usr/bin:/bin") -> ConnectPlan {
        ConnectPlanner.plan(workhorse: .sample(id: "mbp", name: "MacBook Pro", user: "alex", prediction: prediction),
                            desk: DeskName("website")!, mode: mode, address: "workhorse", paths: .test,
                            moshPath: moshPath, localeEnvironment: locale, path: path)
    }

    private func check(_ state: WorkhorseState, answeredAt: String? = "workhorse") -> CheckResult {
        CheckResult(workhorse: .recoverySample(), state: state, status: nil, probes: ProbeSet(),
                    answeredAt: answeredAt, homeReachable: nil, checkedAt: Date(timeIntervalSince1970: 1_800_000_000))
    }

    private func runner(_ interactive: FakeInteractive, state: WorkhorseState = .ready(signIns: true),
                        sleeps: Recorder<Duration> = Recorder()) -> ConnectRunner {
        ConnectRunner(interactive: interactive, sleep: { await sleeps.add($0) }, stateNow: { state })
    }

    // MARK: The command lines

    @Test func theMoshLineIsTheOneTestedInSittingOne() {
        let p = ConnectPlanner.plan(workhorse: .sample(id: "mbp", user: "alex"), desk: DeskName("website")!, mode: .mosh,
                                    address: "workhorse", paths: .test, moshPath: "/opt/homebrew/bin/mosh",
                                    localeEnvironment: ["LANG": "en_GB.UTF-8"])
        #expect(p.argv.first == "/opt/homebrew/bin/mosh")
        #expect(p.argv.contains("--predict=adaptive"))
        #expect(p.argv.contains("--server=MOSH_SERVER_NETWORK_TMOUT=604800 PATH=\"$PATH:/opt/homebrew/bin:/usr/local/bin\" mosh-server"))
        #expect(Array(p.argv.suffix(7)) == ["alex@workhorse", "--", "/bin/sh", "-c",
                                            "exec \"$HOME/.macmosh/macmosh-host\" attach \"$1\"", "macmosh-host", "website"])
        #expect(p.retryOnDrop == false && p.environment["LANG"] == nil)
    }

    @Test func theMoshSshStringPinsTheKey() throws {
        let p = plan(mode: .mosh)
        let ssh = try #require(p.argv.first { $0.hasPrefix("--ssh=") })
        #expect(ssh.hasPrefix("--ssh=ssh "))
        #expect(ssh.contains("HostKeyAlias=macmosh-mbp") && ssh.contains("StrictHostKeyChecking=yes"))
    }

    @Test(arguments: [ConnectionMode.mosh, .tabs, .ssh])
    func noModeCanAskForAPassword(_ mode: ConnectionMode) throws {
        let p = plan(mode: mode)
        if mode == .mosh {
            let ssh = try #require(p.argv.first { $0.hasPrefix("--ssh=") })
            #expect(ssh.contains("PasswordAuthentication=no") && ssh.contains("KbdInteractiveAuthentication=no"))
        } else {
            #expect(p.argv.contains("PasswordAuthentication=no") && p.argv.contains("KbdInteractiveAuthentication=no"))
        }
        #expect(!p.argv.contains("PasswordAuthentication=yes") && !p.argv.contains("BatchMode=no"))
    }

    @Test func moshsFolderIsPutOnPathWhenMissing() {
        let missing = plan(mode: .mosh, moshPath: "/opt/homebrew/bin/mosh", path: "/usr/bin:/bin")
        #expect(missing.environment["PATH"] == "/opt/homebrew/bin:/usr/bin:/bin")
        let present = plan(mode: .mosh, moshPath: "/opt/homebrew/bin/mosh", path: "/usr/bin:/opt/homebrew/bin")
        #expect(present.environment["PATH"] == nil)
        let empty = plan(mode: .mosh, moshPath: "/usr/local/bin/mosh", path: nil)
        #expect(empty.environment["PATH"]?.hasPrefix("/usr/local/bin") == true)
    }

    @Test func tabsAndPlainSSHNoticeADeadNetwork() {
        for mode in [ConnectionMode.tabs, .ssh] {
            let p = plan(mode: mode)
            #expect(p.argv.contains("ServerAliveInterval=5") && p.argv.contains("ServerAliveCountMax=2"))
        }
        let mosh = plan(mode: .mosh)
        #expect(!mosh.argv.joined(separator: " ").contains("ServerAlive"))
    }

    @Test func tabsModeUsesControlModeAndRetries() {
        let p = plan(mode: .tabs)
        #expect(p.argv.first == "ssh" && p.argv.contains("-t"))
        #expect(Array(p.argv.suffix(3)) == ["--", "alex@workhorse", "~/.macmosh/macmosh-host attach --cc website"])
        #expect(p.retryOnDrop == true)
        #expect(p.argv.contains("BatchMode=yes") == false)
    }

    @Test func plainSSHDoesNotRetry() {
        let p = plan(mode: .ssh)
        #expect(p.retryOnDrop == false)
        #expect(Array(p.argv.suffix(3)) == ["--", "alex@workhorse", "~/.macmosh/macmosh-host attach website"])
        #expect(!p.argv.joined(separator: " ").contains("--cc"))
    }

    @Test func theIntroSaysWhatWillHappen() {
        #expect(plan(mode: .mosh).intro ==
            "Opening \"website\" on MacBook Pro over mosh. If the network drops, this tab picks up by itself.")
        #expect(plan(mode: .tabs).intro ==
            "Opening \"website\" on MacBook Pro as iTerm2 tabs. If the connection drops, the tabs close and this tab keeps trying.")
        #expect(plan(mode: .ssh).intro ==
            "Opening \"website\" on MacBook Pro over plain ssh. If the connection drops, this tab ends; your work keeps running.")
    }

    @Test func aUTF8LocaleIsSuppliedOnlyWhenMissing() {
        #expect(plan(mode: .mosh, locale: [:]).environment["LANG"] == "en_US.UTF-8")
        #expect(plan(mode: .mosh, locale: ["LANG": "C"]).environment["LANG"] == "en_US.UTF-8")
        #expect(plan(mode: .mosh, locale: ["LANG": "en_GB.UTF-8"]).environment["LANG"] == nil)
        #expect(plan(mode: .mosh, locale: ["LC_ALL": "de_DE.utf8"]).environment["LANG"] == nil)
        #expect(plan(mode: .mosh, locale: ["LC_CTYPE": "UTF-8"]).environment["LANG"] == nil)
        // Tabs and plain ssh don't run mosh, so they need no locale of their own.
        #expect(plan(mode: .tabs, locale: [:]).environment["LANG"] == nil)
    }

    /// `LC_ALL` beats `LC_CTYPE`, which beats `LANG`; one that is empty counts as not set.
    @Test(arguments: [
        // The variable that decides isn't UTF-8, so that one is set, and only that one.
        (["LC_ALL": "C", "LANG": "en_US.UTF-8"], "LC_ALL"),
        (["LC_ALL": "de_DE.ISO8859-1", "LC_CTYPE": "en_US.UTF-8", "LANG": "en_US.UTF-8"], "LC_ALL"),
        (["LC_CTYPE": "C", "LANG": "en_US.UTF-8"], "LC_CTYPE"),
        (["LC_ALL": "", "LC_CTYPE": "C", "LANG": "en_US.UTF-8"], "LC_CTYPE"),
        (["LC_ALL": "", "LC_CTYPE": "", "LANG": ""], "LANG"),
        (["LC_ALL": "", "LANG": "C"], "LANG"),
        // The variable that decides is UTF-8, so nothing is set, whatever the ones below it say.
        (["LC_ALL": "en_US.UTF-8", "LC_CTYPE": "C", "LANG": "C"], nil),
        (["LC_CTYPE": "en_US.UTF-8", "LANG": "C"], nil),
        (["LC_ALL": "", "LANG": "en_US.UTF-8"], nil),
    ] as [([String: String], String?)])
    func theLocaleVariableThatDecidesIsTheOneSet(_ locale: [String: String], _ expected: String?) {
        let environment = plan(mode: .mosh, locale: locale).environment
        for name in ["LC_ALL", "LC_CTYPE", "LANG"] {
            #expect(environment[name] == (name == expected ? "en_US.UTF-8" : nil), "\(name) for \(locale)")
        }
    }

    @Test(arguments: Prediction.allCases)
    func thePredictionSettingIsUsed(_ prediction: Prediction) {
        #expect(plan(mode: .mosh, prediction: prediction).argv.contains("--predict=\(prediction.rawValue)"))
    }

    @Test func titleEscapeIsOSC1() {
        #expect(TabTitle.escape("website") == "\u{1B}]1;website\u{07}")
        // A title can't end the escape early or start another one.
        #expect(TabTitle.escape("a\u{07}b\u{1B}c") == "\u{1B}]1;abc\u{07}")
    }

    // MARK: Running

    @Test func retriesOnlyWhileTheConnectionDrops() async {
        let interactive = FakeInteractive(exitCodes: [255, 255, 0]); let sleeps = Recorder<Duration>()
        let plan = ConnectPlan(argv: ["ssh"], environment: [:], retryOnDrop: true, intro: "x")
        let code = await ConnectRunner(interactive: interactive, sleep: { await sleeps.add($0) }, stateNow: { .cantReach(.nothingAnswers) })
            .run(plan, title: "website", ui: ScriptedInteraction())
        #expect(code == 0 && interactive.calls.count == 3)
        #expect(await sleeps.values == [.seconds(3), .seconds(3)])
    }

    @Test func aChangedKeyEndsTheRetries() async {
        let interactive = FakeInteractive(exitCodes: [255, 255, 0]); let ui = ScriptedInteraction()
        let plan = ConnectPlan(argv: ["ssh"], environment: [:], retryOnDrop: true, intro: "x")
        let code = await runner(interactive, state: .cantVerify).run(plan, title: "website", ui: ui)
        #expect(code != 0 && interactive.calls.count == 1)
        #expect(ui.said.contains { $0.contains("Don't type a password") })
        #expect(ui.said.contains("Connection lost. Trying again in 3 seconds…"))
        #expect(ui.waits == 1)
    }

    @Test(arguments: [WorkhorseState.locked, .waitingForLogin, .notSetUp(.notPaired)])
    func anyOtherStateEndsTheRetriesToo(_ state: WorkhorseState) async {
        let interactive = FakeInteractive(exitCodes: [255, 0])
        let plan = ConnectPlan(argv: ["ssh"], environment: [:], retryOnDrop: true, intro: "x")
        _ = await runner(interactive, state: state).run(plan, title: "website", ui: ScriptedInteraction())
        #expect(interactive.calls.count == 1)
    }

    @Test func aReadyWorkhorseIsTriedAgain() async {
        let interactive = FakeInteractive(exitCodes: [255, 0])
        let plan = ConnectPlan(argv: ["ssh"], environment: [:], retryOnDrop: true, intro: "x")
        let code = await runner(interactive, state: .ready(signIns: true)).run(plan, title: "website", ui: ScriptedInteraction())
        #expect(code == 0 && interactive.calls.count == 2)
    }

    @Test func plainSSHEndsAtOnceWhenTheConnectionDrops() async {
        let interactive = FakeInteractive(exitCodes: [255, 0]); let sleeps = Recorder<Duration>()
        let plan = ConnectPlan(argv: ["ssh"], environment: [:], retryOnDrop: false, intro: "x")
        let ui = ScriptedInteraction()
        let code = await runner(interactive, sleeps: sleeps).run(plan, title: "website", ui: ui)
        #expect(code == 255 && interactive.calls.count == 1)
        #expect(await sleeps.values.isEmpty)
        #expect(ui.waits == 1)
    }

    @Test func aNormalExitEndsTheLoop() async {
        let interactive = FakeInteractive(exitCodes: [0]); let sleeps = Recorder<Duration>(); let ui = ScriptedInteraction()
        let plan = ConnectPlan(argv: ["ssh"], environment: [:], retryOnDrop: true, intro: "Opening it.")
        let code = await runner(interactive, sleeps: sleeps).run(plan, title: "website", ui: ui)
        #expect(code == 0 && interactive.calls.count == 1)
        #expect(await sleeps.values.isEmpty && ui.waits == 0)
        #expect(ui.said.first == "Opening it.")
        #expect(ui.said.contains(TabTitle.escape("website")))
    }

    @Test func anotherExitCodeEndsTheLoopWithoutRetrying() async {
        let interactive = FakeInteractive(exitCodes: [1, 0])
        let plan = ConnectPlan(argv: ["ssh"], environment: [:], retryOnDrop: true, intro: "x")
        let code = await runner(interactive).run(plan, title: "website", ui: ScriptedInteraction())
        #expect(code == 1 && interactive.calls.count == 1)
    }

    @Test func aFailureSaysWhyAndWaitsForAKey() async {
        let interactive = FakeInteractive(exitCodes: [4]); let ui = ScriptedInteraction()
        let plan = ConnectPlan(argv: ["/opt/homebrew/bin/mosh"], environment: [:], retryOnDrop: false, intro: "x")
        let code = await runner(interactive).run(plan, title: "website", ui: ui)
        #expect(code == 4)
        #expect(ui.said.contains { $0.contains("mosh ended with exit code 4") })
        #expect(ui.waits == 1)
    }

    @Test func theTerminalIsHandedOverWithThePlansCommandAndEnvironment() async {
        let seen = Box<[[String]]>([])
        let interactive = FakeInteractive(onRun: { seen.value.append($0) })
        let plan = ConnectPlan(argv: ["ssh", "a"], environment: ["LANG": "en_US.UTF-8"], retryOnDrop: false, intro: "x")
        _ = await runner(interactive).run(plan, title: "website", ui: ScriptedInteraction())
        #expect(seen.value == [["ssh", "a"]])
    }

    // MARK: Before anything runs

    private func connect(_ result: CheckResult, mode: ConnectionMode? = nil, environment: [String: String] = [:],
                         mosh: String? = "/opt/homebrew/bin/mosh", interactive: FakeInteractive = FakeInteractive(),
                         ui: ScriptedInteraction = ScriptedInteraction()) async -> Int32 {
        await runner(interactive).connect(result, desk: DeskName("website")!, requestedMode: mode, paths: .test,
                                          environment: environment, findMosh: { mosh }, ui: ui)
    }

    @Test func connectRefusesWhenTheKeyDiffers() async {
        let interactive = FakeInteractive(); let ui = ScriptedInteraction()
        let code = await connect(check(.cantVerify), interactive: interactive, ui: ui)
        #expect(code == 1 && interactive.calls.isEmpty)
        #expect(ui.said.contains { $0.contains("Don't type a password") })
        #expect(ui.waits == 1)
    }

    @Test(arguments: [WorkhorseState.locked, .waitingForLogin, .cantReach(.nothingAnswers),
                      .notSetUp(.notPaired), .notSetUp(.identityUnusable), .notSetUp(.hostScriptMissing)])
    func connectGoesNowhereUnlessTheWorkhorseIsReady(_ state: WorkhorseState) async {
        let interactive = FakeInteractive(); let ui = ScriptedInteraction()
        let code = await connect(check(state), interactive: interactive, ui: ui)
        #expect(code == 1 && interactive.calls.isEmpty)
        #expect(ui.said.first?.contains("MacBook Pro") == true)
        #expect(ui.waits == 1)
    }

    @Test(arguments: [WorkhorseState.ready(signIns: true), .ready(signIns: false), .notSetUp(.deskServerDown)])
    func connectGoesAheadWhenTheDeskServerCanBeStarted(_ state: WorkhorseState) async {
        let interactive = FakeInteractive()
        let code = await connect(check(state), interactive: interactive)
        #expect(code == 0 && interactive.calls.count == 1)
    }

    @Test func connectUsesTheAddressThatAnswered() async {
        let interactive = FakeInteractive()
        _ = await connect(check(.ready(signIns: true), answeredAt: "192.168.1.20"), mode: .ssh, interactive: interactive)
        #expect(interactive.calls.first?.contains("alex@192.168.1.20") == true)
    }

    @Test func connectUsesTheWorkhorsesModeUnlessAskedOtherwise() async {
        var w = Workhorse.recoverySample(); w.mode = .ssh
        let result = CheckResult(workhorse: w, state: .ready(signIns: true), status: nil, probes: ProbeSet(),
                                 answeredAt: "workhorse", homeReachable: nil, checkedAt: Date())
        let saved = FakeInteractive()
        _ = await connect(result, interactive: saved)
        #expect(saved.calls.first?.first == "ssh")
        let asked = FakeInteractive()
        _ = await connect(result, mode: .mosh, interactive: asked)
        #expect(asked.calls.first?.first == "/opt/homebrew/bin/mosh")
    }

    @Test func tabsOutsideITermFallBackToMosh() async {
        let interactive = FakeInteractive(); let ui = ScriptedInteraction()
        _ = await connect(check(.ready(signIns: true)), mode: .tabs, environment: ["TERM_PROGRAM": "Apple_Terminal"],
                          interactive: interactive, ui: ui)
        #expect(interactive.calls.first?.first == "/opt/homebrew/bin/mosh")
        #expect(ui.said.contains { $0.contains("iTerm2") && $0.contains("mosh") })
    }

    @Test func tabsInsideITermStayTabs() async {
        let interactive = FakeInteractive()
        _ = await connect(check(.ready(signIns: true)), mode: .tabs, environment: ["TERM_PROGRAM": "iTerm.app"],
                          interactive: interactive)
        #expect(interactive.calls.first?.first == "ssh" && interactive.calls.first?.contains("--cc") == false)
        #expect(interactive.calls.first?.last == "~/.macmosh/macmosh-host attach --cc website")
    }

    @Test func aMissingMoshSaysHowToFixIt() async {
        let interactive = FakeInteractive(); let ui = ScriptedInteraction()
        let code = await connect(check(.ready(signIns: true)), mosh: nil, interactive: interactive, ui: ui)
        #expect(code == 1 && interactive.calls.isEmpty)
        #expect(ui.said.contains("mosh isn't installed on this Mac. Run: macmosh prepare mbp --fix"))
        #expect(ui.waits == 1)
    }

    @Test func plainSSHNeedsNoMosh() async {
        let interactive = FakeInteractive()
        let code = await connect(check(.ready(signIns: true)), mode: .ssh, mosh: nil, interactive: interactive)
        #expect(code == 0 && interactive.calls.count == 1)
    }
}
