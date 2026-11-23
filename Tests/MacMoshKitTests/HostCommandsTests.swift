import Foundation
import Testing
@testable import MacMoshKit

private let web = DeskName("web")!

/// The remote string of ssh call `index`: the last argument.
private func remote(_ runner: FakeRunner, _ index: Int = 0) -> String? {
    runner.calls[index].argv.last
}

/// A runner whose ssh calls all end the way the script would: `exitCode` with `stderr`.
private func scriptEnds(_ exitCode: Int32, stderr: String = "", stdout: String = "") -> FakeRunner {
    FakeRunner { _ in CommandResult(exitCode: exitCode, stdout: stdout, stderr: stderr, timedOut: false) }
}

private func commands(_ runner: CommandRunner, paths: Paths = .test) -> HostCommands {
    HostCommands(runner: runner, paths: paths)
}

private let sshRefusal = "alex@workhorse: Permission denied (publickey,password,keyboard-interactive).\n"

/// A check that found the workhorse in `state`, answering at `address`.
private func checked(_ state: WorkhorseState = .ready(signIns: true), at address: String? = "workhorse",
                     _ w: Workhorse = .sample()) -> CheckResult {
    .sample(state, workhorse: w, answeredAt: address)
}

private func flow(_ runner: CommandRunner) -> DeskFlow {
    DeskFlow(commands: commands(runner))
}

private func desksListing(_ names: [String]) -> FakeRunner {
    FakeRunner { argv in
        FakeRunner.ok((argv.last ?? "").contains(" folders ") ? names.joined(separator: "\n") + "\n" : "")
    }
}

@Suite struct HostCommandsTests {
    // MARK: the one remote string

    @Test func newDeskSendsOneQuotedRemoteString() async throws {
        let runner = FakeRunner { _ in FakeRunner.ok() }
        try await HostCommands(runner: runner, paths: .test).newDesk(
            on: .sample(), address: "workhorse", name: DeskName("web")!,
            folder: "/Users/alex/My \"Proj\" $HOME it's", reopen: true, keep: false, permanent: false,
            command: "echo \"$((6*7))\"")
        #expect(runner.calls[0].argv.last ==
            "~/.macmosh/macmosh-host desk-new web '/Users/alex/My \"Proj\" $HOME it'\\''s' --reopen --command 'echo \"$((6*7))\"'")
    }

    @Test func argumentsAlwaysSayWhetherToReopenAndCarryTheOtherFlagsOnlyWhenGiven() {
        let bare = HostCommands.newDeskArguments(name: web, folder: "/a", reopen: false, keep: false,
                                                 permanent: false, command: nil)
        #expect(bare == ["desk-new", "web", "/a", "--no-reopen"])
        let noCommand = HostCommands.newDeskArguments(name: web, folder: "/a", reopen: true, keep: false,
                                                      permanent: false, command: "")
        #expect(noCommand == ["desk-new", "web", "/a", "--reopen"])
        let all = HostCommands.newDeskArguments(name: web, folder: "/a", reopen: true, keep: true,
                                                permanent: true, command: "npm run dev")
        #expect(all == ["desk-new", "web", "/a", "--reopen", "--keep", "--permanent", "--command", "npm run dev"])
    }

    @Test func aTildeInTheProjectsFolderIsSentAsTyped() async throws {
        let runner = desksListing(["a"])
        _ = try await commands(runner).folders(on: .sample(projectsFolder: "~/Development"), address: "workhorse")
        let sent = try #require(remote(runner))
        #expect(sent.hasSuffix(" folders '~/Development'"))
        #expect(sent.hasPrefix("~/.macmosh/macmosh-host "))
    }

    @Test func removeSendsKillOnlyWhenAsked() async throws {
        let runner = FakeRunner { _ in FakeRunner.ok() }
        let hc = commands(runner)
        try await hc.removeDesk(on: .sample(), address: "workhorse", name: web, kill: false)
        try await hc.removeDesk(on: .sample(), address: "workhorse", name: web, kill: true)
        #expect(remote(runner, 0) == "~/.macmosh/macmosh-host desk-remove web")
        #expect(remote(runner, 1) == "~/.macmosh/macmosh-host desk-remove web --kill")
    }

    @Test func renameSendsTheOldNameThenTheNew() async throws {
        let runner = FakeRunner { _ in FakeRunner.ok() }
        try await commands(runner).renameDesk(on: .sample(), address: "workhorse", from: web, to: DeskName("notes")!)
        #expect(remote(runner) == "~/.macmosh/macmosh-host desk-rename web notes")
    }

    @Test func newWindowAsksForAWindowInTheDesk() async throws {
        let runner = FakeRunner { _ in FakeRunner.ok() }
        try await commands(runner).newWindow(on: .sample(), address: "workhorse", desk: web)
        #expect(remote(runner) == "~/.macmosh/macmosh-host window-new web")
    }

    // MARK: how the call is made

    @Test func theCallGoesToTheAddressThatAnsweredInBatchModeWithATimeLimit() async throws {
        let runner = FakeRunner { _ in FakeRunner.ok() }
        try await commands(runner).newWindow(on: .sample(), address: "192.168.1.20", desk: web)
        let call = runner.calls[0]
        #expect(call.argv[0] == "ssh")
        #expect(sshTarget(call.argv) == "alex@192.168.1.20")
        #expect(call.argv.contains("BatchMode=yes"))
        #expect(!call.argv.contains("-t"))
        #expect(call.timeout == .seconds(15))
    }

    @Test func noSSHRunsWhenTheKeyIsMissing() async throws {
        let paths = try temporaryPaths()
        try FileManager.default.removeItem(at: paths.defaultIdentity)
        let runner = FakeRunner { _ in FakeRunner.ok() }
        let hc = commands(runner, paths: paths)
        await #expect(throws: HostCommandError.self) {
            try await hc.newWindow(on: .sample(), address: "workhorse", desk: web)
        }
        await #expect(throws: HostCommandError.self) { _ = try await hc.folders(on: .sample(projectsFolder: "~/p"), address: "workhorse") }
        #expect(runner.calls.isEmpty)
    }

    // MARK: exit codes

    @Test func exitCodesBecomeErrors() async {
        let expected: [Int32: HostCommandError] = [
            3: .nobodyLoggedIn, 4: .noSuchDesk, 5: .serverDidNotStart, 6: .badInput, 7: .alreadyExists,
        ]
        for (code, want) in expected {
            let runner = scriptEnds(code, stderr: "macmosh-host: some words\n")
            do {
                try await commands(runner).newDesk(on: .sample(), address: "workhorse", name: web, folder: "/x",
                                                   reopen: false, keep: false, permanent: false, command: nil)
                Issue.record("exit code \(code) did not throw")
            } catch {
                #expect(error as? HostCommandError == want, "exit code \(code)")
            }
        }
        #expect(expected.count == 5)
    }

    @Test func everyMethodMapsTheCodes() async {
        let runner = scriptEnds(4)
        let hc = commands(runner)
        await #expect(throws: HostCommandError.noSuchDesk) {
            try await hc.removeDesk(on: .sample(), address: "workhorse", name: web, kill: false)
        }
        await #expect(throws: HostCommandError.noSuchDesk) {
            try await hc.newWindow(on: .sample(), address: "workhorse", desk: web)
        }
        await #expect(throws: HostCommandError.noSuchDesk) {
            try await hc.renameDesk(on: .sample(), address: "workhorse", from: web, to: DeskName("notes")!)
        }
        let seven = commands(scriptEnds(7))
        await #expect(throws: HostCommandError.alreadyExists) {
            try await seven.renameDesk(on: .sample(), address: "workhorse", from: web, to: DeskName("notes")!)
        }
        let six = commands(scriptEnds(6))
        await #expect(throws: HostCommandError.badInput) {
            _ = try await six.folders(on: .sample(projectsFolder: "~/nowhere"), address: "workhorse")
        }
    }

    @Test func otherOutcomesBecomePlainFailures() async {
        let cases: [(CommandResult, String)] = [
            (CommandResult(exitCode: 1, stdout: "", stderr: "macmosh-host: could not create the desk\n", timedOut: false),
             "could not create the desk"),
            (CommandResult(exitCode: -1, stdout: "", stderr: "", timedOut: true), "didn't answer"),
            (FakeRunner.failed(255, stderr: sshRefusal), "key"),
            (FakeRunner.failed(255, stderr: "Host key verification failed.\n"), "different"),
            (FakeRunner.failed(255, stderr: "ssh: connect to host x port 22: Connection refused\n"), "refused"),
        ]
        for (result, word) in cases {
            let runner = FakeRunner { _ in result }
            do {
                try await commands(runner).newWindow(on: .sample(), address: "workhorse", desk: web)
                Issue.record("no error for \(result)")
            } catch let HostCommandError.failed(exitCode, message) {
                #expect(message.localizedCaseInsensitiveContains(word), "\(message) should mention \(word)")
                #expect(!message.isEmpty && exitCode != 0)
            } catch {
                Issue.record("wrong error \(error)")
            }
        }
    }

    // MARK: folders

    @Test func foldersNeedsAProjectsFolder() async {
        let runner = FakeRunner { _ in FakeRunner.ok() }
        let hc = commands(runner)
        await #expect(throws: HostCommandError.noProjectsFolder) {
            _ = try await hc.folders(on: .sample(projectsFolder: nil), address: "workhorse")
        }
        await #expect(throws: HostCommandError.noProjectsFolder) {
            _ = try await hc.folders(on: .sample(projectsFolder: ""), address: "workhorse")
        }
        #expect(runner.calls.isEmpty)
    }

    @Test func foldersReturnsTheLines() async throws {
        let runner = desksListing(["alpha", "beta gamma", "é"])
        let names = try await commands(runner).folders(on: .sample(projectsFolder: "~/Development"), address: "workhorse")
        #expect(names == ["alpha", "beta gamma", "é"])
    }

    @Test func foldersLeavesOutBlankLines() async throws {
        let runner = FakeRunner { _ in FakeRunner.ok("a\n\nb\r\n\n") }
        let names = try await commands(runner).folders(on: .sample(projectsFolder: "/p"), address: "workhorse")
        #expect(names == ["a", "b"])
    }

    // MARK: the words

    @Test func everyErrorHasWordsForAPerson() {
        let w = Workhorse.sample(id: "mbp", name: "MacBook Pro")
        let named: [HostCommandError] = [.badInput, .alreadyExists, .noSuchDesk, .noProjectsFolder, .nobodyLoggedIn,
                                         .serverDidNotStart]
        for error in named {
            #expect(DeskFormat.message(error, workhorse: w).contains("MacBook Pro"), "\(error)")
        }
        let projects = DeskFormat.message(.noProjectsFolder, workhorse: w)
        #expect(projects == "No projects folder is set for MacBook Pro. Set one with: macmosh set mbp projects-folder <path>")
        #expect(DeskFormat.message(.failed(exitCode: 1, message: "It broke."), workhorse: w) == "It broke.")
    }

    // MARK: not Ready

    @Test func aWorkhorseThatIsNotReadyStopsEveryCommandBeforeSSH() async {
        let states: [WorkhorseState] = [.waitingForLogin, .locked, .cantVerify, .cantReach(.nothingAnswers),
                                        .notSetUp(.notPaired), .notSetUp(.identityUnusable)]
        for state in states {
            let runner = FakeRunner { _ in FakeRunner.ok() }
            let f = flow(runner)
            let check = checked(state, at: nil)
            let ui = ScriptedInteraction()
            let results = [
                await f.newDesk(check, request: NewDeskRequest(name: "web", folder: "/x"), ui: ui),
                await f.removeDesk(check, name: "web", kill: false, ui: ui),
                await f.newWindow(check, desk: "web", ui: ui),
                await f.renameDesk(check, from: "web", to: "notes", ui: ui),
                await f.renameDesk(check, from: "web", to: nil, ui: ui),
                await f.removeDeskAsking(check, name: "web", ui: ui),
                await f.folders(check),
            ]
            for result in results {
                #expect(result.code == 1)
                let reason = result.reason ?? ""
                #expect(reason.hasPrefix(StatusFormat.headline(check)), "\(state): \(reason)")
            }
            #expect(runner.calls.isEmpty)
            #expect(ui.asked.isEmpty)
        }
    }

    @Test func theNotReadyMessageCarriesTheHint() async {
        let runner = FakeRunner { _ in FakeRunner.ok() }
        let check = checked(.waitingForLogin, at: nil, .sample(name: "MacBook Pro"))
        let result = await flow(runner).newWindow(check, desk: "web", ui: ScriptedInteraction())
        #expect(result.reason == "MacBook Pro · Waiting for login\nIt is on and unlocked, but nobody has logged in.")
    }

    @Test func bothKindsOfReadyGoThrough() async {
        for state in [WorkhorseState.ready(signIns: true), .ready(signIns: false)] {
            let runner = FakeRunner { _ in FakeRunner.ok() }
            let result = await flow(runner).newWindow(checked(state, at: "192.168.1.20"), desk: "web", ui: ScriptedInteraction())
            #expect(result.code == 0)
            #expect(sshTarget(runner.calls[0].argv) == "alex@192.168.1.20")
        }
    }

    // MARK: the plain form

    @Test func theNonInteractiveFormNeverAsks() async {
        let runner = FakeRunner { _ in FakeRunner.ok() }
        let ui = ScriptedInteraction(answers: ["should not be read"])
        let request = NewDeskRequest(name: "web", folder: "/Users/alex/web", reopen: true)
        #expect(!request.isInteractive)
        let result = await flow(runner).newDesk(checked(), request: request, ui: ui)
        #expect(result.code == 0)
        #expect(result.desk == DeskName("web"))      // the name `desk new` goes on to connect to
        #expect(ui.asked.isEmpty)
        #expect(remote(runner) == "~/.macmosh/macmosh-host desk-new web /Users/alex/web --reopen")
        #expect(ui.said.last == "Open it from the menu, or run: macmosh connect mbp web")
    }

    @Test func aPermanentDeskIsSentAsPermanent() async throws {
        let runner = FakeRunner { _ in FakeRunner.ok() }
        let request = try NewDeskRequest.fromFlags(name: "web", folder: "/Users/alex/web", reopen: false,
                                                   noReopen: true, keep: false, permanent: true, command: nil)
        let result = await flow(runner).newDesk(checked(), request: request, ui: ScriptedInteraction())
        #expect(result.code == 0)
        #expect(remote(runner) == "~/.macmosh/macmosh-host desk-new web /Users/alex/web --no-reopen --permanent")
    }

    // MARK: desk new's flags

    @Test func aNewDeskComesBackAfterARestartUnlessToldNot() throws {
        let plain = try NewDeskRequest.fromFlags(name: "web", folder: "/a", reopen: false, noReopen: false,
                                                 keep: false, permanent: false, command: nil)
        #expect(plain.reopen)
        #expect(!plain.permanent)
        let saidReopen = try NewDeskRequest.fromFlags(name: "web", folder: "/a", reopen: true, noReopen: false,
                                                      keep: false, permanent: false, command: nil)
        #expect(saidReopen == plain)
        let noReopen = try NewDeskRequest.fromFlags(name: "web", folder: "/a", reopen: false, noReopen: true,
                                                    keep: false, permanent: false, command: nil)
        #expect(!noReopen.reopen)
        let permanent = try NewDeskRequest.fromFlags(name: "web", folder: "/a", reopen: false, noReopen: false,
                                                     keep: true, permanent: true, command: "npm run dev")
        #expect(permanent == NewDeskRequest(name: "web", folder: "/a", reopen: true, keep: true, permanent: true,
                                            command: "npm run dev"))
    }

    @Test func reopenAndNoReopenTogetherIsAMistake() {
        #expect(throws: DeskUsageError.reopenAndNoReopen) {
            try NewDeskRequest.fromFlags(name: nil, folder: nil, reopen: true, noReopen: true,
                                         keep: false, permanent: false, command: nil)
        }
        #expect(DeskUsageError.reopenAndNoReopen.description.contains("--no-reopen"))
    }

    @Test func theFormThatAsksMakesADeskThatComesBack() {
        let form = NewDeskRequest()
        #expect(form.isInteractive)
        #expect(form.reopen)
        #expect(!form.permanent)
    }

    @Test func aBadNameInTheArgumentsIsAnErrorNotAQuestion() async {
        let runner = FakeRunner { _ in FakeRunner.ok() }
        let ui = ScriptedInteraction(answers: ["web"])
        let result = await flow(runner).newDesk(checked(), request: NewDeskRequest(name: "my desk", folder: "/x"), ui: ui)
        #expect(result.code == 1)
        #expect(result.reason == DeskFormat.nameRule)
        #expect(ui.asked.isEmpty)
        #expect(runner.calls.isEmpty)
    }

    @Test func aRefusalFromTheWorkhorseBecomesItsMessage() async {
        let result = await flow(scriptEnds(7)).newDesk(checked(), request: NewDeskRequest(name: "web", folder: "/x"),
                                                      ui: ScriptedInteraction())
        #expect(result.code == 1)
        #expect(result.reason == DeskFormat.message(.alreadyExists, workhorse: .sample()))
    }

    @Test func removeAndWindowSaySoOnSuccess() async {
        let runner = FakeRunner { _ in FakeRunner.ok() }
        let ui = ScriptedInteraction()
        let removed = await flow(runner).removeDesk(checked(), name: "web", kill: true, ui: ui)
        let added = await flow(runner).newWindow(checked(), desk: "web", ui: ui)
        #expect(removed.code == 0 && added.code == 0)
        #expect(ui.said == ["Removed the desk web and closed its windows.", "Added a window to web."])
        let bad = await flow(runner).removeDesk(checked(), name: "no way", kill: false, ui: ui)
        #expect(bad.code == 1 && bad.reason == DeskFormat.nameRule)
    }

    // MARK: the interactive form

    @Test func interactiveNewDeskAsksNameThenFolder() async {
        let runner = desksListing(["alpha", "beta", "gamma"])
        let ui = ScriptedInteraction(answers: ["web", "2"])
        let w = Workhorse.sample(projectsFolder: "~/Development")
        let result = await flow(runner).newDesk(checked(at: "workhorse", w), request: NewDeskRequest(), ui: ui)
        #expect(result.code == 0)
        #expect(ui.asked.count == 2)
        #expect(ui.said.contains("  1  alpha"))
        #expect(ui.said.contains("  2  beta"))
        #expect(ui.said.contains("  3  gamma"))
        #expect(ui.asked[1].contains("or type a path"))
        #expect(runner.calls.count == 2)
        #expect(remote(runner, 0) == "~/.macmosh/macmosh-host folders '~/Development'")
        #expect(remote(runner, 1) == "~/.macmosh/macmosh-host desk-new web '~/Development/beta' --reopen")
        #expect(ui.said.last == "Open it from the menu, or run: macmosh connect mbp web")
    }

    @Test func aTypedPathIsUsedAsTyped() async {
        let runner = desksListing(["alpha"])
        let ui = ScriptedInteraction(answers: ["web", "  /Users/alex/Other Place/it's  "])
        let w = Workhorse.sample(projectsFolder: "~/Development/")
        let result = await flow(runner).newDesk(checked(at: "workhorse", w), request: NewDeskRequest(), ui: ui)
        #expect(result.code == 0)
        #expect(remote(runner, 1) == "~/.macmosh/macmosh-host desk-new web '/Users/alex/Other Place/it'\\''s' --reopen")
    }

    @Test func aNumberFromTheListJoinsTheProjectsFolderWithoutADoubleSlash() async {
        let runner = desksListing(["alpha"])
        let ui = ScriptedInteraction(answers: ["web", "1"])
        let w = Workhorse.sample(projectsFolder: "~/Development/")
        _ = await flow(runner).newDesk(checked(at: "workhorse", w), request: NewDeskRequest(), ui: ui)
        #expect(remote(runner, 1) == "~/.macmosh/macmosh-host desk-new web '~/Development/alpha' --reopen")
    }

    @Test func withNoProjectsFolderItJustAsksForAPath() async {
        let runner = FakeRunner { _ in FakeRunner.ok() }
        let ui = ScriptedInteraction(answers: ["web", "/Users/alex/web"])
        let result = await flow(runner).newDesk(checked(), request: NewDeskRequest(), ui: ui)
        #expect(result.code == 0)
        #expect(runner.calls.count == 1)
        #expect(remote(runner) == "~/.macmosh/macmosh-host desk-new web /Users/alex/web --reopen")
        #expect(!ui.asked[1].contains("number"))
    }

    @Test func aNameGivenButNoFolderAsksOnlyForTheFolder() async {
        let runner = FakeRunner { _ in FakeRunner.ok() }
        let ui = ScriptedInteraction(answers: ["/Users/alex/web"])
        let request = NewDeskRequest(name: "web")
        #expect(request.isInteractive)
        let result = await flow(runner).newDesk(checked(), request: request, ui: ui)
        #expect(result.code == 0)
        #expect(ui.asked.count == 1)
    }

    @Test func anInvalidNameIsAskedAgain() async {
        let runner = FakeRunner { _ in FakeRunner.ok() }
        let ui = ScriptedInteraction(answers: ["my desk", "", "web", "/Users/alex/web"])
        let result = await flow(runner).newDesk(checked(), request: NewDeskRequest(), ui: ui)
        #expect(result.code == 0)
        #expect(ui.asked.count == 4)
        #expect(ui.said.filter { $0 == DeskFormat.nameRule }.count == 2)
        #expect(remote(runner) == "~/.macmosh/macmosh-host desk-new web /Users/alex/web --reopen")
    }

    @Test func threeBadNamesStop() async {
        let runner = FakeRunner { _ in FakeRunner.ok() }
        let ui = ScriptedInteraction(answers: ["a b", "c/d", "e.f", "web"])
        let result = await flow(runner).newDesk(checked(), request: NewDeskRequest(), ui: ui)
        #expect(result.code == 1)
        #expect(result.reason == "That wasn't a desk name three times, so MacMosh stopped. \(DeskFormat.nameRule)")
        #expect(ui.asked.count == 3)
        #expect(runner.calls.isEmpty)
    }

    @Test func aListNumberOutOfRangeIsAskedAgain() async {
        let runner = desksListing(["alpha", "beta"])
        let ui = ScriptedInteraction(answers: ["web", "7", "1"])
        let w = Workhorse.sample(projectsFolder: "/p")
        let result = await flow(runner).newDesk(checked(at: "workhorse", w), request: NewDeskRequest(), ui: ui)
        #expect(result.code == 0)
        #expect(remote(runner, 1) == "~/.macmosh/macmosh-host desk-new web /p/alpha --reopen")
    }

    @Test func threeEmptyFolderAnswersStop() async {
        let runner = FakeRunner { _ in FakeRunner.ok() }
        let ui = ScriptedInteraction(answers: ["web", "", "", ""])
        let result = await flow(runner).newDesk(checked(), request: NewDeskRequest(), ui: ui)
        #expect(result.code == 1)
        #expect(result.reason == "No folder was chosen, so MacMosh stopped.")
        #expect(runner.calls.isEmpty)
    }

    @Test func aProjectsFolderThatCantBeListedFallsBackToAPath() async {
        let runner = FakeRunner { argv in
            (argv.last ?? "").contains(" folders ") ? FakeRunner.failed(6, stderr: "macmosh-host: no such folder\n") : FakeRunner.ok()
        }
        let ui = ScriptedInteraction(answers: ["web", "/Users/alex/web"])
        let w = Workhorse.sample(projectsFolder: "~/gone")
        let result = await flow(runner).newDesk(checked(at: "workhorse", w), request: NewDeskRequest(), ui: ui)
        #expect(result.code == 0)
        #expect(ui.said.contains { $0.contains("~/gone") })
        #expect(remote(runner, 1) == "~/.macmosh/macmosh-host desk-new web /Users/alex/web --reopen")
    }

    @Test func foldersThroughTheFlowGivesTheNames() async {
        let runner = desksListing(["alpha", "beta"])
        let w = Workhorse.sample(projectsFolder: "~/Development")
        let result = await flow(runner).folders(checked(at: "workhorse", w))
        #expect(result.code == 0)
        #expect(result.output == ["alpha", "beta"])
        let none = await flow(runner).folders(checked(at: "workhorse", .sample(id: "mbp", projectsFolder: nil)))
        #expect(none.code == 1)
        #expect(none.reason == DeskFormat.message(.noProjectsFolder, workhorse: .sample()))
    }

    // MARK: rename

    static let renamedLine = "Renamed web to notes. Tabs that are open on it keep working; their titles may still say web."

    @Test func renameWithTheNewNameGivenAsksNothing() async {
        let runner = FakeRunner { _ in FakeRunner.ok() }
        let ui = ScriptedInteraction(answers: ["should not be read"])
        let result = await flow(runner).renameDesk(checked(), from: "web", to: "notes", ui: ui)
        #expect(result.code == 0)
        #expect(ui.asked.isEmpty)
        #expect(remote(runner) == "~/.macmosh/macmosh-host desk-rename web notes")
        #expect(ui.said == [Self.renamedLine])
    }

    @Test func renameWithoutTheNewNameAsksForIt() async {
        let runner = FakeRunner { _ in FakeRunner.ok() }
        let ui = ScriptedInteraction(answers: ["  notes  "])
        let result = await flow(runner).renameDesk(checked(), from: "web", to: nil, ui: ui)
        #expect(result.code == 0)
        #expect(ui.asked == ["New name for web: "])
        #expect(remote(runner) == "~/.macmosh/macmosh-host desk-rename web notes")
        #expect(ui.said == [Self.renamedLine])
    }

    @Test func anEmptyAnswerChangesNothing() async {
        let runner = FakeRunner { _ in FakeRunner.ok() }
        let ui = ScriptedInteraction(answers: [""])
        let result = await flow(runner).renameDesk(checked(), from: "web", to: nil, ui: ui)
        #expect(result.code == 1)
        #expect(result.reason == "Nothing was changed.")
        #expect(ui.asked.count == 1)
        #expect(runner.calls.isEmpty)
    }

    @Test func aNewNameThatBreaksTheRuleIsAskedAgainUpToThreeTimes() async {
        let runner = FakeRunner { _ in FakeRunner.ok() }
        let ui = ScriptedInteraction(answers: ["my notes", "notes"])
        let result = await flow(runner).renameDesk(checked(), from: "web", to: nil, ui: ui)
        #expect(result.code == 0)
        #expect(ui.said.first == DeskFormat.nameRule)
        #expect(remote(runner) == "~/.macmosh/macmosh-host desk-rename web notes")

        let three = ScriptedInteraction(answers: ["a b", "c/d", "e.f", "notes"])
        let stopped = await flow(runner).renameDesk(checked(), from: "web", to: nil, ui: three)
        #expect(stopped.code == 1)
        #expect(stopped.reason == "That wasn't a desk name three times, so MacMosh stopped. \(DeskFormat.nameRule)")
        #expect(three.asked.count == 3)
        #expect(runner.calls.count == 1)
    }

    @Test func aBadNameOnTheCommandLineIsAnErrorNotAQuestion() async {
        let runner = FakeRunner { _ in FakeRunner.ok() }
        for (old, new) in [("web", "my notes"), ("we b", "notes")] {
            let ui = ScriptedInteraction(answers: ["notes"])
            let result = await flow(runner).renameDesk(checked(), from: old, to: new, ui: ui)
            #expect(result.code == 1)
            #expect(result.reason == DeskFormat.nameRule)
            #expect(ui.asked.isEmpty)
        }
        #expect(runner.calls.isEmpty)
    }

    @Test func aTakenNameOrAMissingDeskBecomesTheWorkhorsesWords() async {
        let taken = await flow(scriptEnds(7)).renameDesk(checked(), from: "web", to: "notes", ui: ScriptedInteraction())
        #expect(taken.code == 1)
        #expect(taken.reason == DeskFormat.message(.alreadyExists, workhorse: .sample()))
        let missing = await flow(scriptEnds(4)).renameDesk(checked(), from: "web", to: "notes", ui: ScriptedInteraction())
        #expect(missing.reason == DeskFormat.message(.noSuchDesk, workhorse: .sample()))
    }

    // MARK: remove --ask

    /// A Ready check whose report has `website` open with two windows and `notes` closed and permanent.
    private func checkedWithDesks() -> CheckResult {
        var status = HostStatus.sampleWithDesk
        status.definitions = [
            .init(name: DeskName("website")!, reopen: true, keep: false, folder: "/Users/alex/site", command: ""),
            .init(name: DeskName("notes")!, reopen: false, keep: false, folder: "/Users/alex/notes", command: "",
                  permanent: true),
        ]
        return .sample(.ready(signIns: true), workhorse: .sample(), status: status, answeredAt: "workhorse")
    }

    static let removeQuestion = "Type yes to remove it: "

    @Test func removingAnOpenDeskNamesItsWindowsAndClosesThemOnYes() async {
        let runner = FakeRunner { _ in FakeRunner.ok() }
        let ui = ScriptedInteraction(answers: [" yes "])
        let result = await flow(runner).removeDeskAsking(checkedWithDesks(), name: "website", ui: ui)
        #expect(result.code == 0)
        #expect(ui.said == [
            "This removes the desk website and closes its 2 windows (zsh, vim), with whatever is running in them.",
            "Removed the desk website and closed its windows.",
        ])
        #expect(ui.asked == [Self.removeQuestion])
        #expect(remote(runner) == "~/.macmosh/macmosh-host desk-remove website --kill")
    }

    @Test func removingAClosedDeskSaysItHasNoOpenWindows() async {
        let runner = FakeRunner { _ in FakeRunner.ok() }
        let ui = ScriptedInteraction(answers: ["yes"])
        let result = await flow(runner).removeDeskAsking(checkedWithDesks(), name: "notes", ui: ui)
        #expect(result.code == 0)
        #expect(ui.said == ["This removes the desk notes. It has no open windows.", "Removed the desk notes."])
        #expect(ui.asked == [Self.removeQuestion])
        #expect(remote(runner) == "~/.macmosh/macmosh-host desk-remove notes --kill")
    }

    @Test(arguments: ["website", "notes"])
    func noOrEnterRemovesNothing(desk: String) async {
        for answer in ["no", "", "y", "YES please"] {
            let runner = FakeRunner { _ in FakeRunner.ok() }
            let ui = ScriptedInteraction(answers: [answer])
            let result = await flow(runner).removeDeskAsking(checkedWithDesks(), name: desk, ui: ui)
            #expect(result.code == 1, "\(answer)")
            #expect(result.reason == "Nothing was removed.", "\(answer)")
            #expect(ui.asked == [Self.removeQuestion])
            #expect(runner.calls.isEmpty, "\(answer)")
        }
    }

    @Test func oneWindowIsOneWindow() async {
        var status = HostStatus.sampleReady
        status.desks = [.init(name: DeskName("solo")!, windows: [.init(index: 0, name: "zsh")], windowCount: 1, attached: 0)]
        let check = CheckResult.sample(.ready(signIns: true), status: status, answeredAt: "workhorse")
        let ui = ScriptedInteraction()
        _ = await flow(FakeRunner { _ in FakeRunner.ok() }).removeDeskAsking(check, name: "solo", ui: ui)
        #expect(ui.said.first == "This removes the desk solo and closes its 1 window (zsh), with whatever is running in them.")
    }

    @Test func aDeskTheReportDoesntHaveIsNotAskedAbout() async {
        let runner = FakeRunner { _ in FakeRunner.ok() }
        let ui = ScriptedInteraction(answers: ["yes"])
        let result = await flow(runner).removeDeskAsking(checkedWithDesks(), name: "journal", ui: ui)
        #expect(result.code == 1)
        #expect(result.reason == DeskFormat.message(.noSuchDesk, workhorse: .sample()))
        #expect(ui.asked.isEmpty)
        #expect(runner.calls.isEmpty)
    }

    @Test func removeWithoutAskIsAsBefore() async {
        let runner = FakeRunner { _ in FakeRunner.ok() }
        let ui = ScriptedInteraction(answers: ["no"])
        let result = await flow(runner).removeDesk(checkedWithDesks(), name: "website", kill: false, ui: ui)
        #expect(result.code == 0)
        #expect(ui.asked.isEmpty)
        #expect(remote(runner) == "~/.macmosh/macmosh-host desk-remove website")
    }

    // MARK: the end of a tab

    @Test func aTabThatAskedWaitsForAKeyEvenWhenItWorked() {
        let ui = ScriptedInteraction()
        #expect(ui.finishTab(0, reason: nil) == 0)
        #expect(ui.waits == 1)
        let failed = ScriptedInteraction()
        #expect(failed.finishTab(1, reason: "Nothing was changed.") == 1)
        #expect(failed.said == ["Nothing was changed."])
        #expect(failed.waits == 1)
    }

    @Test func foldersJSONIsAnArrayOfNames() throws {
        #expect(try DeskFormat.foldersJSON(["alpha", "b \"q\"", "é"]) == #"["alpha","b \"q\"","é"]"#)
        #expect(try DeskFormat.foldersJSON([]) == "[]")
    }
}
