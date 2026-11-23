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

    @Test func aLaptopAlsoGetsItsLidSwitch() {
        for (lid, title, word) in [(1, "Turn off lid-closed mode…", "off"), (0, "Turn on lid-closed mode…", "on")] as [(Int?, String, String)] {
            var status = HostStatus.sampleWithDesk
            status.power.disableSleep = lid
            let buttons = ButtonRules.forReady(.sample(.ready(signIns: true), status: status))
            #expect(titles(buttons) == ["New desk…", "Share screen", "Restart…", title])
            #expect(buttons.last == ActionButton(key: "lid", title: title, action: .tab(["power", "mbp", "lid", word])))
        }
        var unknown = HostStatus.sampleWithDesk
        unknown.power.disableSleep = nil
        #expect(titles(ButtonRules.forReady(.sample(.ready(signIns: true), status: unknown))).last == "Turn on lid-closed mode…")
    }

    @Test func anOpenDeskGetsANewWindowLineAndAClosedOneDoesNot() {
        #expect(ButtonRules.forDesk(workhorse: "mbp", desk: "website", isOpen: true) == [
            ActionButton(key: "window", title: "New window in website", action: .run(["desk", "window", "mbp", "website"])),
            ActionButton(key: "rename", title: "Rename website…", action: .tab(["desk", "rename", "mbp", "website"])),
            ActionButton(key: "remove", title: "Remove website…", action: .tab(["desk", "remove", "mbp", "website", "--ask"])),
        ])
        #expect(titles(ButtonRules.forDesk(workhorse: "mbp", desk: "notes", isOpen: false)) == ["Rename notes…", "Remove notes…"])
        #expect(ButtonRules.connect(workhorse: "mbp", desk: "website") == .tab(["connect", "mbp", "website"]))
    }

    @Test func everyWorkhorseHasTheChecklistAndTheMenuEndsWithTwoButtons() {
        #expect(ButtonRules.checklist("mbp") == ActionButton(key: "checklist", title: "Run the checklist…",
                                                            action: .tab(["prepare", "mbp", "--pause"])))
        #expect(ButtonRules.addAMac == ActionButton(key: "add", title: "Add a Mac…", action: .tab(["pair"])))
        #expect(ButtonRules.checkNow == ActionButton(key: "check", title: "Check now", action: .refresh))
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
