import Foundation
import Testing
@testable import MacMoshKit

/// Naming one window of a desk from the app (issue 144): the script's `window-name` call, and `DeskFlow.nameWindow`,
/// which the terminal's `desk name-window` and the window's sheet both run.
private let website = DeskName("website")!

private func remote(_ runner: FakeRunner, _ index: Int = 0) -> String? {
    runner.calls[index].argv.last
}

private func scriptEnds(_ exitCode: Int32, stderr: String = "") -> FakeRunner {
    FakeRunner { _ in CommandResult(exitCode: exitCode, stdout: "", stderr: stderr, timedOut: false) }
}

private let attic = Workhorse.sample(id: "attic", name: "Attic")

/// Attic Ready with the report of the menu design's example (website: claude @1, zsh @2, vim @3; blog: zsh @8),
/// from a script of that version.
private func checked(_ version: String = "0.11.0") -> CheckResult {
    .sample(.ready(signIns: true), workhorse: attic, status: windowsReport(version: version), answeredAt: "192.168.1.20")
}

private func flow(_ runner: CommandRunner, _ wording: DeskFormat.Wording = .terminal) -> DeskFlow {
    DeskFlow(commands: HostCommands(runner: runner, paths: .test), wording: wording)
}

private let closed = "That window has closed.\n"

@Suite struct NameWindowFlowTests {
    // MARK: the call

    @Test func theArgumentsAreTheDeskTheWindowsIdAndTheNameOrAuto() {
        #expect(HostCommands.nameWindowArguments(desk: website, window: "@2", to: .named(WindowName("api")!))
                == ["window-name", "website", "@2", "api"])
        #expect(HostCommands.nameWindowArguments(desk: website, window: "@2", to: .named(WindowName("front end")!))
                == ["window-name", "website", "@2", "front end"])
        #expect(HostCommands.nameWindowArguments(desk: website, window: "@12", to: .afterItsProgram)
                == ["window-name", "website", "@12", "--auto"])
    }

    /// The name is one argument, quoted once for the remote shell like every other.
    @Test func theNameTravelsAsOneQuotedArgument() async throws {
        let runner = FakeRunner { _ in FakeRunner.ok() }
        let hc = HostCommands(runner: runner, paths: .test)
        try await hc.nameWindow(on: attic, address: "192.168.1.20", desk: website, window: "@2", to: .named(WindowName("api")!))
        try await hc.nameWindow(on: attic, address: "192.168.1.20", desk: website, window: "@2", to: .named(WindowName("front end")!))
        try await hc.nameWindow(on: attic, address: "192.168.1.20", desk: website, window: "@2", to: .named(WindowName("notes 2.0 - draft_1")!))
        try await hc.nameWindow(on: attic, address: "192.168.1.20", desk: website, window: "@2", to: .afterItsProgram)
        #expect(remote(runner, 0) == "~/.macmosh/macmosh-host window-name website @2 api")
        #expect(remote(runner, 1) == "~/.macmosh/macmosh-host window-name website @2 'front end'")
        #expect(remote(runner, 2) == "~/.macmosh/macmosh-host window-name website @2 'notes 2.0 - draft_1'")
        #expect(remote(runner, 3) == "~/.macmosh/macmosh-host window-name website @2 --auto")
        // The ssh arguments around it, for the name with a space and a full stop.
        let call = runner.calls[2]
        #expect(call.argv[0] == "ssh")
        #expect(sshTarget(call.argv) == "alex@192.168.1.20")
        #expect(sshRemote(call.argv) == ["~/.macmosh/macmosh-host window-name website @2 'notes 2.0 - draft_1'"])
        #expect(call.argv.contains("BatchMode=yes"))
        #expect(!call.argv.contains("-t"))
        #expect(call.stdin == nil)
        #expect(call.timeout == .seconds(15))
    }

    @Test func exitFourWithTheScriptsWordsIsAClosedWindowAndOtherwiseNoSuchDesk() async {
        let hc = HostCommands(runner: scriptEnds(4, stderr: closed), paths: .test)
        await #expect(throws: WindowNameError.windowClosed) {
            try await hc.nameWindow(on: attic, address: "a", desk: website, window: "@2", to: .afterItsProgram)
        }
        let none = HostCommands(runner: scriptEnds(4, stderr: "macmosh-host: no such desk: website\n"), paths: .test)
        await #expect(throws: HostCommandError.noSuchDesk) {
            try await none.nameWindow(on: attic, address: "a", desk: website, window: "@2", to: .afterItsProgram)
        }
    }

    // MARK: the flow, with everything given

    @Test func withEverythingGivenItCallsOnceAndAsksNothing() async {
        let runner = FakeRunner { _ in FakeRunner.ok() }
        let ui = ScriptedInteraction(answers: ["should not be read"])
        let result = await flow(runner).nameWindow(checked(), desk: "website", window: "@2", to: .name("front end"), ui: ui)
        #expect(result == .success)
        #expect(ui.asked.isEmpty)
        #expect(runner.calls.count == 1)
        #expect(remote(runner) == "~/.macmosh/macmosh-host window-name website @2 'front end'")
        #expect(ui.said == ["Named window 1 of website \"front end\" on Attic."])

        let auto = ScriptedInteraction()
        #expect(await flow(runner).nameWindow(checked(), desk: "website", window: "@3", to: .afterItsProgram, ui: auto) == .success)
        #expect(remote(runner, 1) == "~/.macmosh/macmosh-host window-name website @3 --auto")
        #expect(auto.said == ["Window 2 of website follows its program's name again on Attic."])
    }

    /// A window the report doesn't list is still sent (the script decides), and named by its id.
    @Test func aWindowTheReportDoesntListIsNamedByItsId() async {
        let runner = FakeRunner { _ in FakeRunner.ok() }
        let ui = ScriptedInteraction()
        #expect(await flow(runner).nameWindow(checked(), desk: "website", window: "@40", to: .name("logs"), ui: ui) == .success)
        #expect(ui.said == ["Named window @40 of website \"logs\" on Attic."])
    }

    @Test func theWindowClosedComesBackAsAPlainSentence() async {
        for wording in [DeskFormat.Wording.terminal, .window] {
            let result = await flow(scriptEnds(4, stderr: closed), wording)
                .nameWindow(checked(), desk: "website", window: "@2", to: .name("api"), ui: ScriptedInteraction())
            #expect(result == .failure("That window has closed."))
        }
    }

    @Test func noSuchDeskIsTheWorkhorsesWords() async {
        let result = await flow(scriptEnds(4, stderr: "macmosh-host: no such desk: website\n"))
            .nameWindow(checked(), desk: "website", window: "@2", to: .name("api"), ui: ScriptedInteraction())
        #expect(result == .failure(DeskFormat.message(.noSuchDesk, workhorse: attic)))
        let window = await flow(scriptEnds(4, stderr: "macmosh-host: no such desk: website\n"), .window)
            .nameWindow(checked(), desk: "website", window: "@2", to: .name("api"), ui: ScriptedInteraction())
        #expect(window == .failure("Attic has no desk with that name now."))
    }

    @Test func aTimeoutIsTheUsualNoAnswer() async {
        let runner = FakeRunner { _ in CommandResult(exitCode: -1, stdout: "", stderr: "", timedOut: true) }
        let result = await flow(runner, .window)
            .nameWindow(checked(), desk: "website", window: "@2", to: .name("api"), ui: ScriptedInteraction())
        #expect(result == .failure(HostCommands.noAnswer))
    }

    /// Before 0.11.0 the script has no `window-name`: nothing is sent.
    @Test func aScriptTooOldNeverCalls() async {
        let runner = FakeRunner { _ in FakeRunner.ok() }
        for version in ["0.10.0", "0.8.0", ""] {
            let ui = ScriptedInteraction(answers: ["1", "api"])
            let result = await flow(runner).nameWindow(checked(version), desk: "website", window: nil, to: nil, ui: ui)
            #expect(result.code == 1)
            #expect(result.reason == DeskFormat.nameWindowNeedsNewerScript(attic, version: version, for: .terminal))
            #expect(ui.asked.isEmpty)
        }
        #expect(runner.calls.isEmpty)
        #expect(DeskFormat.nameWindowNeedsNewerScript(attic, version: "0.10.0", for: .terminal)
                == "Naming a window needs the workhorse script 0.11.0 or newer, and Attic has 0.10.0. Update it with: macmosh prepare attic --fix")
        #expect(DeskFormat.nameWindowNeedsNewerScript(attic, version: "", for: .window)
                == "Naming a window needs the workhorse script 0.11.0 or newer, and Attic has an older one.")
    }

    @Test func aWorkhorseThatIsNotReadyStopsBeforeSSH() async {
        let runner = FakeRunner { _ in FakeRunner.ok() }
        let locked = CheckResult.sample(.locked, workhorse: attic, status: windowsReport(version: "0.11.0"))
        let result = await flow(runner).nameWindow(locked, desk: "website", window: "@2", to: .name("api"), ui: ScriptedInteraction())
        #expect(result.code == 1)
        #expect(result.reason == DeskFormat.notReady(locked))
        #expect(runner.calls.isEmpty)
    }

    @Test func aBadNameOrWindowGivenIsRefusedNotAsked() async {
        let runner = FakeRunner { _ in FakeRunner.ok() }
        for name in ["--auto", "-n", "a#b", " lead", ""] {
            let ui = ScriptedInteraction(answers: ["api"])
            let result = await flow(runner).nameWindow(checked(), desk: "website", window: "@2", to: .name(name), ui: ui)
            #expect(result == .failure(WindowName.problem(name)!), "\(name)")
            #expect(ui.asked.isEmpty)
        }
        for window in ["2", "@", "@x", "website", "@-1"] {
            let result = await flow(runner).nameWindow(checked(), desk: "website", window: window, to: .name("api"),
                                                       ui: ScriptedInteraction())
            #expect(result == .failure("A window is given by its id, such as @3."), "\(window)")
        }
        let badDesk = await flow(runner).nameWindow(checked(), desk: "web site", window: "@2", to: .name("api"), ui: ScriptedInteraction())
        #expect(badDesk == .failure(DeskFormat.nameRule))
        #expect(runner.calls.isEmpty)
    }

    // MARK: the form that asks

    @Test func withSeveralWindowsItListsThemAsksWhichThenTheName() async {
        let runner = FakeRunner { _ in FakeRunner.ok() }
        let ui = ScriptedInteraction(answers: ["1", "front end"])
        let result = await flow(runner).nameWindow(checked(), desk: "website", window: nil, to: nil, ui: ui)
        #expect(result == .success)
        #expect(ui.said == ["The windows of website:", "  0  claude", "  1  zsh", "  2  vim",
                            "Named window 1 of website \"front end\" on Attic."])
        #expect(ui.asked == ["Which window? Type its number: ",
                             "Name for window 1 (zsh), or Enter alone to let it follow its program's name again: "])
        #expect(remote(runner) == "~/.macmosh/macmosh-host window-name website @2 'front end'")
    }

    @Test func withOneWindowItAsksOnlyTheName() async {
        let runner = FakeRunner { _ in FakeRunner.ok() }
        let ui = ScriptedInteraction(answers: ["notes"])
        let result = await flow(runner).nameWindow(checked(), desk: "blog", window: nil, to: nil, ui: ui)
        #expect(result == .success)
        #expect(ui.asked == ["Name for window 0 (zsh), or Enter alone to let it follow its program's name again: "])
        #expect(remote(runner) == "~/.macmosh/macmosh-host window-name blog @8 notes")
    }

    @Test func anEmptyAnswerForTheWindowCancels() async {
        let runner = FakeRunner { _ in FakeRunner.ok() }
        let ui = ScriptedInteraction(answers: ["", "api"])
        let result = await flow(runner).nameWindow(checked(), desk: "website", window: nil, to: nil, ui: ui)
        #expect(result == .failure("Nothing changed."))
        #expect(ui.asked.count == 1)
        #expect(runner.calls.isEmpty)
    }

    @Test func anEmptyAnswerForTheNameLetsTheWindowFollowItsProgram() async {
        let runner = FakeRunner { _ in FakeRunner.ok() }
        let ui = ScriptedInteraction(answers: ["2", ""])
        let result = await flow(runner).nameWindow(checked(), desk: "website", window: nil, to: nil, ui: ui)
        #expect(result == .success)
        #expect(remote(runner) == "~/.macmosh/macmosh-host window-name website @3 --auto")
        #expect(ui.said.last == "Window 2 of website follows its program's name again on Attic.")
    }

    /// End of input (Ctrl-D, or stdin closed) at the name question is not "Enter alone": it changes nothing and
    /// sends nothing, for a one-window desk (where the name is the only question) and for a given window.
    @Test func endOfInputAtTheNameChangesNothing() async {
        let runner = FakeRunner { _ in FakeRunner.ok() }
        let ui = ScriptedInteraction(answers: [])
        #expect(await flow(runner).nameWindow(checked(), desk: "blog", window: nil, to: nil, ui: ui) == .failure("Nothing changed."))
        #expect(ui.asked == ["Name for window 0 (zsh), or Enter alone to let it follow its program's name again: "])
        let given = ScriptedInteraction(answers: [])
        #expect(await flow(runner).nameWindow(checked(), desk: "website", window: "@3", to: nil, ui: given) == .failure("Nothing changed."))
        #expect(runner.calls.isEmpty)
    }

    /// The window's own quiet stand-in answers no question, so a name left out sends nothing.
    @Test func aQuietInteractionAtTheNameSendsNothing() async {
        let runner = FakeRunner { _ in FakeRunner.ok() }
        let result = await flow(runner, .window).nameWindow(checked(), desk: "website", window: "@3", to: nil, ui: QuietInteraction())
        #expect(result == .failure("Nothing changed."))
        #expect(runner.calls.isEmpty)
    }

    /// The window is given: only the name is asked.
    @Test func aGivenWindowIsNotAskedFor() async {
        let runner = FakeRunner { _ in FakeRunner.ok() }
        let ui = ScriptedInteraction(answers: ["api"])
        #expect(await flow(runner).nameWindow(checked(), desk: "website", window: "@1", to: nil, ui: ui) == .success)
        #expect(ui.asked == ["Name for window 0 (claude), or Enter alone to let it follow its program's name again: "])
        #expect(remote(runner) == "~/.macmosh/macmosh-host window-name website @1 api")
    }

    /// The name is given: only the window is asked.
    @Test func aGivenNameIsNotAskedFor() async {
        let runner = FakeRunner { _ in FakeRunner.ok() }
        let ui = ScriptedInteraction(answers: ["0"])
        #expect(await flow(runner).nameWindow(checked(), desk: "website", window: nil, to: .afterItsProgram, ui: ui) == .success)
        #expect(ui.asked == ["Which window? Type its number: "])
        #expect(remote(runner) == "~/.macmosh/macmosh-host window-name website @1 --auto")
    }

    /// A number that isn't a window's is said so and asked again, up to three tries; then it stops.
    @Test func aBadNumberIsAskedAgainUpToThreeTimes() async {
        let runner = FakeRunner { _ in FakeRunner.ok() }
        let ui = ScriptedInteraction(answers: ["7", "zsh", "1", "api"])
        #expect(await flow(runner).nameWindow(checked(), desk: "website", window: nil, to: nil, ui: ui) == .success)
        #expect(ui.said.contains("There is no window 7 in website."))
        #expect(ui.said.contains("Type the number of a window from the list."))
        #expect(remote(runner) == "~/.macmosh/macmosh-host window-name website @2 api")

        let three = ScriptedInteraction(answers: ["7", "8", "x", "1"])
        let stopped = await flow(runner).nameWindow(checked(), desk: "website", window: nil, to: nil, ui: three)
        #expect(stopped == .failure("That wasn't a window's number three times, so MacMosh stopped."))
        #expect(three.asked.count == 3)
        #expect(runner.calls.count == 1)
    }

    /// A name that breaks the rule is said why and asked again, up to three tries; then it stops with the rule.
    @Test func aBadNameIsAskedAgainUpToThreeTimes() async {
        let runner = FakeRunner { _ in FakeRunner.ok() }
        let ui = ScriptedInteraction(answers: ["1", "-x", "front end"])
        #expect(await flow(runner).nameWindow(checked(), desk: "website", window: nil, to: nil, ui: ui) == .success)
        #expect(ui.said.contains("A window name can't start with -."))
        #expect(remote(runner) == "~/.macmosh/macmosh-host window-name website @2 'front end'")

        let three = ScriptedInteraction(answers: ["1", "a#b", " lead", "--auto", "api"])
        let stopped = await flow(runner).nameWindow(checked(), desk: "website", window: nil, to: nil, ui: three)
        #expect(stopped == .failure("That wasn't a window name three times, so MacMosh stopped. \(WindowName.rule)"))
        #expect(three.asked.count == 4)
        #expect(runner.calls.count == 1)
    }

    @Test func aDeskTheReportDoesntHaveIsNotAskedAbout() async {
        let runner = FakeRunner { _ in FakeRunner.ok() }
        let ui = ScriptedInteraction(answers: ["1", "api"])
        let result = await flow(runner).nameWindow(checked(), desk: "garden", window: nil, to: nil, ui: ui)
        #expect(result == .failure(DeskFormat.message(.noSuchDesk, workhorse: attic)))
        #expect(ui.asked.isEmpty)
        #expect(runner.calls.isEmpty)
    }

    /// A window with no name reads `(no name)` in the list and the question.
    @Test func aWindowWithNoNameSaysSo() async {
        var report = windowsReport(version: "0.11.0")
        report.desks[0].windows[1].name = ""
        let check = CheckResult.sample(.ready(signIns: true), workhorse: attic, status: report, answeredAt: "a")
        let ui = ScriptedInteraction(answers: ["1", "api"])
        _ = await flow(FakeRunner { _ in FakeRunner.ok() }).nameWindow(check, desk: "website", window: nil, to: nil, ui: ui)
        #expect(ui.said.contains("  1  (no name)"))
        #expect(ui.asked.last == "Name for window 1, or Enter alone to let it follow its program's name again: ")
    }
}
