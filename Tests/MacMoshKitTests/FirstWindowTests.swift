import Foundation
import Testing
@testable import MacMoshKit

/// A new desk's first window, named as the desk is made (issue 163): the rule, the script's arguments
/// (`desk-new --window-name`, script 0.12.0), the window's New desk form, and the terminal's New desk questions and
/// `macmosh desk new`, which make the same desk as the form.
private let attic = Workhorse.sample(id: "attic", name: "Attic", user: "alex")
private let web = DeskName("web")!
/// A desk name of 64 characters, longer than a window name can be.
private let long = "a-very-long_desk-name-" + String(repeating: "x", count: 42)

/// Attic Ready, from a script of that version, with no desks.
private func checked(_ version: String = "0.12.0") -> CheckResult {
    var status = HostStatus.sampleReady
    status.scriptVersion = version
    return .sample(.ready(signIns: true), workhorse: attic, status: status, answeredAt: "192.168.1.20")
}

private func flow(_ runner: CommandRunner, _ wording: DeskFormat.Wording = .terminal) -> DeskFlow {
    DeskFlow(commands: HostCommands(runner: runner, paths: .test), wording: wording)
}

private func ok() -> FakeRunner { FakeRunner { _ in FakeRunner.ok() } }

/// The New desk form on Attic with that script, a typed path and the name it gives.
private func form(_ version: String = "0.12.0", name: String = "web") -> NewDeskForm {
    var f = NewDeskForm(check: checked(version), saved: attic)
    f.setTypedPath("~/Development/web")
    f.setName(name)
    return f
}

@Suite struct FirstWindowTests {
    static let question = "First window's name (Enter: same name as the desk, web; -: named after the program running in it): "

    // MARK: the rule

    /// The desk's own name always names its window, whatever its length, as the script takes it; anything else keeps
    /// `WindowName`'s rule and gets its sentence.
    @Test func theDesksOwnNameOrAWindowName() {
        #expect(long.count == 64 && DeskName(long) != nil)
        #expect(FirstWindow.problem(long, desk: long) == nil)
        #expect(FirstWindow.problem("web", desk: "web") == nil)
        #expect(FirstWindow.problem("build logs", desk: "web") == nil)
        #expect(FirstWindow.problem(String(repeating: "x", count: 32), desk: "web") == nil)
        #expect(FirstWindow.problem(long, desk: "web") == "A window name is 32 characters at most.")
        #expect(FirstWindow.problem("a#b", desk: "web") == "A window name uses letters, digits, spaces, -, _ and full stops only.")
        #expect(FirstWindow.problem("-x", desk: "web") == "A window name can't start with -.")
        #expect(FirstWindow.problem(" web", desk: "web") == "A window name can't start or end with a space.")
        #expect(FirstWindow.problem("", desk: "web") == "Type a name.")
    }

    @Test func whatIsSentForEachChoice() {
        #expect(FirstWindow.afterItsProgram.name(for: web) == nil)
        #expect(FirstWindow.deskName.name(for: web) == "web")
        #expect(FirstWindow.named("build logs").name(for: web) == "build logs")
        #expect(FirstWindow.deskName.name(for: DeskName(long)!) == long)
    }

    // MARK: the script's arguments

    @Test func theNameGoesBeforeTheCommandOnlyWhenGiven() {
        #expect(HostCommands.newDeskArguments(name: web, folder: "/a", reopen: true, keep: false, permanent: false,
                                              command: nil) == ["desk-new", "web", "/a", "--reopen"])
        #expect(HostCommands.newDeskArguments(name: web, folder: "/a", reopen: true, keep: false, permanent: false,
                                              command: nil, windowName: "web")
                == ["desk-new", "web", "/a", "--reopen", "--window-name", "web"])
        #expect(HostCommands.newDeskArguments(name: web, folder: "/a", reopen: false, keep: true, permanent: true,
                                              command: "npm run dev", windowName: "build logs")
                == ["desk-new", "web", "/a", "--no-reopen", "--keep", "--permanent", "--window-name", "build logs",
                    "--command", "npm run dev"])
    }

    // MARK: the window's form

    @Test func theFormsWordsAreInOnePlace() {
        #expect(NewDeskForm.Words.firstWindow == "First window")
        #expect(NewDeskForm.Words.sameAsDesk == "Same name as the desk")
        #expect(NewDeskForm.Words.firstWindowHelp == "Left empty, the window is named after the program running in it.")
    }

    /// Ticked at first: the first window gets the desk's name, and that is sent.
    @Test func tickedAtFirstTheWindowIsNamedAfterTheDesk() {
        let f = form()
        #expect(f.canNameFirstWindow)
        #expect(f.windowSameAsDesk)
        #expect(f.windowName.isEmpty)
        #expect(f.firstWindowLine == nil)
        #expect(f.firstWindow == .deskName)
        #expect(f.canMake)
        #expect(f.request?.firstWindow == .deskName)
    }

    /// Ticked, a 64-character desk name still names its window.
    @Test func tickedALongDeskNameIsFine() {
        let f = form(name: long)
        #expect(f.canMake && f.problems.isEmpty)
        #expect(f.request?.firstWindow == .deskName)
    }

    /// Clear and empty: nothing is sent, and tmux names the window. The grey line says so.
    @Test func clearAndEmptyLeavesTheNameToTmux() {
        var f = form()
        f.windowSameAsDesk = false
        #expect(f.firstWindowLine == NewDeskForm.Words.firstWindowHelp)
        #expect(!f.firstWindowLineIsProblem)
        #expect(f.canMake)
        #expect(f.request?.firstWindow == .afterItsProgram)
    }

    /// Clear with a name: that name, as typed.
    @Test func clearWithANameSendsThatName() {
        var f = form()
        f.windowSameAsDesk = false
        f.windowName = "build logs"
        #expect(f.firstWindowLine == NewDeskForm.Words.firstWindowHelp && !f.firstWindowLineIsProblem)
        #expect(f.canMake)
        #expect(f.request?.firstWindow == .named("build logs"))
        // The desk's own name typed in the field is fine too, however long.
        var g = form(name: long)
        g.windowSameAsDesk = false
        g.windowName = long
        #expect(g.canMake)
    }

    /// A name that breaks the rule shows the rule's sentence in red, and Make desk is off.
    @Test func aBadNameShowsTheRulesSentenceAndMakeDeskIsOff() {
        var f = form()
        f.windowSameAsDesk = false
        for (typed, sentence) in [
            ("a#b", "A window name uses letters, digits, spaces, -, _ and full stops only."),
            ("-x", "A window name can't start with -."),
            ("trail ", "A window name can't start or end with a space."),
            (String(repeating: "x", count: 33), "A window name is 32 characters at most."),
        ] {
            f.windowName = typed
            #expect(f.firstWindowProblem == sentence, "\(typed)")
            #expect(f.firstWindowLine == sentence && f.firstWindowLineIsProblem, "\(typed)")
            #expect(f.problems == [sentence], "\(typed)")
            #expect(!f.canMake && f.request == nil, "\(typed)")
        }
        // Ticked again, the typed name no longer counts.
        f.windowSameAsDesk = true
        #expect(f.canMake && f.firstWindowLine == nil)
    }

    /// With a script older than 0.12.0 the form has no first-window line and sends nothing about it.
    @Test func anOlderScriptShowsNoLineAndSendsNothing() {
        for version in ["0.11.0", "0.5.0", ""] {
            var f = form(version)
            #expect(!f.canNameFirstWindow, "\(version)")
            #expect(f.firstWindowLine == nil)
            #expect(f.firstWindow == nil)
            #expect(f.request?.firstWindow == nil)
            // Whatever the hidden fields hold.
            f.windowSameAsDesk = false
            f.windowName = "a#b"
            #expect(f.canMake && f.firstWindowProblem == nil && f.firstWindowLine == nil, "\(version)")
            #expect(f.request?.firstWindow == nil)
        }
    }

    // MARK: DeskFlow, which the window and the terminal both run

    @Test func theFormsChoicesBecomeTheArguments() async {
        let cases: [(FirstWindow?, String)] = [
            (.deskName, "~/.macmosh/macmosh-host desk-new web /Users/alex/web --reopen --window-name web"),
            (.named("build logs"), "~/.macmosh/macmosh-host desk-new web /Users/alex/web --reopen --window-name 'build logs'"),
            (.afterItsProgram, "~/.macmosh/macmosh-host desk-new web /Users/alex/web --reopen"),
            (nil, "~/.macmosh/macmosh-host desk-new web /Users/alex/web --reopen"),
        ]
        for (first, remote) in cases {
            let runner = ok()
            let request = NewDeskRequest(name: "web", folder: "/Users/alex/web", firstWindow: first)
            let result = await flow(runner, .window).newDesk(checked(), request: request, ui: QuietInteraction())
            #expect(result.code == 0, "\(String(describing: first))")
            #expect(runner.calls.map { $0.argv.last } == [remote], "\(String(describing: first))")
        }
    }

    /// The desk's long name as its own window's name goes through; a bad name stops before any ssh.
    @Test func theRuleIsCheckedBeforeAnythingIsSent() async {
        let runner = ok()
        let made = await flow(runner).newDesk(checked(), request: NewDeskRequest(name: long, folder: "/a", firstWindow: .named(long)),
                                              ui: ScriptedInteraction())
        #expect(made.code == 0)
        #expect(runner.calls.last?.argv.last == "~/.macmosh/macmosh-host desk-new '\(long)' /a --reopen --window-name '\(long)'")
        let refused = ok()
        let result = await flow(refused).newDesk(checked(), request: NewDeskRequest(name: "web", folder: "/a", firstWindow: .named("a#b")),
                                                 ui: ScriptedInteraction())
        #expect(result.code == 1)
        #expect(result.reason == "A window name uses letters, digits, spaces, -, _ and full stops only.")
        #expect(refused.calls.isEmpty)
    }

    /// With an older script a name is never sent: it stops before any ssh and says why, in each face's words.
    @Test func anOlderScriptIsNeverSentAName() async {
        for first in [FirstWindow.deskName, .named("build logs")] {
            let runner = ok()
            let request = NewDeskRequest(name: "web", folder: "/a", firstWindow: first)
            let terminal = await flow(runner).newDesk(checked("0.11.0"), request: request, ui: ScriptedInteraction())
            #expect(terminal.code == 1)
            #expect(terminal.reason == "Naming a new desk's first window needs the workhorse script 0.12.0 or newer, and Attic has 0.11.0. Update it with: macmosh prepare attic --fix")
            let window = await flow(runner, .window).newDesk(checked("0.11.0"), request: request, ui: QuietInteraction())
            #expect(window.reason == "Naming a new desk's first window needs the workhorse script 0.12.0 or newer, and Attic has 0.11.0.")
            #expect(runner.calls.isEmpty)
        }
        // Leaving it to tmux needs nothing.
        let runner = ok()
        let plain = await flow(runner).newDesk(checked("0.11.0"), request: NewDeskRequest(name: "web", folder: "/a", firstWindow: .afterItsProgram),
                                               ui: ScriptedInteraction())
        #expect(plain.code == 0)
        #expect(runner.calls.map { $0.argv.last } == ["~/.macmosh/macmosh-host desk-new web /a --reopen"])
    }

    // MARK: the terminal's questions

    /// One more question after the desk's name; Return answers it with the desk's name.
    @Test func returnNamesTheWindowAfterTheDesk() async {
        let runner = ok()
        let ui = ScriptedInteraction(answers: ["web", "", "/Users/alex/web", ""])
        let result = await flow(runner).newDesk(checked(), request: NewDeskRequest(), ui: ui)
        #expect(result.code == 0)
        #expect(ui.asked == ["Desk name: ", Self.question, "Folder on Attic, a full path or one starting with ~: ",
                             "Command to start in it (Enter for none): "])
        #expect(runner.calls.map { $0.argv.last } == ["~/.macmosh/macmosh-host desk-new web /Users/alex/web --reopen --window-name web"])
    }

    @Test func aDashLeavesTheNameToTmux() async {
        let runner = ok()
        let ui = ScriptedInteraction(answers: ["web", "-", "/Users/alex/web", ""])
        let result = await flow(runner).newDesk(checked(), request: NewDeskRequest(), ui: ui)
        #expect(result.code == 0)
        #expect(runner.calls.map { $0.argv.last } == ["~/.macmosh/macmosh-host desk-new web /Users/alex/web --reopen"])
    }

    @Test func aNameOfItsOwnIsSentAsTyped() async {
        let runner = ok()
        let ui = ScriptedInteraction(answers: ["web", "build logs", "/Users/alex/web", "npm run dev"])
        let result = await flow(runner).newDesk(checked(), request: NewDeskRequest(), ui: ui)
        #expect(result.code == 0)
        #expect(runner.calls.map { $0.argv.last } == [
            "~/.macmosh/macmosh-host desk-new web /Users/alex/web --reopen --window-name 'build logs' --command 'npm run dev'",
        ])
    }

    /// A name that breaks the rule says why and asks again; three of them stop with nothing sent.
    @Test func aBadAnswerIsAskedAgainUpToThreeTimes() async {
        let runner = ok()
        let ui = ScriptedInteraction(answers: ["web", "a#b", "api", "/Users/alex/web", ""])
        _ = await flow(runner).newDesk(checked(), request: NewDeskRequest(), ui: ui)
        #expect(ui.said.first == "A window name uses letters, digits, spaces, -, _ and full stops only.")
        #expect(ui.asked.filter { $0 == Self.question }.count == 2)
        #expect(runner.calls.map { $0.argv.last } == ["~/.macmosh/macmosh-host desk-new web /Users/alex/web --reopen --window-name api"])

        let stopped = ok()
        let three = ScriptedInteraction(answers: ["web", "a#b", "-x", " x", "/Users/alex/web"])
        let result = await flow(stopped).newDesk(checked(), request: NewDeskRequest(), ui: three)
        #expect(result.code == 1)
        #expect(result.reason == "That wasn't a window name three times, so MacMosh stopped. \(WindowName.rule)")
        #expect(stopped.calls.isEmpty)
    }

    /// End of input at the question makes nothing.
    @Test func endOfInputMakesNothing() async {
        let runner = ok()
        let ui = ScriptedInteraction(answers: ["web"])
        let result = await flow(runner).newDesk(checked(), request: NewDeskRequest(), ui: ui)
        #expect(result.code == 1)
        #expect(result.reason == "No desk was made.")
        #expect(runner.calls.isEmpty)
    }

    /// With a script older than 0.12.0 the question is not asked, and nothing about the window is sent.
    @Test func anOlderScriptIsNotAsked() async {
        let runner = ok()
        let ui = ScriptedInteraction(answers: ["web", "/Users/alex/web", ""])
        let result = await flow(runner).newDesk(checked("0.11.0"), request: NewDeskRequest(), ui: ui)
        #expect(result.code == 0)
        #expect(!ui.asked.contains(Self.question))
        #expect(runner.calls.map { $0.argv.last } == ["~/.macmosh/macmosh-host desk-new web /Users/alex/web --reopen"])
    }

    /// A name given with `--window-name` is not asked again, and `desk new` with everything given asks nothing.
    @Test func theFlagIsTakenAndNothingIsAsked() async throws {
        let request = try NewDeskRequest.fromFlags(name: "web", folder: "/Users/alex/web", reopen: false, noReopen: false,
                                                   keep: false, permanent: false, command: nil, windowName: "build logs")
        #expect(request.firstWindow == .named("build logs"))
        let runner = ok()
        let ui = ScriptedInteraction(answers: ["should not be read"])
        let result = await flow(runner).newDesk(checked(), request: request, ui: ui)
        #expect(result.code == 0)
        #expect(ui.asked.isEmpty)
        #expect(runner.calls.map { $0.argv.last } == ["~/.macmosh/macmosh-host desk-new web /Users/alex/web --reopen --window-name 'build logs'"])
        // Without the flag: nothing is asked, and the desk's name is sent when the script can take it (look step 4).
        let plain = try NewDeskRequest.fromFlags(name: "web", folder: "/Users/alex/web", reopen: false, noReopen: false,
                                                 keep: false, permanent: false, command: nil)
        #expect(plain.firstWindow == nil && plain.firstWindowAfterDesk)
        // The interactive form with the flag given asks every other question but this one.
        let asking = try NewDeskRequest.fromFlags(name: nil, folder: nil, reopen: false, noReopen: false, keep: false,
                                                  permanent: false, command: nil, windowName: "build logs")
        let askingUI = ScriptedInteraction(answers: ["web", "/Users/alex/web", ""])
        let r2 = ok()
        _ = await flow(r2).newDesk(checked(), request: asking, ui: askingUI)
        #expect(!askingUI.asked.contains(Self.question))
        #expect(r2.calls.map { $0.argv.last } == ["~/.macmosh/macmosh-host desk-new web /Users/alex/web --reopen --window-name 'build logs'"])
    }
    // MARK: the one-line command (look step 4, design 7 "One behaviour change")

    private func oneLine(_ windowName: String? = nil) throws -> NewDeskRequest {
        try NewDeskRequest.fromFlags(name: "web", folder: "/Users/alex/web", reopen: false, noReopen: false, keep: false,
                                     permanent: false, command: nil, windowName: windowName)
    }

    @Test func theOneLineCommandNamesTheFirstWindowAfterTheDesk() async throws {
        let runner = ok(), ui = ScriptedInteraction(answers: ["should not be read"])
        let result = await flow(runner).newDesk(checked(), request: try oneLine(), ui: ui)
        #expect(result.code == 0 && ui.asked.isEmpty)
        #expect(runner.calls.map { $0.argv.last } == ["~/.macmosh/macmosh-host desk-new web /Users/alex/web --reopen --window-name web"])
    }

    @Test func aDashLeavesTheFirstWindowToItsProgram() async throws {
        #expect(try oneLine("-").firstWindow == .afterItsProgram)
        for version in ["0.12.0", "0.11.0"] {
            let runner = ok()
            let result = await flow(runner).newDesk(checked(version), request: try oneLine("-"), ui: ScriptedInteraction())
            #expect(result.code == 0, "\(version)")
            #expect(runner.calls.map { $0.argv.last } == ["~/.macmosh/macmosh-host desk-new web /Users/alex/web --reopen"], "\(version)")
        }
    }

    /// Review Focus 1: with a script older than 0.12.0 (or one whose version is not known) the desk is made, nothing
    /// about the window is sent, and nothing is refused.
    @Test func theOneLineCommandWithAnOlderScriptSendsNothingAboutTheWindow() async throws {
        for version in ["0.11.0", ""] {
            let runner = ok()
            let result = await flow(runner).newDesk(checked(version), request: try oneLine(), ui: ScriptedInteraction())
            #expect(result.code == 0 && result.reason == nil, "\(version)")
            #expect(runner.calls.map { $0.argv.last } == ["~/.macmosh/macmosh-host desk-new web /Users/alex/web --reopen"], "\(version)")
        }
    }

    /// Review Focus 2: Start again and the window's form build a request with no first window and ask nothing; they
    /// do not pick up the one-line command's default.
    @Test func onlyTheOneLineCommandDefaultsToTheDesksName() async {
        let request = NewDeskRequest(name: "web", folder: "/Users/alex/web", permanent: true, command: "claude")
        #expect(!request.firstWindowAfterDesk && request.firstWindow == nil)
        let runner = ok()
        _ = await flow(runner, .window).newDesk(checked(), request: request, ui: QuietInteraction())
        #expect(runner.calls.map { $0.argv.last } == ["~/.macmosh/macmosh-host desk-new web /Users/alex/web --reopen --permanent --command claude"])
    }

    @Test func theQuestionAndTheHelpUseTheFormsWords() {
        #expect(DeskFlow.firstWindowQuestion(DeskName("website")!)
                == "First window's name (Enter: same name as the desk, website; -: named after the program running in it): ")
        #expect(NewDeskRequest.windowNameHelp == "A name for the desk's first window, or - to name it after the program running in it. "
                + WindowName.rule + " Left out with the desk's name and folder given, the window gets the desk's name; when the "
                + "questions run, they ask for it. With a workhorse script older than 0.12.0, only - or leaving it out works, and "
                + "the window is named after the program running in it.")
    }
}
