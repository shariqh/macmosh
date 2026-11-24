import Foundation
import Testing
@testable import MacMoshKit

/// The rules for which buttons go with which state, read by the menu and (later) the window.
@Suite struct ButtonRulesTests {
    private func titles(_ buttons: [ActionButton]) -> [String] { buttons.map(\.title) }

    @Test func eachStateGetsItsOwnButtonsUnderTheHint() {
        let able = Workhorse.sample(osVersion: "27.3", arch: "arm64")
        let old = Workhorse.sample(osVersion: "15.6", arch: "arm64")
        let rows: [(WorkhorseState, Workhorse, [ActionButton])] = [
            (.ready(signIns: true), .sample(), []),
            (.ready(signIns: false), .sample(),
             [ActionButton(key: "fix", title: "Fix…", action: .tab(["prepare", "mbp", "--restart-desk-server", "--pause"]))]),
            (.waitingForLogin, .sample(),
             [ActionButton(key: "login", title: "Log in…  (opens Screen Sharing)", action: .run(["screen", "mbp"]))]),
            (.locked, able,
             [ActionButton(key: "unlock", title: "Unlock disk…  (you type the Mac's password)", action: .tab(["unlock", "mbp"]))]),
            (.locked, old, []),
            (.cantVerify, .sample(), []),
            (.cantReach(.nothingAnswers), .sample(), []),
            (.notSetUp(.notPaired), .sample(),
             [ActionButton(key: "pair", title: "Pair…", action: .tab(["pair", "mbp"]))]),
            (.notSetUp(.deskServerDown), .sample(),
             [ActionButton(key: "finish", title: "Finish setting up…", action: .tab(["prepare", "mbp", "--fix", "--pause"]))]),
            (.notSetUp(.hostScriptMissing), .sample(),
             [ActionButton(key: "finish", title: "Finish setting up…", action: .tab(["prepare", "mbp", "--fix", "--pause"]))]),
        ]
        for (state, w, want) in rows {
            #expect(ButtonRules.forState(.sample(state, workhorse: w, status: .sampleWithDesk)) == want, "\(state)")
        }
    }

    @Test func aReadyWorkhorseGetsNewDeskShareAndRestart() {
        var desktop = HostStatus.sampleWithDesk
        desktop.battery = .init(present: false, onAC: nil, percent: nil)
        let r = CheckResult.sample(.ready(signIns: true), status: desktop)
        #expect(ButtonRules.forReady(r) == [
            ActionButton(key: "newDesk", title: "New desk…", action: .tab(["desk", "new", "mbp"])),
            ActionButton(key: "share", title: "Share screen", action: .run(["screen", "mbp"])),
            ActionButton(key: "restart", title: "Restart…", action: .tab(["restart", "mbp"])),
        ])
    }

    @Test func aWorkhorseThatIsNotReadyGetsNoReadyButtons() {
        for state in [WorkhorseState.waitingForLogin, .locked, .cantReach(.nothingAnswers), .notSetUp(.notPaired)] {
            #expect(ButtonRules.forReady(.sample(state, status: .sampleWithDesk)).isEmpty, "\(state)")
        }
    }

    /// Changed on purpose for issue #107: the lid switch comes before Restart…, the menu's order.
    @Test func aLaptopAlsoGetsItsLidSwitch() {
        for (lid, title, word) in [(1, "Turn off lid-closed mode…", "off"), (0, "Turn on lid-closed mode…", "on")] as [(Int?, String, String)] {
            var status = HostStatus.sampleWithDesk
            status.power.disableSleep = lid
            let buttons = ButtonRules.forReady(.sample(.ready(signIns: true), status: status))
            #expect(titles(buttons) == ["New desk…", "Share screen", title, "Restart…"])
            #expect(buttons[2] == ActionButton(key: "lid", title: title, action: .tab(["power", "mbp", "lid", word])))
        }
        var unknown = HostStatus.sampleWithDesk
        unknown.power.disableSleep = nil
        #expect(titles(ButtonRules.forReady(.sample(.ready(signIns: true), status: unknown)))[2] == "Turn on lid-closed mode…")
    }

    /// Changed on purpose for issue #107: a desk's buttons start with Open (what a click on the desk's row
    /// does too), and the window line reads New window, since it is in the desk's own submenu.
    @Test func anOpenDeskGetsANewWindowLineAndAClosedOneDoesNot() {
        #expect(ButtonRules.forDesk(workhorse: "mbp", desk: "website", isOpen: true) == [
            ActionButton(key: "open", title: "Open website", action: .tab(["connect", "mbp", "website"])),
            ActionButton(key: "window", title: "New window", action: .run(["desk", "window", "mbp", "website"])),
            ActionButton(key: "rename", title: "Rename website…", action: .tab(["desk", "rename", "mbp", "website"])),
            ActionButton(key: "remove", title: "Remove website…", action: .tab(["desk", "remove", "mbp", "website", "--ask"])),
        ])
        #expect(titles(ButtonRules.forDesk(workhorse: "mbp", desk: "notes", isOpen: false))
                == ["Open notes", "Rename notes…", "Remove notes…"])
        #expect(ButtonRules.connect(workhorse: "mbp", desk: "website") == .tab(["connect", "mbp", "website"]))
    }

    /// The headline's submenu (issue #107): Share screen, a laptop's lid-closed switch, Restart…. New desk…
    /// stays at the top level. None in any other state.
    @Test func aReadyHeadlineGetsShareTheLidSwitchAndRestart() {
        var lid = HostStatus.sampleWithDesk
        lid.power.disableSleep = 1
        #expect(ButtonRules.forHeadline(.sample(.ready(signIns: true), status: lid)) == [
            ActionButton(key: "share", title: "Share screen", action: .run(["screen", "mbp"])),
            ActionButton(key: "lid", title: "Turn off lid-closed mode…", action: .tab(["power", "mbp", "lid", "off"])),
            ActionButton(key: "restart", title: "Restart…", action: .tab(["restart", "mbp"])),
        ])
        var desktop = HostStatus.sampleWithDesk
        desktop.battery = .init(present: false, onAC: nil, percent: nil)
        #expect(titles(ButtonRules.forHeadline(.sample(.ready(signIns: false), status: desktop))) == ["Share screen", "Restart…"])
        #expect(ButtonRules.forHeadline(.sample(.locked, status: .sampleWithDesk)).isEmpty)
        #expect(ButtonRules.newDesk("mbp") == ActionButton(key: "newDesk", title: "New desk…", action: .tab(["desk", "new", "mbp"])))
        // forReady is exactly what the menu builds, in its order: New desk…, then the headline's buttons.
        let r = CheckResult.sample(.ready(signIns: true), status: lid)
        #expect(ButtonRules.forReady(r) == [ButtonRules.newDesk("mbp")] + ButtonRules.forHeadline(r))
    }

    @Test func everyWorkhorseHasTheChecklistAndTheMenuEndsWithTwoButtons() {
        #expect(ButtonRules.checklist("mbp") == ActionButton(key: "checklist", title: "Run the checklist…",
                                                            action: .tab(["prepare", "mbp", "--pause"])))
        #expect(ButtonRules.addAMac == ActionButton(key: "add", title: "Add a Mac…", action: .tab(["pair"])))
        #expect(ButtonRules.checkNow == ActionButton(key: "check", title: "Check now", action: .refresh))
    }

    // MARK: Which desks, and the block of one workhorse (main window, step 2)

    /// The open desks in the report's order, then each closed permanent desk. A definition with no
    /// session that is not permanent is a leftover and gets nothing; a session with no definition
    /// (made by hand) is there, with no definition.
    @Test func theDesksAreTheOpenOnesThenTheClosedPermanentOnes() {
        var s = HostStatus.sampleWithDesk
        s.desks.append(.init(name: DeskName("byhand")!, windows: [.init(index: 0, name: "zsh")],
                             windowCount: 1, attached: 0))
        s.definitions = [
            .init(name: DeskName("notes")!, reopen: true, keep: false, folder: "/Users/alex/notes", command: "",
                  permanent: true),
            .init(name: DeskName("website")!, reopen: true, keep: true, folder: "/Users/alex/site", command: "npm run dev"),
            .init(name: DeskName("shop")!, reopen: true, keep: false, folder: "/Users/alex/shop", command: ""),
        ]
        let desks = ButtonRules.desks(.sample(.ready(signIns: true), status: s))
        #expect(desks.map(\.name) == ["website", "byhand", "notes"])
        #expect(desks.map(\.isOpen) == [true, true, false])
        #expect(desks[0].definition?.folder == "/Users/alex/site")
        #expect(desks[0].isKept && !desks[0].isPermanent)
        #expect(desks[1].definition == nil && desks[1].session?.windowCount == 1)
        #expect(desks[2].session == nil && desks[2].isPermanent)
        #expect(desks[0].buttons == ButtonRules.forDesk(workhorse: "mbp", desk: "website", isOpen: true))
        #expect(desks[2].buttons == ButtonRules.forDesk(workhorse: "mbp", desk: "notes", isOpen: false))
        #expect(ButtonRules.desks(.sample(.ready(signIns: true), status: nil)).isEmpty)
    }

    /// A Ready workhorse's buttons, desks aside, in the order both faces show them: the state's, New
    /// desk…, the rarer ones, the checklist.
    @Test func aReadyBlockHasItsButtonsInTheMenusOrder() {
        let r = CheckResult.sample(.ready(signIns: false), status: .sampleWithDesk, homeReachable: false)
        let block = WorkhorseBlock.of(r, waitingForDeskServer: [], now: formatNow, timeZone: formatZone)
        #expect(block.kind == .ready)
        #expect(block.headline == StatusFormat.headline(r))
        #expect(block.hint == StatusFormat.hint(r))
        #expect(titles(block.buttons) == ["Fix…", "New desk…", "Share screen", "Turn on lid-closed mode…",
                                         "Restart…", "Run the checklist…"])
        #expect(block.buttons == ButtonRules.forState(r) + ButtonRules.forReady(r) + [ButtonRules.checklist("mbp")])
        #expect(block.desks.map(\.name) == ["website"])
        #expect(block.summary == StatusFormat.summaryLine(.sampleWithDesk))
        #expect(block.homeReachable == false)
        #expect(WorkhorseBlock.homeLine(false) == "Home address reachable from here: no")
    }

    @Test func aBlockThatIsNotReadyHasItsStatesButtonAndTheChecklistOnly() {
        let able = Workhorse.sample(osVersion: "27.3", arch: "arm64")
        let r = CheckResult.sample(.locked, workhorse: able, status: .sampleWithDesk, homeReachable: true)
        let block = WorkhorseBlock.of(r, waitingForDeskServer: [], now: formatNow, timeZone: formatZone)
        #expect(block.kind == .other)
        #expect(titles(block.buttons) == ["Unlock disk…  (you type the Mac's password)", "Run the checklist…"])
        #expect(block.desks.isEmpty && block.newDesk == nil && block.rareButtons.isEmpty)
        #expect(block.summary == nil && block.homeReachable == nil)
    }

    /// Waiting for the desk server: its own headline and hint, and only the checklist; only when the
    /// state is "Desk server is off" and the id is in the set.
    @Test func theDeskServerWaitHasItsOwnHeadlineAndOnlyTheChecklist() {
        let down = CheckResult.sample(.notSetUp(.deskServerDown), status: .sampleReady)
        let block = WorkhorseBlock.of(down, waitingForDeskServer: ["mbp"], now: formatNow, timeZone: formatZone)
        #expect(block.kind == .waitingForDeskServer)
        #expect(block.headline == "MacBook Pro · Waiting for the desk server")
        #expect(block.hint == MenuModel.waitingForDeskServerHint)
        #expect(titles(block.buttons) == ["Run the checklist…"])
        #expect(WorkhorseBlock.isWaitingForDeskServer(down, ["mbp"]))
        #expect(!WorkhorseBlock.isWaitingForDeskServer(down, []))
        #expect(!WorkhorseBlock.isWaitingForDeskServer(.sampleReady(), ["mbp"]))
        let notWaiting = WorkhorseBlock.of(down, waitingForDeskServer: [], now: formatNow, timeZone: formatZone)
        #expect(titles(notWaiting.buttons) == ["Finish setting up…", "Run the checklist…"])
    }

    @Test func aWorkhorseThatHasNotAnsweredHasTheChecklistOnly() {
        let block = WorkhorseBlock.stillChecking(.sample(id: "attic", name: "Attic"))
        #expect(block.kind == .stillChecking)
        #expect(block.headline == "Attic · Still checking…")
        #expect(block.hint == nil)
        #expect(block.buttons == [ButtonRules.checklist("attic")])
    }

    @Test func noTwoButtonsInOneGroupShareAKey() {
        var lid = HostStatus.sampleWithDesk
        lid.power.disableSleep = 1
        let ready = ButtonRules.forReady(.sample(.ready(signIns: false), status: lid))
        let mixed = ButtonRules.forState(.sample(.ready(signIns: false), status: lid)) + ready + [ButtonRules.checklist("mbp")]
        #expect(Set(mixed.map(\.key)).count == mixed.count)
        let desk = ButtonRules.forDesk(workhorse: "mbp", desk: "website", isOpen: true)
        #expect(Set(desk.map(\.key)).count == desk.count)
    }
}
