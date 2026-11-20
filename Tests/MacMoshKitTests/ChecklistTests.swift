import Foundation
import Testing
@testable import MacMoshKit

/// The daily Mac's checks from plain facts; each argument defaults to the passing value.
private func daily(mosh: String? = "/opt/homebrew/bin/mosh", brew: String? = "/opt/homebrew/bin/brew",
                   terminal: TerminalApp = .iterm2, fromSetting: Bool = false,
                   identity: IdentityState = .usable, ownKey: Bool = true,
                   tailscale: Bool? = true) -> [CheckOutcome] {
    DailyMacChecks.outcomes(DailyMacFacts(moshPath: mosh, brewPath: brew, terminal: terminal,
                                          terminalFromSetting: fromSetting, identity: identity, ownKey: ownKey,
                                          identityPath: "~/.ssh/macmosh_ed25519", tailscaleRunning: tailscale))
}

/// The workhorse's checks from one check result. The saved workhorse has a home address unless told otherwise.
private func onWorkhorse(_ r: CheckResult, saved: Workhorse = .sample(homeAddress: "192.168.1.20"),
                         installed: InstalledScript? = nil) -> [CheckOutcome] {
    let script = installed ?? (r.status.map { .version($0.scriptVersion) } ?? .absent)
    return WorkhorseChecks.outcomes(r, saved: saved, installed: script, builtIn: HostScript.version)
}

private func check(_ id: CheckID, _ r: CheckResult, saved: Workhorse = .sample(homeAddress: "192.168.1.20"),
                   installed: InstalledScript? = nil) -> CheckOutcome {
    guard let found = outcome(id, in: onWorkhorse(r, saved: saved, installed: installed)) else {
        fatalError("no outcome for \(id)")
    }
    return found
}

private func check(_ id: CheckID, _ list: [CheckOutcome]) -> CheckOutcome {
    guard let found = outcome(id, in: list) else { fatalError("no outcome for \(id)") }
    return found
}

private func with(_ change: (inout HostStatus) -> Void) -> HostStatus {
    var s = HostStatus.everythingRight
    change(&s)
    return s
}

@Suite struct ChecklistTests {
    // MARK: The plan's tests

    @Test func automaticFixesNeverTouchPowerOrSecurity() async {
        let f = ChecklistFixture(report: .everythingWrong)
        _ = await f.checklist.applyAutomaticFixes(for: .sample(), progress: { _ in })
        let all = f.runner.calls.map { $0.argv.joined(separator: " ") }.joined(separator: "\n")
        for word in ["sudo", "pmset", "fdesetup", "restart-server", "kill-server", "systemsetup", "socketfilterfw --set"] {
            #expect(!all.contains(word))
        }
    }

    @Test func automaticFixesDoWhatTheTableSays() async throws {
        let f = ChecklistFixture(report: .everythingWrong, programs: ["/opt/homebrew/bin/brew"])
        let said = ProgressLines()
        _ = await f.checklist.applyAutomaticFixes(for: .sample(), progress: { said.add($0) })
        let calls = f.runner.calls.map(\.argv)
        #expect(calls.contains(["/opt/homebrew/bin/brew", "install", "mosh"]))
        #expect(calls.contains { sshRemote($0) == ["PATH=\"$PATH:/opt/homebrew/bin:/usr/local/bin\"; brew install mosh tmux"] })
        #expect(calls.contains { sshRemote($0) == ["~/.macmosh/macmosh-host install-agent"] })
        #expect(calls.contains { sshRemote($0) == ["launchctl kickstart \"gui/$(id -u)/io.github.shariqh.macmosh.host\""] })
        #expect(try f.store.find("mbp").homeAddress == "192.168.1.20")
        // Each fix is said before it is done: one line per fix, at least.
        #expect(said.all.count >= 5)
    }

    @Test func theWorkhorseToolsGetTenMinutes() async {
        let f = ChecklistFixture(report: .everythingWrong)
        _ = await f.checklist.applyAutomaticFixes(for: .sample(), progress: { _ in })
        let brew = f.runner.calls.first { sshRemote($0.argv).first?.contains("brew install mosh tmux") ?? false }
        #expect(brew?.timeout == .seconds(600))
    }

    @Test func eachFixIsSaidBeforeItIsDone() async {
        // Each line records how many commands had run when it was said.
        let events = ProgressLines()
        let f = ChecklistFixture(report: .everythingWrong)
        let counted = f.runner
        _ = await f.checklist.applyAutomaticFixes(for: .sample(), progress: { line in
            events.add("\(counted.calls.count)|\(line)")
        })
        let installAt = f.runner.calls.firstIndex { $0.stdin != nil }
        let saidInstall = events.all.first { $0.contains("macmosh-host") }
        #expect(installAt != nil)
        #expect(saidInstall != nil)
        if let installAt, let saidInstall, let n = Int(saidInstall.prefix { $0 != "|" }) {
            #expect(n <= installAt)
        }
    }

    @Test func noFixReachesAWorkhorseThatCantBeVerified() async {
        let paths = Paths.test
        let runner = FakeRunner { argv in
            argv.first == "ssh"
                ? FakeRunner.failed(255, stderr: "@    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @\nHost key verification failed.\n")
                : FakeRunner.ok()
        }
        let store = WorkhorseStore(paths: try! temporaryPaths())
        try? store.upsert(.sample())
        let hints = FixedHints(.allFine)
        let checklist = Checklist(runner: runner, paths: paths, store: store,
                                  checker: StatusChecker(runner: runner, paths: paths, hints: hints),
                                  keys: KeyManager(paths: paths, runner: runner), hints: hints,
                                  local: fakeLocalMac(programs: ["/opt/homebrew/bin/brew", "/opt/homebrew/bin/mosh"]))
        let outcomes = await checklist.applyAutomaticFixes(for: .sample(), progress: { _ in })
        let ssh = runner.calls.filter { $0.argv.first == "ssh" }
        #expect(ssh.allSatisfy { sshRemote($0.argv) == SSHInvocation.hostCommand(["status"]) })
        let key = check(.keyAccepted, outcomes)
        #expect(key.passed == false)
        #expect(key.action == nil)
        #expect(key.fix != .passwordTab)
    }

    @Test func signInsOffIsNeverFixedAutomatically() async {
        let f = ChecklistFixture(report: with { $0.signIns = .no })
        let outcomes = await f.checklist.applyAutomaticFixes(for: .sample(), progress: { _ in })
        #expect(!f.allCalls.contains("restart-server"))
        #expect(!f.allCalls.contains("kickstart"))
        let server = check(.deskServerAndSignIns, outcomes)
        #expect(server.passed == false)
        #expect(server.action == .tab(["prepare", "mbp", "--restart-desk-server"]))
    }

    @Test func aTooNewScriptIsNotDowngraded() async {
        let f = ChecklistFixture(report: with { $0.scriptVersion = "99.0.0" })
        let outcomes = await f.checklist.applyAutomaticFixes(for: .sample(), progress: { _ in })
        #expect(!f.runner.calls.contains { $0.stdin != nil })
        #expect(!f.allCalls.contains("install-agent"))
        let script = check(.hostScriptCurrent, outcomes)
        #expect(script.passed == false)
        #expect(script.action == nil)
        #expect(script.detail == "This MacMosh is older than the script on the workhorse. Update MacMosh.")
    }

    @Test func restartDeskServerListsDesksAndNeedsTheWord() async {
        let report = with { $0.signIns = .no }.withDesks(["website", "api"])
        let f = ChecklistFixture(report: report)
        let ui = ScriptedInteraction(answers: ["restart"])
        #expect(await f.checklist.restartDeskServer(for: .sample(), ui: ui))
        #expect(ui.said.contains("Restarting the desk server closes these desks: website, api."))
        #expect(ui.asked == ["Type restart to go ahead: "])
        #expect(f.runner.calls.contains { sshRemote($0.argv) == ["~/.macmosh/macmosh-host restart-server --yes"] })

        let g = ChecklistFixture(report: report)
        let no = ScriptedInteraction(answers: ["yes"])
        #expect(await g.checklist.restartDeskServer(for: .sample(), ui: no) == false)
        #expect(!g.allCalls.contains("restart-server"))
        #expect(no.said.contains("Nothing was restarted."))
    }

    @Test func restartDeskServerStopsWhenTheWorkhorseIsNotUp() async {
        let f = ChecklistFixture(report: nil)
        let ui = ScriptedInteraction(answers: ["restart"])
        #expect(await f.checklist.restartDeskServer(for: .sample(), ui: ui) == false)
        #expect(ui.asked.isEmpty)
        #expect(!f.allCalls.contains("restart-server"))
    }

    @Test func installHomebrewShowsTheCommandAndNeedsYes() async {
        let report = with { $0.tools = [] }
        let f = ChecklistFixture(report: report)
        let ui = ScriptedInteraction(answers: ["yes"])
        let interactive = FakeInteractive()
        let code = await f.checklist.installHomebrew(for: .sample(), interactive: interactive, ui: ui)
        #expect(code == 0)
        #expect(ui.said.contains(Checklist.homebrewInstallCommand))
        #expect(ui.said.contains { $0.contains("sudo") && $0.contains("password") })
        #expect(ui.said.contains { $0.contains("downloads") && $0.contains("installer") })
        #expect(ui.asked == ["Type yes to run it: "])
        #expect(interactive.calls.count == 1)
        let argv = interactive.calls[0]
        #expect(argv.contains("-t"))
        #expect(sshRemote(argv) == [Checklist.homebrewInstallCommand])

        let g = ChecklistFixture(report: report)
        let declined = FakeInteractive()
        let no = ScriptedInteraction(answers: ["y"])
        #expect(await g.checklist.installHomebrew(for: .sample(), interactive: declined, ui: no) != 0)
        #expect(declined.calls.isEmpty)
    }

    @Test func theHomebrewCommandIsHomebrewsOwn() {
        #expect(Checklist.homebrewInstallCommand
            == "/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"")
    }

    @Test func outcomesComeInTheDesignsOrder() async {
        let f = ChecklistFixture(report: .everythingRight, workhorse: .sample(homeAddress: "192.168.1.20"))
        let outcomes = await f.checklist.run(for: .sample(homeAddress: "192.168.1.20"))
        #expect(outcomes.map(\.id) == CheckID.allCases)
        #expect(outcomes.prefix(6).allSatisfy { $0.side == .dailyMac })
        #expect(outcomes.dropFirst(6).allSatisfy { $0.side == .workhorse })
    }

    @Test func runOnlyLooks() async throws {
        let f = ChecklistFixture(report: .everythingWrong, programs: ["/opt/homebrew/bin/brew"])
        _ = await f.checklist.run(for: .sample())
        let ssh = f.runner.calls.filter { $0.argv.first == "ssh" }
        #expect(ssh.allSatisfy { sshRemote($0.argv) == SSHInvocation.hostCommand(["status"]) || sshRemote($0.argv) == ["true"] })
        #expect(!f.runner.calls.contains { $0.argv.first?.hasSuffix("brew") ?? false })
        #expect(try f.store.find("mbp").homeAddress == nil)
    }

    @Test func everythingRightPassesOrIsInformation() async {
        let f = ChecklistFixture(report: .everythingRight, workhorse: .sample(homeAddress: "192.168.1.20"))
        let outcomes = await f.checklist.run(for: .sample(homeAddress: "192.168.1.20"))
        #expect(outcomes.allSatisfy { $0.passed != false })
    }

    // MARK: On the daily Mac

    @Test func moshInstalledPasses() {
        #expect(check(.moshInstalled, daily()).passed == true)
    }

    @Test func moshMissingIsInstalledWithBrew() {
        let o = check(.moshInstalled, daily(mosh: nil))
        #expect(o.passed == false)
        #expect(o.fix == .auto)
        #expect(o.action == .automatic)
    }

    @Test func moshMissingWithoutHomebrewPointsToBrewSh() {
        let o = check(.moshInstalled, daily(mosh: nil, brew: nil))
        #expect(o.passed == false)
        guard case .steps(let steps)? = o.action else { Issue.record("no steps"); return }
        #expect(steps.joined().contains("https://brew.sh"))
    }

    @Test func terminalChosenIsInformation() {
        let o = check(.terminalChosen, daily(terminal: .iterm2))
        #expect(o.passed == nil)
        #expect(o.fix == .info)
        #expect(o.detail.contains("iTerm2"))
        #expect(check(.terminalChosen, daily(terminal: .appleTerminal)).detail.contains("Terminal"))
    }

    @Test func iTerm2IsChosenWhenInstalledUnlessTheSettingSaysOtherwise() {
        #expect(Checklist.chosenTerminal(setting: nil, iTermInstalled: true) == .iterm2)
        #expect(Checklist.chosenTerminal(setting: nil, iTermInstalled: false) == .appleTerminal)
        #expect(Checklist.chosenTerminal(setting: .appleTerminal, iTermInstalled: true) == .appleTerminal)
        #expect(Checklist.chosenTerminal(setting: .iterm2, iTermInstalled: false) == .iterm2)
    }

    @Test func identityExistsPasses() {
        #expect(check(.identityExists, daily()).passed == true)
    }

    @Test func aMissingKeyIsCreatedAutomatically() {
        let o = check(.identityExists, daily(identity: .missing))
        #expect(o.passed == false)
        #expect(o.fix == .auto)
        #expect(o.action == .automatic)
    }

    @Test func aKeyThatExistsIsNeverReplaced() {
        // A key with loose permissions, or a key the user named, is theirs to fix: never automatic.
        for o in [check(.identityExists, daily(identity: .badPermissions)),
                  check(.identityExists, daily(identity: .missing, ownKey: false))] {
            #expect(o.passed == false)
            #expect(o.action != .automatic)
            #expect(o.fix != .auto)
        }
    }

    @Test func automationAndLocalNetworkAreInformation() {
        for id in [CheckID.opensTerminalTabs, .reachesHomeNetwork] {
            let o = check(id, daily())
            #expect(o.passed == nil)
            #expect(o.fix == .info)
            #expect(o.detail.contains("macOS asks"))
        }
    }

    @Test func tailscaleConnectedPasses() {
        #expect(check(.tailscaleConnected, daily(tailscale: true)).passed == true)
    }

    @Test func tailscaleOffFailsButIsOptional() {
        let o = check(.tailscaleConnected, daily(tailscale: false))
        #expect(o.passed == false)
        #expect(o.fix == .info)
        #expect(o.detail.contains("Optional"))
        let missing = check(.tailscaleConnected, daily(tailscale: nil))
        #expect(missing.passed == nil)
        #expect(missing.detail.contains("https://tailscale.com/download"))
    }

    // MARK: On the workhorse

    @Test func remoteLoginOnPassesWhenSomethingAnswers() {
        let refused = CheckResult.sample(.notSetUp(.notPaired), probes: ProbeSet(main: .authDenied(methods: ["publickey", "password"])))
        let otherKey = CheckResult.sample(.cantVerify, probes: ProbeSet(main: .timedOut, home: .hostKeyChanged))
        for r in [answered(.everythingRight), refused, otherKey] {
            #expect(check(.remoteLoginOn, r).passed == true)
        }
    }

    @Test func remoteLoginFailsWhenNothingAnswers() {
        let r = CheckResult.sample(.cantReach(.nothingAnswers),
                                   probes: ProbeSet(main: .timedOut, home: .refused, local: .unresolved))
        let o = check(.remoteLoginOn, r)
        #expect(o.passed == false)
        #expect(o.fix == .atWorkhorse)
        guard case .steps(let steps)? = o.action else { Issue.record("no steps"); return }
        #expect(steps.joined().contains("System Settings > General > Sharing > Remote Login"))
    }

    @Test func screenSharingOnPasses() {
        #expect(check(.screenSharingOn, answered(.everythingRight)).passed == true)
    }

    @Test func screenSharingOffFails() {
        let o = check(.screenSharingOn, answered(with { $0.screenSharing = .no }))
        #expect(o.passed == false)
        #expect(o.fix == .atWorkhorse)
    }

    @Test func screenSharingUnknownIsInformation() {
        let o = check(.screenSharingOn, answered(with { $0.screenSharing = .unknown }))
        #expect(o.passed == nil)
        #expect(o.detail == "MacMosh couldn't tell. Look in System Settings > General > Sharing.")
    }

    @Test func keyAcceptedPasses() {
        #expect(check(.keyAccepted, answered(.everythingRight)).passed == true)
    }

    @Test func aRefusedKeyOpensThePairTab() {
        let r = CheckResult.sample(.notSetUp(.notPaired), probes: ProbeSet(main: .authDenied(methods: ["publickey", "password"])),
                                   answeredAt: nil)
        let o = check(.keyAccepted, r)
        #expect(o.passed == false)
        #expect(o.fix == .passwordTab)
        #expect(o.action == .tab(["pair", "mbp"]))
    }

    @Test func aKeyThatSignedInPassesEvenWhenTheScriptIsMissing() {
        let r = CheckResult.sample(.notSetUp(.hostScriptMissing),
                                   probes: ProbeSet(main: .remoteFailed(exitCode: 127, stderr: "not found")),
                                   answeredAt: "workhorse")
        #expect(check(.keyAccepted, r).passed == true)
    }

    @Test func aDifferentHostKeyNeverOffersAPasswordTab() {
        let r = CheckResult.sample(.cantVerify, probes: ProbeSet(main: .hostKeyChanged))
        for o in onWorkhorse(r) {
            #expect(o.fix != .passwordTab)
            if case .tab? = o.action { Issue.record("\(o.id) offers a tab while the host key differs") }
            #expect(o.action != .automatic)
        }
    }

    @Test func osAndChipIsInformation() {
        let new = check(.osAndChip, answered(.everythingRight))
        #expect(new.passed == nil)
        #expect(new.detail.contains("27.3"))
        #expect(new.detail.contains("Restart recovery over ssh is offered"))
        let old = check(.osAndChip, answered(with { $0.osVersion = "15.6" }))
        #expect(old.detail.contains("unlock it at the Mac"))
    }

    @Test func toolsInstalledPasses() {
        #expect(check(.toolsInstalled, answered(.everythingRight)).passed == true)
    }

    @Test func missingToolsWithHomebrewAreInstalledAutomatically() {
        let o = check(.toolsInstalled, answered(.everythingWrong, state: .notSetUp(.deskServerDown)))
        #expect(o.passed == false)
        #expect(o.fix == .auto)
        #expect(o.action == .automatic)
    }

    @Test func missingHomebrewOpensThePasswordTab() {
        let o = check(.toolsInstalled, answered(with { $0.tools = [] }))
        #expect(o.passed == false)
        #expect(o.fix == .passwordTab)
        #expect(o.action == .tab(["prepare", "mbp", "--install-homebrew"]))
    }

    @Test func hostScriptCurrentPasses() {
        #expect(check(.hostScriptCurrent, answered(.everythingRight)).passed == true)
    }

    @Test func anOldOrMissingScriptIsInstalledAutomatically() {
        let old = check(.hostScriptCurrent, answered(with { $0.scriptVersion = "0.0.1" }))
        #expect(old.passed == false)
        #expect(old.action == .automatic)
        let missing = CheckResult.sample(.notSetUp(.hostScriptMissing),
                                         probes: ProbeSet(main: .remoteFailed(exitCode: 127, stderr: "not found")),
                                         answeredAt: "workhorse")
        let o = check(.hostScriptCurrent, missing, installed: .absent)
        #expect(o.passed == false)
        #expect(o.action == .automatic)
        let noAgent = check(.hostScriptCurrent, answered(with { $0.agentInstalled = false }))
        #expect(noAgent.passed == false)
        #expect(noAgent.action == .automatic)
    }

    @Test func aScriptWhoseVersionCantBeReadIsLeftAlone() {
        let r = CheckResult.sample(.notSetUp(.hostScriptOutdated), probes: ProbeSet(main: .ok(stdout: "macmosh-host\t2\t1.0.0\n")),
                                   answeredAt: "workhorse")
        let o = check(.hostScriptCurrent, r, installed: .unreadable)
        #expect(o.passed == false)
        #expect(o.action != .automatic)
    }

    @Test func deskServerAndSignInsPasses() {
        #expect(check(.deskServerAndSignIns, answered(.everythingRight)).passed == true)
    }

    @Test func aStoppedServerWithSomebodyLoggedInIsStartedAutomatically() {
        let o = check(.deskServerAndSignIns, answered(with { $0.serverUp = false; $0.signIns = .unknown },
                                                      state: .notSetUp(.deskServerDown)))
        #expect(o.passed == false)
        #expect(o.fix == .auto)
        #expect(o.action == .automatic)
    }

    @Test func aStoppedServerWithNobodyLoggedInSaysLogIn() {
        let o = check(.deskServerAndSignIns, answered(with { $0.serverUp = false; $0.consoleUser = nil },
                                                      state: .waitingForLogin))
        #expect(o.passed == false)
        #expect(o.fix == .atWorkhorse)
        #expect(o.action == .steps(["Log in at the Mac or with Log in…"]))
    }

    @Test func signInsOffOpensTheRestartTab() {
        let o = check(.deskServerAndSignIns, answered(with { $0.signIns = .no }, state: .ready(signIns: false)))
        #expect(o.passed == false)
        #expect(o.action == .tab(["prepare", "mbp", "--restart-desk-server"]))
    }

    @Test func staysAwakePasses() {
        #expect(check(.staysAwake, answered(.everythingRight)).passed == true)
    }

    @Test func staysAwakeFailsAndOpensThePowerTab() {
        for power in [HostStatus.Power(sleepOnPower: 10, wakeForNetwork: 1), .init(sleepOnPower: 0, wakeForNetwork: 0),
                      .init(sleepOnPower: nil, wakeForNetwork: nil)] {
            let o = check(.staysAwake, answered(with { $0.power = power }))
            #expect(o.passed == false)
            #expect(o.fix == .passwordTab)
            #expect(o.action == .tab(["power", "mbp", "awake"]))
        }
    }

    @Test func restartsAfterPowerCutPassesOnADesktop() {
        #expect(check(.restartsAfterPowerCut, answered(.everythingRight)).passed == true)
    }

    @Test func restartsAfterPowerCutFailsOnADesktop() {
        let o = check(.restartsAfterPowerCut, answered(with { $0.power.autoRestart = 0 }))
        #expect(o.passed == false)
        #expect(o.fix == .passwordTab)
        #expect(o.action == .tab(["power", "mbp", "autorestart"]))
    }

    @Test func restartsAfterPowerCutIsInformationOnALaptop() {
        let o = check(.restartsAfterPowerCut, answered(with {
            $0.battery = .init(present: true, onAC: true, percent: 80)
            $0.power.autoRestart = nil
        }))
        #expect(o.passed == nil)
        #expect(o.action == nil)
    }

    @Test func fileVaultStatusIsInformation() {
        for value in [HostStatus.Tri.yes, .no, .unknown] {
            let o = check(.fileVaultStatus, answered(with { $0.fileVault = value }))
            #expect(o.passed == nil)
            #expect(o.fix == .info)
            #expect(o.action == nil)
            #expect(o.detail.contains("never changes"))
        }
    }

    @Test func homeAddressRecordedPasses() {
        #expect(check(.homeAddressRecorded, answered(.everythingRight), saved: .sample(homeAddress: "192.168.1.20")).passed == true)
    }

    @Test func aHomeAddressNotSavedYetIsRecordedAutomatically() {
        let o = check(.homeAddressRecorded, answered(.everythingRight), saved: .sample())
        #expect(o.passed == false)
        #expect(o.fix == .auto)
        #expect(o.action == .automatic)
    }

    @Test func firewallOffIsInformation() {
        let o = check(.firewall, answered(.everythingRight))
        #expect(o.passed == nil)
        #expect(!o.detail.contains("mosh"))
    }

    @Test func firewallOnSaysMoshMayBeBlocked() {
        let o = check(.firewall, answered(with { $0.firewall = .yes }))
        #expect(o.passed == nil)
        #expect(o.fix == .info)
        #expect(o.detail.contains("mosh may be blocked"))
    }

    @Test func protectedFoldersIsOptionalAndAtTheWorkhorse() {
        let o = check(.protectedFolders, answered(.everythingRight))
        #expect(o.passed == nil)
        #expect(o.fix == .atWorkhorse)
        guard case .steps(let steps)? = o.action else { Issue.record("no steps"); return }
        #expect(steps.joined().contains("Full Disk Access"))
        #expect(steps.joined().contains("/opt/homebrew/bin/tmux"))
    }

    @Test func withoutAReportTheReportsChecksSayTheyCouldntTell() {
        let r = CheckResult.sample(.cantReach(.nothingAnswers), probes: ProbeSet(main: .timedOut))
        for id in [CheckID.screenSharingOn, .toolsInstalled, .deskServerAndSignIns, .staysAwake, .restartsAfterPowerCut,
                   .fileVaultStatus, .firewall] {
            let o = check(id, r)
            #expect(o.passed == nil)
            #expect(o.action == nil)
        }
    }

    // MARK: Words and JSON

    @Test func textUsesTheThreeMarks() {
        let outcomes = [
            CheckOutcome(id: .moshInstalled, side: .dailyMac, passed: true, fix: .auto, title: "mosh is installed",
                         detail: "/opt/homebrew/bin/mosh", action: nil),
            CheckOutcome(id: .staysAwake, side: .workhorse, passed: false, fix: .passwordTab,
                         title: "It stays awake on power", detail: "It sleeps after 10 minutes.",
                         action: .tab(["power", "mbp", "awake"])),
            CheckOutcome(id: .firewall, side: .workhorse, passed: nil, fix: .info, title: "The macOS firewall",
                         detail: "It is off.", action: nil),
        ]
        let lines = ChecklistFormat.text(outcomes).split(separator: "\n").map(String.init)
        #expect(lines.contains("✓ mosh is installed"))
        #expect(lines.contains("✗ It stays awake on power: It sleeps after 10 minutes."))
        #expect(lines.contains("   Fix: run macmosh power mbp awake"))
        #expect(lines.contains("• The macOS firewall: It is off."))
    }

    @Test func textNumbersTheStepsAndNamesTheAutomaticFix() {
        let outcomes = [
            CheckOutcome(id: .remoteLoginOn, side: .workhorse, passed: false, fix: .atWorkhorse, title: "Remote Login is on",
                         detail: "Nothing answered.", action: .steps(["Open System Settings.", "Turn on Remote Login."])),
            CheckOutcome(id: .identityExists, side: .dailyMac, passed: false, fix: .auto, title: "MacMosh's own ssh key exists",
                         detail: "Missing.", action: .automatic),
        ]
        let text = ChecklistFormat.text(outcomes)
        #expect(text.contains("   Fix, at the workhorse:\n     1. Open System Settings.\n     2. Turn on Remote Login."))
        #expect(text.contains("   Fix: macmosh prepare --fix does this."))
    }

    @Test func jsonHasEveryOutcome() throws {
        let outcomes = onWorkhorse(answered(.everythingWrong, state: .notSetUp(.deskServerDown)))
        let data = Data(try ChecklistFormat.json(outcomes).utf8)
        let decoded = try JSONDecoder().decode([CheckOutcome].self, from: data)
        #expect(decoded == outcomes)
        let raw = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let awake = try #require(raw.first { $0["id"] as? String == "staysAwake" })
        let action = try #require(awake["action"] as? [String: Any])
        #expect(action["kind"] as? String == "tab")
        #expect(action["arguments"] as? [String] == ["power", "mbp", "awake"])
    }
}
