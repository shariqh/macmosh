import Foundation
import Testing
@testable import MacMoshKit

private let attic = Workhorse.sample(id: "attic", name: "Attic", user: "alex", projectsFolder: "~/Development")

/// A Ready report of Attic with an open desk called `--kill`, made before the rule, and one called `web`.
private func dashedCheck() -> CheckResult {
    var status = HostStatus.sampleReady
    status.scriptVersion = "0.8.0"
    status.desks = [
        .init(name: DeskName("--kill")!, windows: [.init(index: 0, name: "zsh")], windowCount: 1, attached: 0),
        .init(name: DeskName("web")!, windows: [.init(index: 0, name: "zsh")], windowCount: 1, attached: 0),
    ]
    return .sample(.ready(signIns: true), workhorse: attic, status: status, answeredAt: "workhorse")
}

private func flow(_ runner: CommandRunner) -> DeskFlow {
    DeskFlow(commands: HostCommands(runner: runner, paths: .test))
}

/// Every id in the menu's tree.
private func ids(_ entries: [MenuEntry]) -> [String] {
    entries.flatMap { [$0.id] + ids($0.submenu) + ids($0.children) }
}

/// A new desk name can't start with a dash (issue #147): the workhorse script reads `--old` as an option, so New
/// desk failed with "unknown option", and a desk renamed to `--kill` could be neither opened nor removed.
/// Desks that already have such a name still parse, show and can be renamed away from it.
@Suite struct NewDeskNameTests {
    static let sentence = "A desk name can't start with -."

    @Test func theRuleIsOnePlainSentence() {
        #expect(DeskFormat.noLeadingDash == Self.sentence)
    }

    // MARK: the one rule both faces use

    @Test func aNewNameThatStartsWithADashIsRefused() {
        for name in ["--old", "--kill", "-x", "-", "---"] {
            #expect(DeskNameRule.newNameProblem(name) == Self.sentence, "\(name)")
            #expect(DeskNameRule.newName(name) == nil, "\(name)")
        }
    }

    @Test func aDashElsewhereIsFine() {
        for name in ["web-2", "a-", "a--b", "x_-"] {
            #expect(DeskNameRule.newNameProblem(name) == nil, "\(name)")
            #expect(DeskNameRule.newName(name) == DeskName(name), "\(name)")
        }
    }

    @Test func aNameThatBreaksTheOtherRuleSaysThatRule() {
        for name in ["", "my desk", "-my desk", "a/b", String(repeating: "a", count: 65)] {
            #expect(DeskNameRule.newNameProblem(name) == DeskFormat.nameRule, "\(name)")
            #expect(DeskNameRule.newName(name) == nil, "\(name)")
        }
    }

    // MARK: the window's forms

    @Test func theNewDeskFormRefusesALeadingDash() {
        var f = NewDeskForm(check: dashedCheck(), saved: attic)
        f.setTypedPath("~/Development/old")
        f.setName("--old")
        #expect(f.nameProblem == Self.sentence)
        #expect(f.nameLine == Self.sentence && f.nameLineIsProblem)
        #expect(!f.canMake && f.request == nil)
        f.setName("old")
        #expect(f.canMake)
    }

    /// The form's taken-name check still comes after the rule: `--kill` is taken, but the dash is what is wrong.
    @Test func aTakenNameWithALeadingDashSaysTheDash() {
        #expect(DeskNameRule.problem("--kill", taken: ["--kill"], workhorse: "Attic") == Self.sentence)
    }

    @Test func theRenameFormRefusesALeadingDash() {
        var f = RenameForm(check: dashedCheck(), desk: "web")
        f.name = "--web"
        #expect(f.problem == Self.sentence && !f.canRename && f.newName == nil)
    }

    /// A desk called `--kill` can be renamed away from it in the window.
    @Test func aDeskWithALeadingDashCanBeRenamedInTheWindow() {
        var f = RenameForm(check: dashedCheck(), desk: "--kill")
        #expect(f.name == "--kill" && f.problem == nil && !f.canRename)
        f.name = "-kill"
        #expect(f.problem == Self.sentence && !f.canRename)
        f.name = "kill"
        #expect(f.problem == nil && f.canRename && f.newName == DeskName("kill"))
    }

    // MARK: the terminal's forms

    @Test func newDeskInTheTerminalRefusesALeadingDashBeforeSSH() async {
        let runner = FakeRunner { _ in FakeRunner.ok() }
        let ui = ScriptedInteraction()
        let result = await flow(runner).newDesk(dashedCheck(), request: NewDeskRequest(name: "--old", folder: "/x"), ui: ui)
        #expect(result.code == 1 && result.reason == Self.sentence)
        #expect(runner.calls.isEmpty && ui.asked.isEmpty)
    }

    @Test func theTerminalsQuestionAsksAgainAfterALeadingDash() async {
        let runner = FakeRunner { _ in FakeRunner.ok() }
        let ui = ScriptedInteraction(answers: ["--old", "old", "/Users/alex/old", ""])
        let result = await flow(runner).newDesk(dashedCheck(), request: NewDeskRequest(), ui: ui)
        #expect(result.code == 0)
        #expect(ui.said.first == Self.sentence)
        #expect(runner.calls.last?.argv.last == "~/.macmosh/macmosh-host desk-new old /Users/alex/old --reopen")
    }

    @Test func renameInTheTerminalRefusesALeadingDash() async {
        let runner = FakeRunner { _ in FakeRunner.ok() }
        let given = await flow(runner).renameDesk(dashedCheck(), from: "web", to: "--web", ui: ScriptedInteraction())
        #expect(given.code == 1 && given.reason == Self.sentence)
        #expect(runner.calls.isEmpty)

        let ui = ScriptedInteraction(answers: ["--web", "web2"])
        let asked = await flow(runner).renameDesk(dashedCheck(), from: "web", to: nil, ui: ui)
        #expect(asked.code == 0)
        #expect(ui.said.first == Self.sentence)
        #expect(runner.calls.last?.argv.last == "~/.macmosh/macmosh-host desk-rename web web2")
    }

    /// Three dashed answers: the stop names the rule the last answer broke, not the other one (review of #150).
    @Test func theTerminalStopsWithTheRuleTheLastAnswerBroke() async {
        let runner = FakeRunner { _ in FakeRunner.ok() }
        let stop = "That wasn't a desk name three times, so MacMosh stopped. \(Self.sentence)"
        let made = await flow(runner).newDesk(dashedCheck(), request: NewDeskRequest(),
                                              ui: ScriptedInteraction(answers: ["--old", "-x", "--kill"]))
        #expect(made.code == 1 && made.reason == stop)
        let renamed = await flow(runner).renameDesk(dashedCheck(), from: "web", to: nil,
                                                    ui: ScriptedInteraction(answers: ["--old", "-x", "--kill"]))
        #expect(renamed.code == 1 && renamed.reason == stop)
        #expect(runner.calls.isEmpty)
    }

    /// The old name is not a new one: a desk called `--kill` can still be renamed in the terminal.
    @Test func aDeskWithALeadingDashCanBeRenamedInTheTerminal() async {
        let runner = FakeRunner { _ in FakeRunner.ok() }
        let result = await flow(runner).renameDesk(dashedCheck(), from: "--kill", to: "kill", ui: ScriptedInteraction())
        #expect(result.code == 0)
        #expect(runner.calls.count == 1)
        #expect(runner.calls.last?.argv.last?.hasSuffix(" kill") == true)
    }

    // MARK: desks that already have such a name

    @Test func aDeskWithALeadingDashStillParsesAndShows() throws {
        #expect(DeskName("--kill")?.value == "--kill")
        let report = try HostStatus.parse(fixture("status/desks-board.txt").replacingOccurrences(of: "\nend\n", with: "\ndesk\t--kill\t1\t0\nwindow\t--kill\t0\tzsh\nend\n"))
        #expect(report.desks.map(\.name.value).contains("--kill"))

        let check = dashedCheck()
        let board = BoardModel.build(latest: ["attic": check], lastReady: [:], checking: [], order: [attic],
                                     waitingForDeskServer: [], ended: [:], results: [:], now: formatNow, timeZone: formatZone)
        #expect(board.workhorses.first?.desks.map(\.name).contains("--kill") == true)
        let menu = MenuModel.build([.checked(check)], now: formatNow, timeZone: formatZone)
        #expect(ids(menu.entries).contains("desk:attic:--kill"))
    }

    // MARK: a name made from a folder

    @Test func aNameFromAFolderDropsLeadingDashes() {
        #expect(NewDeskForm.name(fromFolder: "~/Development/--old") == "old")
        #expect(NewDeskForm.name(fromFolder: "/Users/alex/-x-y") == "x-y")
        // A dot becomes a dash first, and then goes too.
        #expect(NewDeskForm.name(fromFolder: "~/.config") == "config")
        #expect(NewDeskForm.name(fromFolder: "~/x/-" + String(repeating: "a", count: 80)) == String(repeating: "a", count: 64))
    }

    /// A folder that leaves nothing gives an empty name, and the form asks for one.
    @Test func aFolderOfOnlyDashesGivesNoName() {
        #expect(NewDeskForm.name(fromFolder: "~/Development/---") == "")
        #expect(NewDeskForm.name(fromFolder: "/Users/alex/...") == "")
        var f = NewDeskForm(check: dashedCheck(), saved: attic)
        f.setTypedPath("~/Development/---")
        #expect(f.name == "" && f.nameProblem == "Give the desk a name." && !f.canMake)
    }
}
