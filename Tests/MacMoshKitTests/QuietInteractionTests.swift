import Foundation
import Testing
@testable import MacMoshKit

/// The `Interaction` the window's actions run with (main window design, section 7.2): it never waits.
@Suite struct QuietInteractionTests {
    @Test func itCollectsWhatIsSaidInOrder() {
        let ui = QuietInteraction()
        ui.say("one")
        ui.say("two")
        #expect(ui.said == ["one", "two"])
    }

    @Test func everyQuestionIsAnsweredWithNothing() {
        let ui = QuietInteraction()
        #expect(ui.ask("Desk name: ") == "")
        #expect(ui.ask(DeskFlow.removeQuestion) == "")
        #expect(ui.said.isEmpty)
    }

    @Test func pressAKeyIsIgnored() {
        let ui = QuietInteraction()
        ui.waitForKey("Press any key to close.")
        #expect(ui.finish(1, reason: "It stopped.") == 1)
        #expect(ui.said == ["It stopped."])
    }

    /// The terminal form, run with it, can't wait on a question: an empty answer stops it, and nothing is removed.
    @Test func aFormThatAsksStopsAtOnceWithIt() async {
        let runner = FakeRunner { _ in FakeRunner.ok() }
        let check = CheckResult.sample(.ready(signIns: true), status: .sampleWithDesk, answeredAt: "workhorse")
        let result = await DeskFlow(commands: HostCommands(runner: runner, paths: .test))
            .removeDeskAsking(check, name: "website", ui: QuietInteraction())
        #expect(result.code != 0)
        #expect(runner.calls.isEmpty)
    }
}
