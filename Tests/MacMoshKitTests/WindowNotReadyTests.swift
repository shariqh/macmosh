import Foundation
import Testing
@testable import MacMoshKit

private let attic = Workhorse.sample(id: "attic", name: "Attic")

/// Every state that is not Ready, each reason and problem included, Locked both on a Mac that can be unlocked over
/// ssh and on one that can't (macOS 15), and Can't reach both with and without a time it was last seen.
private func notReadyChecks() -> [CheckResult] {
    var seen = attic
    seen.lastSeen = utcDate(2027, 1, 15, 14, 2)
    let older = Workhorse.sample(id: "attic", name: "Attic", osVersion: "15.0")
    var states: [(WorkhorseState, Workhorse)] = [(.waitingForLogin, attic), (.locked, attic), (.locked, older),
                                                 (.cantVerify, attic)]
    for reason in [UnreachableReason.tailscaleOff, .noNetwork, .otherVPN, .awayAndOffline, .nothingAnswers] {
        states.append((.cantReach(reason), attic))
        states.append((.cantReach(reason), seen))
    }
    for problem in [SetupProblem.notPaired, .identityUnusable, .hostScriptMissing, .hostScriptOutdated,
                    .unreadableReport, .deskServerDown] {
        states.append((.notSetUp(problem), attic))
    }
    return states.map { CheckResult.sample($0.0, workhorse: $0.1) }
}

/// When the workhorse stops being Ready while a form is open, the window says why on one line with no `macmosh`
/// command (issue #147); the terminal's words are unchanged.
@Suite struct WindowNotReadyTests {
    @Test func everyStateIsOneLineWithNoCommandInTheWindow() {
        for check in notReadyChecks() {
            let line = DeskFormat.notReady(check, for: .window, now: formatNow, timeZone: formatZone)
            #expect(!line.contains("\n"), "\(check.state): \(line)")
            #expect(!line.contains("macmosh "), "\(check.state): \(line)")
            #expect(!line.contains("Run:") && !line.contains("--"), "\(check.state): \(line)")
            #expect(line.hasPrefix(StatusFormat.headline(check) + "."), "\(check.state): \(line)")
        }
    }

    @Test func theTerminalsWordsAreUnchangedForEveryState() {
        for check in notReadyChecks() {
            let hint = StatusFormat.hint(check, now: formatNow, timeZone: formatZone)
            let terminal = [StatusFormat.headline(check)] + (hint.map { [$0] } ?? [])
            #expect(DeskFormat.notReady(check, now: formatNow, timeZone: formatZone) == terminal.joined(separator: "\n"))
            #expect(DeskFormat.notReady(check, for: .terminal, now: formatNow, timeZone: formatZone)
                    == terminal.joined(separator: "\n"))
        }
    }

    /// Each state's sentence in the window: the headline, then the hint's sentences that name no command.
    @Test(arguments: [
        (WorkhorseState.waitingForLogin, "Attic · Waiting for login. It is on and unlocked, but nobody has logged in."),
        (.locked, "Attic · Locked after a restart. The disk is locked until someone types the Mac's password."),
        (.cantVerify, "Attic · Can't verify it. Something answers at its address with a different key. Stop. Don't type a password. Check or unlock at the Mac."),
        (.cantReach(.tailscaleOff), "Attic · Can't reach it. Tailscale is off on this Mac."),
        (.cantReach(.noNetwork), "Attic · Can't reach it. This Mac has no network."),
        (.cantReach(.otherVPN), "Attic · Can't reach it. Another VPN is running on this Mac."),
        (.cantReach(.awayAndOffline), "Attic · Can't reach it. Tailscale says it is offline and you are away from home. It may have restarted: its home address is out of reach from here."),
        (.cantReach(.nothingAnswers), "Attic · Can't reach it. Nothing answers at either address: it is off, asleep or disconnected. If it just restarted, its home address may have changed."),
        (.notSetUp(.notPaired), "Attic · Not paired."),
        (.notSetUp(.identityUnusable), "Attic · Your ssh key is locked. MacMosh can't use ~/.ssh/macmosh_ed25519."),
        (.notSetUp(.hostScriptMissing), "Attic · Needs setting up."),
        (.notSetUp(.hostScriptOutdated), "Attic · Needs setting up."),
        (.notSetUp(.unreadableReport), "Attic · Couldn't read its status. It answered, but its status report was incomplete. MacMosh will try again."),
        (.notSetUp(.deskServerDown), "Attic · Desk server is off."),
    ])
    func eachStatesSentenceInTheWindow(state: WorkhorseState, sentence: String) {
        #expect(DeskFormat.notReady(.sample(state, workhorse: attic), for: .window, now: formatNow, timeZone: formatZone)
                == sentence)
    }

    /// Only a sentence that names a `macmosh` command is dropped, never one that names the key file, whatever the
    /// file is called (review of pull request #150).
    @Test func theKeyFileSentenceStaysWhateverTheFileIsCalled() {
        for file in [nil, "~/.ssh/macmosh_ed25519", "~/.ssh/id_ed25519"] {
            let w = Workhorse.sample(id: "attic", name: "Attic", identityFile: file)
            let line = DeskFormat.notReady(.sample(.notSetUp(.identityUnusable), workhorse: w), for: .window,
                                           now: formatNow, timeZone: formatZone)
            #expect(line == "Attic · Your ssh key is locked. MacMosh can't use \(file ?? "~/.ssh/macmosh_ed25519").")
        }
    }

    @Test func lastSeenStaysInTheWindowsSentence() {
        var seen = attic
        seen.lastSeen = utcDate(2027, 1, 15, 14, 2)
        #expect(DeskFormat.notReady(.sample(.cantReach(.tailscaleOff), workhorse: seen), for: .window,
                                    now: formatNow, timeZone: formatZone)
                == "Attic · Can't reach it. Last seen 14:02. Tailscale is off on this Mac.")
    }

    /// The window's DeskFlow stops with the window's sentence; the terminal's with the headline and hint.
    @Test func theWindowsFlowStopsWithTheWindowsSentence() async {
        let runner = FakeRunner { _ in FakeRunner.ok() }
        let window = DeskFlow(commands: HostCommands(runner: runner, paths: .test), wording: .window)
        let check = CheckResult.sample(.notSetUp(.deskServerDown), workhorse: attic)
        let made = await window.newDesk(check, request: NewDeskRequest(name: "web", folder: "/x"), ui: QuietInteraction())
        #expect(made.reason == "Attic · Desk server is off.")
        let renamed = await window.renameDesk(check, from: "web", to: "notes", ui: QuietInteraction())
        #expect(renamed.reason == "Attic · Desk server is off.")
        let folders = await window.folders(check)
        #expect(folders.reason == "Attic · Desk server is off.")
        let terminal = DeskFlow(commands: HostCommands(runner: runner, paths: .test))
        let typed = await terminal.newWindow(check, desk: "web", ui: ScriptedInteraction())
        #expect(typed.reason == "Attic · Desk server is off\nRun: macmosh prepare attic --fix")
        #expect(runner.calls.isEmpty)
    }

    // MARK: exit 6

    /// The script's exit 6 in the window: one line, with no terminal words.
    @Test func theWindowsSentenceForExit6IsOneShortLine() {
        let line = DeskFormat.message(.badInput, workhorse: attic, for: .window)
        #expect(line == "Attic didn't accept the name or the folder. The folder must exist on Attic.")
        #expect(!line.contains("\n") && !line.contains("macmosh"))
        // The terminal's is unchanged.
        #expect(DeskFormat.message(.badInput, workhorse: attic)
                == "Attic didn't accept that. A desk name uses letters, digits, - and _ only; a folder must exist on Attic and be a full path or start with ~; a startup command can't contain a tab or a new line.")
    }
}
