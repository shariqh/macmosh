import Foundation
import Testing
@testable import MacMoshKit

private let path = "/Users/alex/.local/bin/macmosh"

private func render(_ items: [MenuItem], symbol: String = "checkmark.circle") -> String {
    SwiftBarRenderer.render(Menu(symbol: symbol, items: items), macmoshPath: path)
}

private func one(_ title: String, _ action: MenuAction = .none, indent: Int = 0) -> MenuItem {
    MenuItem(title: title, action: action, indent: indent, isSeparator: false)
}

private let separator = MenuItem(title: "", action: .none, indent: 0, isSeparator: true)

/// The lines of the output after the header and its `---`.
private func body(_ text: String) -> [String] {
    Array(text.split(separator: "\n", omittingEmptySubsequences: false).dropFirst(2).dropLast())
        .map(String.init)
}

@Suite struct SwiftBarRendererTests {
    @Test func aTabActionBecomesAnOpenCall() {
        let menu = Menu(symbol: "checkmark.circle", items: [
            MenuItem(title: "website (2 windows)", action: .tab(["connect", "mbp", "website"]), indent: 1,
                     isSeparator: false),
        ])
        #expect(SwiftBarRenderer.render(menu, macmoshPath: "/Users/alex/.local/bin/macmosh") == """
             | sfimage=checkmark.circle
            ---
               website (2 windows) | bash=/Users/alex/.local/bin/macmosh param0=open param1=connect param2=mbp param3=website terminal=false

            """)
    }

    @Test func aRunActionChecksAgainAfterwards() {
        let text = render([one("Share screen", .run(["screen", "mbp"]), indent: 1)])
        #expect(body(text) == ["   Share screen | bash=\(path) param0=screen param1=mbp terminal=false refresh=true"])
    }

    @Test func aRefreshActionAndAPlainLine() {
        let text = render([one("Check now", .refresh), one("Just text")])
        #expect(body(text) == ["Check now | refresh=true", "Just text"])
    }

    @Test func eachLevelIsThreeSpaces() {
        let text = render([one("a", indent: 0), one("b", indent: 1), one("c", indent: 2)])
        #expect(body(text) == ["a", "   b", "      c"])
    }

    @Test func separatorsAreThreeDashes() {
        let text = render([one("a"), separator, one("b")])
        #expect(body(text) == ["a", "---", "b"])
        #expect(text.hasPrefix(" | sfimage=checkmark.circle\n---\n"))
    }

    @Test func aBarInANameCannotBreakALine() {
        let text = render([one("Work | Mac", .tab(["connect", "mbp", "x"]), indent: 1)])
        #expect(body(text) == ["   Work / Mac | bash=\(path) param0=open param1=connect param2=mbp param3=x terminal=false"])
    }

    @Test func aNewLineInANameCannotBreakALine() {
        let text = render([one("Line one\nline two\r\nthree\u{2028}four", indent: 0)])
        #expect(body(text) == ["Line one line two  three four"])
    }

    @Test func aNameStartingWithADashIsNotASeparatorOrSubmenu() {
        let text = render([one("--- Mac · Ready"), one("-x")])
        for line in body(text) {
            // Only plain spaces are skipped: the guard in front of the dash is a no-break space.
            let first = line.drop { $0 == " " }.first
            #expect(first != "-", "\(line)")
        }
    }

    @Test func anActionWithUnplainWordsIsDroppedNotQuotedWrong() {
        let text = render([one("Open", .tab(["connect", "a b", "x"])), one("Run", .run(["x;y"]))])
        #expect(body(text) == ["Open", "Run"])
        let badPath = SwiftBarRenderer.render(
            Menu(symbol: "plus.circle", items: [one("Open", .tab(["pair"]))]), macmoshPath: "/Users/a b/macmosh")
        #expect(body(badPath) == ["Open"])
    }

    @Test func theErrorMenuIsTheWarningIconAndOneLine() {
        #expect(SwiftBarRenderer.errorMenu("Can't read MacMosh's saved settings: x | y") == """
             | sfimage=exclamationmark.triangle
            ---
            Can't read MacMosh's saved settings: x / y

            """)
    }

    @Test func aWholeMenuRendersEachItem() {
        let text = SwiftBarRenderer.render(MenuModel.build([.checked(.sampleReady(id: "mbp"))]), macmoshPath: path)
        #expect(text.hasPrefix(" | sfimage=checkmark.circle\n---\nMacBook Pro · Ready\n"))
        #expect(text.contains("   website (2 windows: zsh, vim, open in 1 tab) | bash=\(path) param0=open param1=connect param2=mbp param3=website terminal=false\n"))
        #expect(text.contains("      New window in website | bash=\(path) param0=desk param1=window param2=mbp param3=website terminal=false refresh=true\n"))
        #expect(text.hasSuffix("Add a Mac… | bash=\(path) param0=open param1=pair terminal=false\nCheck now | refresh=true\n"))
    }

    @Test func theOwnPathIsMadeAbsoluteFromTheCurrentFolder() {
        #expect(SwiftBarRenderer.absolutePath(of: "/Users/alex/.local/bin/macmosh", in: "/tmp") == "/Users/alex/.local/bin/macmosh")
        #expect(SwiftBarRenderer.absolutePath(of: "./bin/macmosh", in: "/work/mm") == "/work/mm/bin/macmosh")
        #expect(SwiftBarRenderer.absolutePath(of: "../macmosh", in: "/work/mm") == "/work/macmosh")
    }
}

@Suite struct MenuDataTests {
    @Test func rendersWithinTheBudgetWhenNothingAnswers() async {
        let slow = FakeRunner.sleeping(.seconds(30))
        let clock = ContinuousClock()
        let start = clock.now
        let gathered = await MenuData.gather([.sample(id: "a"), .sample(id: "b")],
                                             checker: StatusChecker(runner: slow, paths: .test, hints: FixedHints(.allFine)),
                                             budget: .seconds(1))
        #expect(clock.now - start < .seconds(3))
        #expect(MenuModel.build(gathered).items.contains { $0.title.hasSuffix("Still checking…") })
        #expect(gathered == [.stillChecking(.sample(id: "a")), .stillChecking(.sample(id: "b"))])
    }

    @Test func aFastWorkhorseIsCheckedAndASlowOneIsNot() async {
        let runner = FakeRunner { argv in
            guard sshTarget(argv) == "alex@fast" else { return sshTimedOut }
            return FakeRunner.ok("")
        }
        // The slow one's runner never answers in time: a runner that sleeps only for its address.
        let mixed = MixedRunner(fast: "alex@fast", fastAnswer: runner)
        let list = [Workhorse.sample(id: "slow", mainAddress: "slow"), Workhorse.sample(id: "fast", mainAddress: "fast")]
        let gathered = await MenuData.gather(list, checker: StatusChecker(runner: mixed, paths: .test, hints: FixedHints(.allFine)),
                                             budget: .seconds(2))
        #expect(gathered.count == 2)
        #expect(gathered[0] == .stillChecking(list[0]))
        if case .checked(let result) = gathered[1] { #expect(result.workhorse.id == "fast") } else { Issue.record("fast was not checked") }
    }

    @Test func noWorkhorsesGatherNothingAtOnce() async {
        let clock = ContinuousClock()
        let start = clock.now
        let gathered = await MenuData.gather([], checker: StatusChecker(runner: FakeRunner.sleeping(.seconds(30)), paths: .test,
                                                                       hints: FixedHints(.allFine)), budget: .seconds(20))
        #expect(gathered.isEmpty)
        #expect(clock.now - start < .seconds(1))
    }

    @Test func everythingAnsweringEndsTheCallBeforeTheBudget() async {
        let quick = FakeRunner { _ in sshTimedOut }
        let clock = ContinuousClock()
        let start = clock.now
        let gathered = await MenuData.gather([.sample(id: "a"), .sample(id: "b")],
                                             checker: StatusChecker(runner: quick, paths: .test, hints: FixedHints(.allFine)),
                                             budget: .seconds(30))
        #expect(clock.now - start < .seconds(5))
        #expect(gathered.count == 2)
        for entry in gathered { if case .stillChecking = entry { Issue.record("expected a checked result") } }
    }

    @Test func theResultsKeepTheOrderOfTheInput() async {
        let quick = FakeRunner { _ in sshTimedOut }
        let list = (0..<6).map { Workhorse.sample(id: "w\($0)", name: "W\($0)") }
        let gathered = await MenuData.gather(list, checker: StatusChecker(runner: quick, paths: .test, hints: FixedHints(.allFine)),
                                             budget: .seconds(30))
        let ids: [String] = gathered.map { entry in
            switch entry {
            case .checked(let r): return r.workhorse.id
            case .stillChecking(let w): return w.id
            }
        }
        #expect(ids == list.map(\.id))
    }
}

/// Answers quickly for one ssh target and hangs (until cancelled) for every other.
private struct MixedRunner: CommandRunner {
    let fast: String
    let fastAnswer: FakeRunner

    func run(_ executable: String, _ arguments: [String], environment: [String: String],
             stdin: Data?, timeout: Duration) async -> CommandResult {
        if (([executable] + arguments).contains(fast)) {
            return await fastAnswer.run(executable, arguments, environment: environment, stdin: stdin, timeout: timeout)
        }
        try? await Task.sleep(for: .seconds(30))
        return CommandResult(exitCode: -1, stdout: "", stderr: "", timedOut: true)
    }
}
