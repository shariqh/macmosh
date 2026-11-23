import AppKit
import Foundation
import Testing
@testable import MacMoshKit

private func titles(_ menu: MenuLines) -> [String] { menu.items.map(\.title) }

private func item(_ menu: MenuLines, _ title: String) -> MenuItem? { menu.items.first { $0.title == title } }

private func menu(_ state: WorkhorseState, workhorse: Workhorse = .sample(), status: HostStatus? = nil,
                  homeReachable: Bool? = nil) -> MenuLines {
    MenuModel.build([.checked(.sample(state, workhorse: workhorse, status: status, homeReachable: homeReachable))])
}

@Suite struct MenuModelTests {
    @Test func theReadyMenuMatchesTheDesign() {
        let menu = MenuModel.build([.checked(.sampleReady(id: "mbp", name: "MacBook Pro"))])
        let expected: [String] = [
            "MacBook Pro · Ready", "website (2 windows: zsh, vim, open in 1 tab)", "New window in website",
            "Rename website…", "Remove website…",
            "New desk…", "Share screen", "Restart…", "Turn on lid-closed mode…",
            "Sign-ins working · Awake on power · Lid-closed mode off · On power, 82%",
            "Home address reachable from here: yes",
        ]
        #expect(Array(titles(menu).prefix(expected.count)) == expected)
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

    // MARK: the lid-closed switch

    private func lidMenu(lid: Int?, laptop: Bool = true) -> MenuLines {
        var status = HostStatus.sampleWithDesk
        status.power.disableSleep = lid
        if !laptop { status.battery = .init(present: false, onAC: nil, percent: nil) }
        return MenuModel.build([.checked(.sample(.ready(signIns: true), workhorse: .sample(id: "mbp"), status: status))])
    }

    @Test func aLaptopWithTheLidSettingOffOffersToTurnItOn() {
        for lid in [0, nil] as [Int?] {
            let m = lidMenu(lid: lid)
            #expect(item(m, "Turn on lid-closed mode…")?.action == .tab(["power", "mbp", "lid", "on"]))
            #expect(item(m, "Turn on lid-closed mode…")?.indent == 1)
            #expect(item(m, "Turn off lid-closed mode…") == nil)
        }
    }

    @Test func aLaptopWithTheLidSettingOnOffersToTurnItOff() {
        let m = lidMenu(lid: 1)
        #expect(item(m, "Turn off lid-closed mode…")?.action == .tab(["power", "mbp", "lid", "off"]))
        #expect(item(m, "Turn on lid-closed mode…") == nil)
    }

    @Test func theLidItemComesRightAfterRestart() {
        let t = titles(lidMenu(lid: 1))
        let restart = t.firstIndex(of: "Restart…")
        #expect(restart != nil)
        #expect(restart.map { t[$0 + 1] } == "Turn off lid-closed mode…")
    }

    @Test func aMacWithNoBatteryHasNoLidItem() {
        for lid in [0, 1, nil] as [Int?] {
            let m = lidMenu(lid: lid, laptop: false)
            #expect(item(m, "Turn on lid-closed mode…") == nil)
            #expect(item(m, "Turn off lid-closed mode…") == nil)
            #expect(!titles(m).contains { $0.contains("Lid-closed") })
        }
    }

    @Test func noLidItemWhenTheWorkhorseIsNotReady() {
        let m = menu(.waitingForLogin, status: .sampleWithDesk)
        #expect(!titles(m).contains { $0.contains("lid-closed mode") })
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

    @Test func aKeptDeskSaysSo() {
        var status = HostStatus.sampleWithDesk
        status.definitions = [
            .init(name: DeskName("website")!, reopen: true, keep: true, folder: "/Users/alex/site", command: "npm run dev"),
            .init(name: DeskName("notes")!, reopen: false, keep: false, folder: "/Users/alex/notes", command: ""),
        ]
        status.desks.append(
            .init(name: DeskName("notes")!, windows: [.init(index: 0, name: "zsh")], windowCount: 1, attached: 0))
        let m = menu(.ready(signIns: true), status: status)
        #expect(item(m, "website (2 windows: zsh, vim, kept running, open in 1 tab)") != nil)
        #expect(item(m, "notes (1 window: zsh)") != nil)
    }

    @Test func aClosedPermanentDeskHasALineThatOpensIt() {
        var status = HostStatus.sampleWithDesk
        status.definitions = [
            .init(name: DeskName("notes")!, reopen: false, keep: false, folder: "/Users/alex/notes", command: "",
                  permanent: true),
        ]
        let m = menu(.ready(signIns: true), status: status)
        let closed = item(m, "notes (closed)")
        #expect(closed?.action == .tab(["connect", "mbp", "notes"]))
        #expect(closed?.indent == 1)
        // After the open desks and before New desk…, with no New window line: there is no desk to add one to.
        let at = titles(m).firstIndex(of: "notes (closed)")
        #expect(at != nil && titles(m)[at! + 1] == "Rename notes…")
        #expect(at != nil && titles(m)[at! - 1] == "Remove website…")
        #expect(!titles(m).contains("New window in notes"))
    }

    // MARK: rename and remove under each desk

    @Test func anOpenDeskHasARenameLineAfterItsNewWindowLine() {
        let m = MenuModel.build([.checked(.sampleReady(id: "mbp"))])
        let at = titles(m).firstIndex(of: "New window in website")
        #expect(at.map { titles(m)[$0 + 1] } == "Rename website…")
        let rename = item(m, "Rename website…")
        #expect(rename?.action == .tab(["desk", "rename", "mbp", "website"]))
        #expect(rename?.indent == 2)
    }

    @Test func anOpenDeskHasARemoveLineAfterItsRenameLine() {
        let m = MenuModel.build([.checked(.sampleReady(id: "mbp"))])
        let at = titles(m).firstIndex(of: "Rename website…")
        #expect(at.map { titles(m)[$0 + 1] } == "Remove website…")
        #expect(at.map { titles(m)[$0 + 2] } == "New desk…")
        let remove = item(m, "Remove website…")
        #expect(remove?.action == .tab(["desk", "remove", "mbp", "website", "--ask"]))
        #expect(remove?.indent == 2)
    }

    /// The order the design draws: each desk, then its own lines, then New desk….
    @Test func theLinesUnderEachDeskComeInTheDesignsOrder() {
        var status = HostStatus.sampleWithDesk
        status.definitions = [
            .init(name: DeskName("notes")!, reopen: false, keep: false, folder: "/Users/alex/notes", command: "",
                  permanent: true),
        ]
        let m = menu(.ready(signIns: true), workhorse: .sample(id: "mbp"), status: status)
        let from = titles(m).firstIndex { $0.hasPrefix("website (") }
        let lines = from.map { Array(titles(m)[$0..<($0 + 7)]) }
        #expect(lines == [
            "website (2 windows: zsh, vim, open in 1 tab)", "New window in website", "Rename website…", "Remove website…",
            "notes (closed)", "Rename notes…", "Remove notes…",
        ])
        #expect(from.map { titles(m)[$0 + 7] } == "New desk…")
        #expect(from.map { m.items[$0..<($0 + 7)].map(\.indent) } == [1, 2, 2, 2, 1, 2, 2])
        #expect(item(m, "Remove notes…")?.action == .tab(["desk", "remove", "mbp", "notes", "--ask"]))
    }

    @Test func aClosedPermanentDeskHasARenameLine() {
        var status = HostStatus.sampleWithDesk
        status.definitions = [
            .init(name: DeskName("notes")!, reopen: false, keep: false, folder: "/Users/alex/notes", command: "",
                  permanent: true),
        ]
        let m = menu(.ready(signIns: true), workhorse: .sample(id: "mbp"), status: status)
        let at = titles(m).firstIndex(of: "notes (closed)")
        #expect(at.map { titles(m)[$0 + 1] } == "Rename notes…")
        #expect(item(m, "Rename notes…")?.action == .tab(["desk", "rename", "mbp", "notes"]))
        #expect(item(m, "Rename notes…")?.indent == 2)
    }

    @Test func anOpenPermanentDeskSaysSo() {
        var status = HostStatus.sampleWithDesk
        status.definitions = [
            .init(name: DeskName("website")!, reopen: true, keep: true, folder: "/Users/alex/site",
                  command: "npm run dev", permanent: true),
        ]
        let m = menu(.ready(signIns: true), status: status)
        #expect(item(m, "website (2 windows: zsh, vim, kept running, permanent, open in 1 tab)") != nil)
        #expect(!titles(m).contains("website (closed)"))
    }

    @Test func aDeskThatIsNotPermanentAndHasNoSessionIsNotShown() {
        // A leftover line: the desk's last shell exited, or it ended with the server and won't come back.
        var status = HostStatus.sampleWithDesk
        status.definitions = [
            .init(name: DeskName("scratch")!, reopen: false, keep: false, folder: "/Users/alex/x", command: ""),
            .init(name: DeskName("again")!, reopen: true, keep: false, folder: "/Users/alex/y", command: ""),
        ]
        let m = menu(.ready(signIns: true), status: status)
        #expect(!titles(m).contains { $0.hasPrefix("scratch") || $0.hasPrefix("again") })
        #expect(titles(m) == titles(menu(.ready(signIns: true), status: .sampleWithDesk)))
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

    // MARK: the wait after a login (issue #88)

    @Test func aWorkhorseWaitingForItsDeskServerShowsNoFix() {
        let r = CheckResult.sample(.notSetUp(.deskServerDown), status: .sampleReady)
        let m = MenuModel.build([.checked(r)], waitingForDeskServer: ["mbp"])
        #expect(titles(m) == ["MacBook Pro · Waiting for the desk server", MenuModel.waitingForDeskServerHint,
                              "Run the checklist…", "", "Add a Mac…", "Check now"])
        #expect(m.items[0].indent == 0)
        #expect(m.items[0].action == .none)
        #expect(item(m, "Finish setting up…") == nil)
        let actions = m.items.map(\.action).filter { if case .tab = $0 { return true }; if case .run = $0 { return true }; return false }
        #expect(actions == [.tab(["prepare", "mbp", "--pause"]), .tab(["pair"])])
        #expect(m.symbol == "ellipsis.circle")
    }

    @Test func theHintIsTheTwoTrueSentences() {
        #expect(MenuModel.waitingForDeskServerHint == "Someone has logged in and the desk server isn't running yet. MacMosh's login agent starts it after a login; if it still isn't running in a minute, this menu says so.")
    }

    @Test func theWaitOnlyChangesDeskServerDown() {
        let states: [WorkhorseState] = [.ready(signIns: true), .notSetUp(.notPaired), .waitingForLogin]
        for state in states {
            let r = CheckResult.sample(state, status: .sampleWithDesk, homeReachable: true)
            #expect(MenuModel.build([.checked(r)], waitingForDeskServer: ["mbp"]) == MenuModel.build([.checked(r)]), "\(state)")
        }
    }

    @Test func aWaitingWorkhorseDoesNotPickTheIcon() {
        let a = CheckResult.sampleReady(id: "a", name: "A")
        let b = CheckResult.sample(.notSetUp(.deskServerDown), workhorse: .sample(id: "b", name: "B"), status: .sampleReady)
        let m = MenuModel.build([.checked(a), .checked(b)], waitingForDeskServer: ["b"])
        #expect(m.symbol == "checkmark.circle")
        let t = titles(m)
        let ready = t.firstIndex(of: "A · Ready")
        let waiting = t.firstIndex(of: "B · Waiting for the desk server")
        #expect(ready != nil && waiting != nil && ready! < waiting!)
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
