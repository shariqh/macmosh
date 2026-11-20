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
            folder: "/Users/alex/My \"Proj\" $HOME it's", reopen: true, keep: false, command: "echo \"$((6*7))\"")
        #expect(runner.calls[0].argv.last ==
            "~/.macmosh/macmosh-host desk-new web '/Users/alex/My \"Proj\" $HOME it'\\''s' --reopen --command 'echo \"$((6*7))\"'")
    }

    @Test func argumentsCarryOnlyTheFlagsThatWereGiven() {
        let bare = HostCommands.newDeskArguments(name: web, folder: "/a", reopen: false, keep: false, command: nil)
        #expect(bare == ["desk-new", "web", "/a"])
        let noCommand = HostCommands.newDeskArguments(name: web, folder: "/a", reopen: false, keep: false, command: "")
        #expect(noCommand == ["desk-new", "web", "/a"])
        let all = HostCommands.newDeskArguments(name: web, folder: "/a", reopen: true, keep: true, command: "npm run dev")
        #expect(all == ["desk-new", "web", "/a", "--reopen", "--keep", "--command", "npm run dev"])
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
                                                   reopen: false, keep: false, command: nil)
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
        #expect(remote(runner, 1) == "~/.macmosh/macmosh-host desk-new web '~/Development/beta'")
        #expect(ui.said.last == "Open it from the menu, or run: macmosh connect mbp web")
    }

    @Test func aTypedPathIsUsedAsTyped() async {
        let runner = desksListing(["alpha"])
        let ui = ScriptedInteraction(answers: ["web", "  /Users/alex/Other Place/it's  "])
        let w = Workhorse.sample(projectsFolder: "~/Development/")
        let result = await flow(runner).newDesk(checked(at: "workhorse", w), request: NewDeskRequest(), ui: ui)
        #expect(result.code == 0)
        #expect(remote(runner, 1) == "~/.macmosh/macmosh-host desk-new web '/Users/alex/Other Place/it'\\''s'")
    }

    @Test func aNumberFromTheListJoinsTheProjectsFolderWithoutADoubleSlash() async {
        let runner = desksListing(["alpha"])
        let ui = ScriptedInteraction(answers: ["web", "1"])
        let w = Workhorse.sample(projectsFolder: "~/Development/")
        _ = await flow(runner).newDesk(checked(at: "workhorse", w), request: NewDeskRequest(), ui: ui)
        #expect(remote(runner, 1) == "~/.macmosh/macmosh-host desk-new web '~/Development/alpha'")
    }

    @Test func withNoProjectsFolderItJustAsksForAPath() async {
        let runner = FakeRunner { _ in FakeRunner.ok() }
        let ui = ScriptedInteraction(answers: ["web", "/Users/alex/web"])
        let result = await flow(runner).newDesk(checked(), request: NewDeskRequest(), ui: ui)
        #expect(result.code == 0)
        #expect(runner.calls.count == 1)
        #expect(remote(runner) == "~/.macmosh/macmosh-host desk-new web /Users/alex/web")
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
        #expect(remote(runner) == "~/.macmosh/macmosh-host desk-new web /Users/alex/web")
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
        #expect(remote(runner, 1) == "~/.macmosh/macmosh-host desk-new web /p/alpha")
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
        #expect(remote(runner, 1) == "~/.macmosh/macmosh-host desk-new web /Users/alex/web")
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

    @Test func foldersJSONIsAnArrayOfNames() throws {
        #expect(try DeskFormat.foldersJSON(["alpha", "b \"q\"", "é"]) == #"["alpha","b \"q\"","é"]"#)
        #expect(try DeskFormat.foldersJSON([]) == "[]")
    }
}
