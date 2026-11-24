import Foundation
import Testing
@testable import MacMoshKit

/// What a window button runs today (main window design, section 8, step 3): the menu's own action as it
/// is, and for the window's own actions the menu action that does the same thing until the window's
/// forms exist (step 4).
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

    /// New desk, Rename and Remove open the same terminal tab as the menu's lines, which ask their questions.
    @Test func newDeskRenameAndRemoveRunTheMenusTabUntilTheFormsExist() {
        #expect(WindowRun.menuAction(for: .window(.newDesk(workhorse: "attic"))) == .tab(["desk", "new", "attic"]))
        #expect(WindowRun.menuAction(for: .window(.rename(workhorse: "attic", desk: "website")))
                == .tab(["desk", "rename", "attic", "website"]))
        #expect(WindowRun.menuAction(for: .window(.remove(workhorse: "attic", desk: "website")))
                == .tab(["desk", "remove", "attic", "website", "--ask"]))
    }

    /// The mapping is the way back of `BoardAction.init`: each of the menu's own buttons for these
    /// comes back to the very action the menu runs.
    @Test func theMappingGivesBackTheMenusOwnActions() {
        let menuButtons = [ButtonRules.newDesk("attic")]
            + ButtonRules.forDesk(workhorse: "attic", desk: "website", isOpen: true)
        for button in menuButtons {
            #expect(WindowRun.menuAction(for: BoardAction(button.action)) == button.action)
        }
    }

    @Test func openTheOnesNotInATabOpensOnePlainConnectTabForEach() {
        #expect(WindowRun.menuAction(for: .window(.openAllWithoutTab(workhorse: "attic", desks: ["api", "blog"])))
                == .tabs([["connect", "attic", "api"], ["connect", "attic", "blog"]]))
        #expect(WindowRun.menuAction(for: .window(.openAllWithoutTab(workhorse: "attic", desks: ["api"])))
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
        let all: [WindowAction] = [.newDesk(workhorse: "attic"), .rename(workhorse: "attic", desk: "website"),
                                   .remove(workhorse: "attic", desk: "website"),
                                   .openAllWithoutTab(workhorse: "attic", desks: ["api", "blog"])]
        for action in all {
            let words = WindowRun.menuAction(for: .window(action))?.words ?? []
            #expect(!words.isEmpty && words.allSatisfy(PlainWords.isPlain))
        }
    }
}
