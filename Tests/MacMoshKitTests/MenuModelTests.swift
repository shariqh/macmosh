import AppKit
import Foundation
import Testing
@testable import MacMoshKit

private func titles(_ menu: Menu) -> [String] { menu.items.map(\.title) }

private func item(_ menu: Menu, _ title: String) -> MenuItem? { menu.items.first { $0.title == title } }

private func menu(_ state: WorkhorseState, workhorse: Workhorse = .sample(), status: HostStatus? = nil,
                  homeReachable: Bool? = nil) -> Menu {
    MenuModel.build([.checked(.sample(state, workhorse: workhorse, status: status, homeReachable: homeReachable))])
}

@Suite struct MenuModelTests {
    @Test func theReadyMenuMatchesTheDesign() {
        let menu = MenuModel.build([.checked(.sampleReady(id: "mbp", name: "MacBook Pro"))])
        let expected: [String] = [
            "MacBook Pro · Ready", "website (2 windows: zsh, vim, open in 1 tab)", "New window in website",
            "New desk…", "Share screen", "Restart…", "Sign-ins working · Awake on power · On power, 82%",
            "Home address reachable from here: yes",
        ]
        #expect(Array(titles(menu).prefix(8)) == expected)
        #expect(menu.symbol == "checkmark.circle")
        #expect(menu.items[1].action == .tab(["connect", "mbp", "website"]))
    }

    @Test func theReadyMenuHasTheDesignsActionsAndIndents() {
        let menu = MenuModel.build([.checked(.sampleReady(id: "mbp"))])
        #expect(menu.items[0].indent == 0)
        #expect(menu.items[1].indent == 1)
        #expect(menu.items[2].indent == 2)
        #expect(menu.items[2].action == .run(["desk", "window", "mbp", "website"]))
        #expect(item(menu, "New desk…")?.action == .tab(["desk", "new", "mbp"]))
        #expect(item(menu, "Share screen")?.action == .run(["screen", "mbp"]))
        #expect(item(menu, "Restart…")?.action == .tab(["restart", "mbp"]))
        #expect(item(menu, "Restart…")?.indent == 1)
    }

    @Test func theMenuEndsWithTheChecklistAndTheTwoButtons() {
        let menu = MenuModel.build([.checked(.sampleReady(id: "mbp"))])
        let last = Array(menu.items.suffix(4))
        #expect(last[0].title == "Run the checklist…")
        #expect(last[0].action == .tab(["prepare", "mbp", "--pause"]))
        #expect(last[1].isSeparator)
        #expect(last[2].title == "Add a Mac…")
        #expect(last[2].action == .tab(["pair"]))
        #expect(last[2].indent == 0)
        #expect(last[3].title == "Check now")
        #expect(last[3].action == .refresh)
    }

    @Test func singularWindowAndTabsAndNoTabs() {
        var status = HostStatus.sampleReady
        status.desks = [
            .init(name: DeskName("notes")!, windows: [.init(index: 0, name: "zsh")], windowCount: 1, attached: 0),
            .init(name: DeskName("api")!, windows: [.init(index: 0, name: "a"), .init(index: 1, name: "b")],
                  windowCount: 2, attached: 2),
        ]
        let m = menu(.ready(signIns: true), status: status)
        #expect(item(m, "notes (1 window: zsh)") != nil)
        #expect(item(m, "api (2 windows: a, b, open in 2 tabs)") != nil)
    }

    @Test func theHomeLightIsLeftOutWhenUnknownAndSaysNoWhenNo() {
        let unknown = menu(.ready(signIns: true), status: .sampleWithDesk, homeReachable: nil)
        #expect(!titles(unknown).contains { $0.hasPrefix("Home address") })
        let no = menu(.ready(signIns: true), status: .sampleWithDesk, homeReachable: false)
        #expect(titles(no).contains("Home address reachable from here: no"))
    }

    // MARK: one test per row of the state table

    @Test func readyWithSignInsOffAddsTheHintAndFix() {
        let m = menu(.ready(signIns: false), status: .sampleWithDesk)
        #expect(m.symbol == "exclamationmark.circle")
        #expect(titles(m)[0] == "MacBook Pro · Ready, sign-ins off")
        #expect(titles(m)[1] == "Tools that keep logins in the keychain look signed out here.")
        #expect(item(m, "Fix…")?.action == .tab(["prepare", "mbp", "--restart-desk-server", "--pause"]))
        #expect(item(m, "Share screen") != nil)
    }

    @Test func waitingForLoginOffersLogIn() {
        let m = menu(.waitingForLogin)
        #expect(titles(m)[1] == "It is on and unlocked, but nobody has logged in.")
        #expect(item(m, "Log in…  (opens Screen Sharing)")?.action == .run(["screen", "mbp"]))
        #expect(m.symbol == "person.crop.circle.badge.questionmark")
    }

    @Test func lockedOffersUnlock() {
        let able = Workhorse.sample(osVersion: "27.3", arch: "arm64")
        let m = menu(.locked, workhorse: able)
        #expect(titles(m)[1].hasPrefix("The disk is locked"))
        #expect(item(m, "Unlock disk…  (you type the Mac's password)")?.action == .tab(["unlock", "mbp"]))
        #expect(m.symbol == "lock.circle")
    }

    @Test func lockedOnAnOlderMacOffersNoUnlock() {
        let old = Workhorse.sample(osVersion: "15.6", arch: "arm64")
        let m = menu(.locked, workhorse: old)
        #expect(titles(m)[1].hasSuffix("Unlock it at the Mac."))
        #expect(!titles(m).contains { $0.hasPrefix("Unlock disk") })
        let intel = Workhorse.sample(osVersion: "27.3", arch: "x86_64")
        #expect(!titles(menu(.locked, workhorse: intel)).contains { $0.hasPrefix("Unlock disk") })
    }

    @Test func cantVerifyOffersOnlyTheHint() {
        let m = menu(.cantVerify)
        // The headline, the hint, the checklist, a separator, Add a Mac and Check now: no button of its own.
        #expect(titles(m).count == 6)
        #expect(titles(m)[1].hasPrefix("Something answers at its address with a different key."))
        #expect(m.symbol == "exclamationmark.triangle")
        #expect(m.items[1].action == .none)
        #expect(m.items[2].title == "Run the checklist…")
    }

    @Test func cantReachOffersOnlyTheHint() {
        let m = menu(.cantReach(.tailscaleOff))
        #expect(titles(m)[1] == "Tailscale is off on this Mac.")
        #expect(m.items[2].title == "Run the checklist…")
        #expect(m.symbol == "wifi.slash")
    }

    @Test func cantReachShowsWhenItWasLastSeen() {
        let seen = utcDate(2027, 1, 15, 14, 2)
        let w = Workhorse.sample(lastSeen: seen)
        let r = CheckResult.sample(.cantReach(.tailscaleOff), workhorse: w)
        let m = MenuModel.build([.checked(r)], now: formatNow, timeZone: formatZone)
        #expect(titles(m)[1] == "Last seen \(shortClock(seen)). Tailscale is off on this Mac.")
    }

    @Test func notSetUpOffersToFinish() {
        let m = menu(.notSetUp(.hostScriptMissing))
        #expect(titles(m)[1] == "Run: macmosh prepare mbp --fix")
        #expect(item(m, "Finish setting up…")?.action == .tab(["prepare", "mbp", "--fix", "--pause"]))
        #expect(m.symbol == "wrench.and.screwdriver")
    }

    @Test func notPairedOffersPair() {
        let m = menu(.notSetUp(.notPaired))
        #expect(item(m, "Pair…")?.action == .tab(["pair", "mbp"]))
        #expect(item(m, "Finish setting up…") == nil)
    }

    @Test func stillCheckingIsOneLine() {
        let m = MenuModel.build([.stillChecking(.sample(name: "MacBook Pro"))])
        #expect(titles(m)[0] == "MacBook Pro · Still checking…")
        #expect(m.items[0].indent == 0)
        #expect(m.items[0].action == .none)
        #expect(m.items[1].title == "Run the checklist…")
    }

    @Test func eachStateOffersItsButton() {
        let able = Workhorse.sample(osVersion: "27.3", arch: "arm64")
        let rows: [(WorkhorseState, Workhorse, String, MenuAction)] = [
            (.ready(signIns: true), .sample(), "Restart…", .tab(["restart", "mbp"])),
            (.ready(signIns: false), .sample(), "Fix…", .tab(["prepare", "mbp", "--restart-desk-server", "--pause"])),
            (.waitingForLogin, .sample(), "Log in…  (opens Screen Sharing)", .run(["screen", "mbp"])),
            (.locked, able, "Unlock disk…  (you type the Mac's password)", .tab(["unlock", "mbp"])),
            (.notSetUp(.deskServerDown), .sample(), "Finish setting up…", .tab(["prepare", "mbp", "--fix", "--pause"])),
            (.notSetUp(.notPaired), .sample(), "Pair…", .tab(["pair", "mbp"])),
            (.cantVerify, .sample(), "Run the checklist…", .tab(["prepare", "mbp", "--pause"])),
            (.cantReach(.nothingAnswers), .sample(), "Run the checklist…", .tab(["prepare", "mbp", "--pause"])),
        ]
        for (state, w, title, action) in rows {
            let m = menu(state, workhorse: w, status: .sampleWithDesk)
            #expect(item(m, title)?.action == action, "\(state)")
        }
    }

    // MARK: the whole menu

    @Test func noWorkhorsesOffersAddAMac() {
        let m = MenuModel.build([])
        #expect(titles(m) == ["No workhorses yet", "Add a Mac…"])
        #expect(m.items[1].action == .tab(["pair"]))
        #expect(m.symbol == "plus.circle")
    }

    @Test func eachWorkhorseGetsItsOwnBlockInOrder() {
        let m = MenuModel.build([
            .checked(.sampleReady(id: "a", name: "Alpha")),
            .stillChecking(.sample(id: "b", name: "Beta")),
        ])
        let heads = m.items.filter { $0.indent == 0 && !$0.isSeparator }.map(\.title)
        #expect(heads == ["Alpha · Ready", "Beta · Still checking…", "Add a Mac…", "Check now"])
        #expect(m.items.filter { $0.title == "Run the checklist…" }.count == 2)
        #expect(m.symbol == "checkmark.circle")
    }

    @Test func theMostUrgentStatePicksTheIcon() {
        let order: [WorkhorseState] = [
            .cantVerify, .locked, .waitingForLogin, .cantReach(.nothingAnswers), .notSetUp(.notPaired),
            .ready(signIns: false), .ready(signIns: true),
        ]
        for i in order.indices {
            // Whatever comes after state i is less urgent, whatever the order they are given in.
            let rest = Array(order[i...])
            #expect(MenuModel.mostUrgent(rest) == order[i])
            #expect(MenuModel.mostUrgent(rest.reversed()) == order[i])
        }
        #expect(MenuModel.mostUrgent([]) == nil)

        let expectedSymbols: [String] = [
            "exclamationmark.triangle", "lock.circle", "person.crop.circle.badge.questionmark", "wifi.slash",
            "wrench.and.screwdriver", "exclamationmark.circle", "checkmark.circle",
        ]
        #expect(order.map(MenuModel.symbol(for:)) == expectedSymbols)

        let mixed = MenuModel.build([.checked(.sampleReady()), .checked(.sample(.locked))])
        #expect(mixed.symbol == "lock.circle")
    }

    @Test func everySymbolExists() {
        var names = Set(everySampleMenu().map(\.symbol))
        names.insert(MenuModel.noWorkhorsesSymbol)
        names.insert(MenuModel.stillCheckingSymbol)
        #expect(names.count >= 8)
        for name in names {
            #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil, "\(name)")
        }
    }

    @Test func everyTabAndRunActionUsesOnlyPlainWords() {
        var seen = 0
        for menu in everySampleMenu() {
            for item in menu.items {
                switch item.action {
                case .tab(let args), .run(let args):
                    seen += 1
                    #expect(!args.isEmpty)
                    for word in args { #expect(PlainWords.isPlain(word), "\(word)") }
                case .refresh, .none:
                    break
                }
            }
        }
        #expect(seen > 20)
    }

    @Test func plainWordsAreLettersDigitsAndTheListedMarks() {
        #expect(PlainWords.isPlain("a1@%+=:,./_-Z"))
        #expect(!PlainWords.isPlain(""))
        for bad in ["a b", "a'b", "a;b", "a$b", "a|b", "a\nb", "é", "a\"b", "a\\b", "a(b"] {
            #expect(!PlainWords.isPlain(bad), "\(bad)")
        }
    }
}

/// "14:02", in the test's time zone.
private func shortClock(_ date: Date) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = formatZone
    f.dateFormat = "HH:mm"
    return f.string(from: date)
}
