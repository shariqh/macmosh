#if DEBUG
import Foundation
import Testing
@testable import MacMoshKit

/// The sample menus CI takes pictures of (issue #113). They are built by the real model, so these
/// tests only check that each sample is the menu its name promises.
@Suite struct SampleMenuTests {
    private func menu(_ sample: SampleMenu, change: Int = 0) -> MenuLines {
        MenuModel.build(sample.gathered(change: change))
    }

    @Test func theSixDeskSampleHasSixDeskRowsOneClosedAndOneWithThreeWindows() {
        let rows = menu(.sixDesks).rows
        #expect(rows.first?.label == "Workhorse · Ready")
        let desks = rows.filter { $0.id.hasPrefix("desk:workhorse:") }
        #expect(desks.map(\.id) == ["website", "api", "notes", "blog", "shop", "garden"].map { "desk:workhorse:\($0)" })
        #expect(desks[0].title == "website (3 windows: claude, zsh, vim, kept running, permanent, open in 2 tabs)")
        #expect(desks[5].title == "garden (closed)")
        // Every desk's row opens a submenu and opens the desk when clicked.
        for desk in desks {
            guard case .submenu(let lines, let primary) = desk.kind else {
                Issue.record("\(desk.id) should open a submenu"); continue
            }
            #expect(primary != nil)
            #expect(lines.contains { $0.id == "\(desk.id):open" })
        }
        // The rows the CI job clicks.
        guard case .submenu(let api, _) = desks[1].kind else { return }
        #expect(api.map(\.id).contains("desk:workhorse:api:window"))
        #expect(menu(.sixDesks).symbol == "checkmark.circle")
    }

    @Test func eachOtherSampleIsTheStateItsNameSays() {
        #expect(menu(.signInsOff).symbol == "exclamationmark.circle")
        #expect(menu(.signInsOff).rows.contains { $0.id == "wh:workhorse:fix" })
        #expect(menu(.locked).rows.first?.label == "Workhorse · Locked after a restart")
        #expect(!menu(.locked).hasSubmenu)
        #expect(menu(.waitingForLogin).rows.first?.label == "Workhorse · Waiting for login")
        #expect(menu(.twoWorkhorses).rows.map(\.label).contains("Spare · Locked after a restart"))
        #expect(menu(.twoWorkhorses).hasSubmenu)
        #expect(menu(.noWorkhorses).items.count == 2)
        #expect(SampleMenu.noWorkhorses.workhorses.isEmpty)
    }

    @Test func theChangingSampleDiffersAtEveryChangeAndAddsAndRemovesADeskInTurn() {
        let menus = (0..<4).map { menu(.changing, change: $0) }
        for i in 1..<menus.count { #expect(menus[i] != menus[i - 1]) }
        let scratch = menus.map { $0.rows.contains { $0.id == "desk:workhorse:scratch" } }
        #expect(scratch == [false, true, false, true])
        // The row CI rests on stays the same, so the pointer stays on it.
        for m in menus {
            #expect(m.rows.first { $0.id == "desk:workhorse:website" }?.title
                    == menu(.sixDesks).rows.first { $0.id == "desk:workhorse:website" }?.title)
        }
    }

    @Test func aSampleRunsNothingReal() async {
        let outcome = await SampleMenu.actions.outcome(of: .tab(["connect", "workhorse", "website"]), title: "website")
        #expect(outcome == ActionOutcome(summary: "tab opened", notice: nil))
        let ran = await SampleMenu.actions.outcome(of: .run(["desk", "window", "workhorse", "api"]), title: "New window")
        #expect(ran == ActionOutcome(summary: "ran", notice: nil))
    }
}
#endif
