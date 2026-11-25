import Foundation
import Testing
@testable import MacMoshKit

/// What a window button runs (main window design, sections 8, steps 3 and 4): the menu's own action as it
/// is, the window's forms for New desk, Rename and Remove, and the tabs of "Open the N not in a tab".
@Suite struct WindowRunTests {
    @Test func aButtonThatCarriesAMenuActionRunsItAsItIs() {
        let actions: [MenuAction] = [
            .tab(["connect", "attic", "website"]), .run(["desk", "window", "attic", "api"]), .run(["screen", "attic"]),
            .tab(["prepare", "attic", "--pause"]), .refresh, .tabs([["connect", "attic", "a"]]),
            .focus(label: "x", orOpen: ["connect", "attic", "a"]), .none,
        ]
        for action in actions {
            #expect(WindowRun.menuAction(for: .menu(action)) == action)
        }
    }

    /// New desk, Rename and Remove open the window's own forms (step 4), never the menu's terminal tab.
    @Test func newDeskRenameAndRemoveOpenTheWindowsForms() {
        #expect(WindowRun.menuAction(for: .window(.newDesk(workhorse: "attic"))) == nil)
        #expect(WindowRun.menuAction(for: .window(.rename(workhorse: "attic", desk: "website"))) == nil)
        #expect(WindowRun.menuAction(for: .window(.remove(workhorse: "attic", desk: "website"))) == nil)
        #expect(WindowRun.form(for: .window(.newDesk(workhorse: "attic"))) == .newDesk(workhorse: "attic"))
        #expect(WindowRun.form(for: .window(.rename(workhorse: "attic", desk: "website"))) == .rename(workhorse: "attic", desk: "website"))
        #expect(WindowRun.form(for: .window(.remove(workhorse: "attic", desk: "website"))) == .remove(workhorse: "attic", desk: "website"))
        #expect(WindowRun.form(for: .menu(.tab(["desk", "new", "attic"]))) == nil)
    }

    /// The menu keeps its terminal tabs: its own New desk…, Rename… and Remove… lines are unchanged.
    @Test func theMenusOwnLinesStillOpenTheirTabs() {
        #expect(ButtonRules.newDesk("attic").action == .tab(["desk", "new", "attic"]))
        let desk = ButtonRules.forDesk(workhorse: "attic", desk: "website", isOpen: true)
        #expect(desk.first { $0.key == "rename" }?.action == .tab(["desk", "rename", "attic", "website"]))
        #expect(desk.first { $0.key == "remove" }?.action == .tab(["desk", "remove", "attic", "website", "--ask"]))
    }

    /// The window's other buttons carry the menu's own action, as the menu's lines run it.
    @Test func theMappingGivesBackTheMenusOwnActions() {
        for button in ButtonRules.forDesk(workhorse: "attic", desk: "website", isOpen: true)
            where button.key == "open" || button.key == "window" {
            #expect(WindowRun.menuAction(for: BoardAction(button.action)) == button.action)
        }
    }

    /// The tabs the board worked out, in its order, through the menu's own `.tabs` (and so its guard against a
    /// second tab on a window that has one).
    @Test func openTheOnesNotInATabOpensTheTabsTheBoardListed() {
        let tabs = [["connect", "attic", "api", "--window", "@5"], ["connect", "attic", "blog"]]
        #expect(WindowRun.menuAction(for: .window(.openAllWithoutTab(workhorse: "attic", tabs: tabs))) == .tabs(tabs))
        #expect(WindowRun.menuAction(for: .window(.openAllWithoutTab(workhorse: "attic", tabs: [["connect", "attic", "api"]])))
                == .tabs([ButtonRules.connect(workhorse: "attic", desk: "api").words]))
    }

    /// Start again and Forget have nothing to run until the ended desks exist (step 5).
    @Test func startAgainAndForgetRunNothingYet() {
        #expect(WindowRun.menuAction(for: .window(.startAgain(workhorse: "attic", desk: "a", keepIt: false))) == nil)
        #expect(WindowRun.menuAction(for: .window(.startAgain(workhorse: "attic", desk: "a", keepIt: true))) == nil)
        #expect(WindowRun.menuAction(for: .window(.forget(workhorse: "attic", desk: "a"))) == nil)
    }

    /// Every argument handed on is a plain word, as `TabCommand` requires.
    @Test func everyMappedActionUsesPlainWords() {
        let all: [WindowAction] = [.openAllWithoutTab(workhorse: "attic", tabs: [["connect", "attic", "api"],
                                                                                 ["connect", "attic", "blog", "--window", "@8"]])]
        for action in all {
            let words = WindowRun.menuAction(for: .window(action))?.words ?? []
            #expect(!words.isEmpty && words.allSatisfy(PlainWords.isPlain))
        }
    }
}
