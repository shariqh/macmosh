import Foundation
import Testing
@testable import MacMoshKit

/// Every id in a tree, depth first: an entry, its submenu, then the lines under it.
func allIDs(_ entries: [MenuEntry]) -> [String] {
    entries.flatMap { [$0.id] + allIDs($0.submenu) + allIDs($0.children) }
}

/// Every entry in a tree, depth first.
func allEntries(_ entries: [MenuEntry]) -> [MenuEntry] {
    entries.flatMap { [$0] + allEntries($0.submenu) + allEntries($0.children) }
}

func entry(_ entries: [MenuEntry], _ id: String) -> MenuEntry? {
    for e in entries {
        if e.id == id { return e }
        if let found = entry(e.submenu, id) ?? entry(e.children, id) { return found }
    }
    return nil
}

/// Two workhorses that each have a desk called `website`, a closed permanent desk, one still being
/// checked and one waiting for its desk server.
private func twoWithTheSameDesk() -> MenuLines {
    var status = HostStatus.sampleWithDesk
    status.definitions = [
        .init(name: DeskName("notes")!, reopen: false, keep: false, folder: "/Users/alex/notes", command: "",
              permanent: true),
    ]
    return MenuModel.build([
        .checked(.sample(.ready(signIns: true), workhorse: .sample(id: "workhorse", name: "Workhorse"), status: status,
                         homeReachable: true)),
        .checked(.sampleReady(id: "daily-mac", name: "Daily Mac")),
        .stillChecking(.sample(id: "attic", name: "Attic")),
        .checked(.sample(.notSetUp(.deskServerDown), workhorse: .sample(id: "spare", name: "Spare"), status: .sampleReady)),
    ], waitingForDeskServer: ["spare"])
}

@Suite struct MenuTreeTests {
    // MARK: flattening

    @Test func flatteningPutsEachEntryAtItsDepthAndItsChildrenOneDeeper() {
        let tree = [
            MenuEntry(id: "a", title: "A", action: .refresh, children: [
                MenuEntry(id: "a:b", title: "B", children: [
                    MenuEntry(id: "a:b:c", title: "C", action: .tab(["x"])),
                ]),
                MenuEntry(id: "a:d", title: "D"),
            ]),
            .separator(id: "top:sep1"),
            MenuEntry(id: "e", title: "E"),
        ]
        #expect(MenuEntry.flatten(tree) == [
            MenuItem(title: "A", action: .refresh, indent: 0, isSeparator: false),
            MenuItem(title: "B", action: .none, indent: 1, isSeparator: false),
            MenuItem(title: "C", action: .tab(["x"]), indent: 2, isSeparator: false),
            MenuItem(title: "D", action: .none, indent: 1, isSeparator: false),
            MenuItem(title: "", action: .none, indent: 0, isSeparator: true),
            MenuItem(title: "E", action: .none, indent: 0, isSeparator: false),
        ])
    }

    /// A line that opens a submenu is one line, its submenu's lines come right after it one level in and
    /// marked as inside a submenu, then the lines drawn under it in the same menu.
    @Test func flatteningASubmenuMarksTheLineThatOpensItAndTheLinesInIt() {
        let tree = [
            MenuEntry(id: "h", title: "Head", submenu: [
                MenuEntry(id: "h:a", title: "A", action: .refresh),
                .separator(id: "h:sep1"),
                MenuEntry(id: "h:t", title: "T"),
            ], children: [
                MenuEntry(id: "d", title: "Desk", action: .tab(["x"]), submenu: [
                    MenuEntry(id: "d:o", title: "Open", action: .tab(["x"])),
                ]),
                MenuEntry(id: "n", title: "New", action: .tab(["n"])),
            ]),
        ]
        #expect(MenuEntry.flatten(tree) == [
            MenuItem(title: "Head", action: .none, indent: 0, isSeparator: false, opensSubmenu: true),
            MenuItem(title: "A", action: .refresh, indent: 1, isSeparator: false, inSubmenu: true),
            MenuItem(title: "", action: .none, indent: 1, isSeparator: true, inSubmenu: true),
            MenuItem(title: "T", action: .none, indent: 1, isSeparator: false, inSubmenu: true),
            MenuItem(title: "Desk", action: .tab(["x"]), indent: 1, isSeparator: false, opensSubmenu: true),
            MenuItem(title: "Open", action: .tab(["x"]), indent: 2, isSeparator: false, inSubmenu: true),
            MenuItem(title: "New", action: .tab(["n"]), indent: 1, isSeparator: false),
        ])
    }

    @Test func aMenuSaysWhetherAnyLineOpensASubmenu() {
        let flat = MenuLines(symbol: "x", entries: [
            MenuEntry(id: "a", title: "A", children: [MenuEntry(id: "b", title: "B")]),
        ])
        #expect(!flat.hasSubmenu)
        let deep = MenuLines(symbol: "x", entries: [
            MenuEntry(id: "a", title: "A", children: [
                MenuEntry(id: "b", title: "B", submenu: [MenuEntry(id: "c", title: "C")]),
            ]),
        ])
        #expect(deep.hasSubmenu)
        #expect(MenuEntry(id: "s", title: "S", submenu: [MenuEntry(id: "c", title: "C")]).opensSubmenu)
        #expect(!MenuEntry(id: "s", title: "S", children: [MenuEntry(id: "c", title: "C")]).opensSubmenu)
    }

    @Test func idsInsideASubmenuAreNumberedToo() {
        let lines = MenuLines(symbol: "x", entries: [
            MenuEntry(id: "a", title: "A", submenu: [MenuEntry(id: "a", title: "B")], children: [MenuEntry(id: "a", title: "C")]),
        ])
        #expect(allIDs(lines.entries) == ["a", "a#2", "a#3"])
    }

    @Test func theLinesAreTheFlattenedTree() {
        for menu in everySampleMenu() + moreSampleMenus() + [twoWithTheSameDesk()] {
            #expect(menu.items == MenuEntry.flatten(menu.entries))
        }
    }

    // MARK: the shape

    /// Changed on purpose for issue #107: the rare lines are in the headline's submenu; the desks and
    /// New desk… are under it at the top level.
    @Test func aReadyWorkhorseIsOneEntryWithItsSubmenuAndItsDesksUnderIt() {
        let m = MenuModel.build([.checked(.sampleReady(id: "mbp", name: "MacBook Pro"))])
        #expect(m.entries.map(\.id) == ["wh:mbp", "top:sep1", "top:add", "top:check"])
        let block = m.entries[0]
        #expect(block.title == "MacBook Pro · Ready")
        #expect(block.action == .none)   // the headline's row has no primary action
        #expect(block.submenu.map(\.id) == [
            "wh:mbp:share", "wh:mbp:lid", "wh:mbp:restart", "wh:mbp:sep1", "wh:mbp:summary:1", "wh:mbp:summary:2",
            "wh:mbp:summary:3", "wh:mbp:summary:4", "wh:mbp:home", "wh:mbp:sep2", "wh:mbp:checklist",
        ])
        // Changed on purpose for issue #124: the summary is drawn one fact per line, as grey text.
        #expect(block.submenu.filter { $0.id.contains(":summary:") }.map(\.title)
                == ["Sign-ins working", "Awake on power", "Lid-closed mode off", "On power, 82%"])
        #expect(block.submenu.filter { $0.id.contains(":summary:") }.allSatisfy { $0.action == .none && $0.submenu.isEmpty })
        #expect(block.children.map(\.id) == ["desk:mbp:website", "wh:mbp:newDesk"])
        #expect(m.entries[1].isSeparator)
        #expect(m.entries[2].title == "Add a Mac…" && m.entries[3].title == "Check now")
    }

    /// Changed on purpose for issue #107: a desk's actions are in its submenu, which starts with Open.
    @Test func aDeskIsOneRowThatOpensItWithItsActionsInItsSubmenu() {
        let m = MenuModel.build([.checked(.sampleReady(id: "mbp"))])
        let desk = entry(m.entries, "desk:mbp:website")
        #expect(desk?.title == "website (2 windows: zsh, vim, open in 1 tab)")
        #expect(desk?.action == .tab(["connect", "mbp", "website"]))
        #expect(desk?.submenu.map(\.id) == ["desk:mbp:website:open", "desk:mbp:website:window",
                                            "desk:mbp:website:sep1", "desk:mbp:website:rename",
                                            "desk:mbp:website:remove"])
        #expect(desk?.submenu.map(\.title) == ["Open website", "New window", "", "Rename website…", "Remove website…"])
        #expect(desk?.submenu.first?.action == desk?.action)
        #expect(desk?.submenu.allSatisfy { $0.submenu.isEmpty && $0.children.isEmpty } == true)
        #expect(desk?.children.isEmpty == true)
    }

    /// Changed on purpose for issue #107: Open is in the submenu too, then a separator.
    @Test func aClosedPermanentDeskHasOpenRenameAndRemoveInItsSubmenu() {
        let notes = entry(twoWithTheSameDesk().entries, "desk:workhorse:notes")
        #expect(notes?.title == "notes (closed)")
        #expect(notes?.action == .tab(["connect", "workhorse", "notes"]))
        #expect(notes?.submenu.map(\.id) == ["desk:workhorse:notes:open", "desk:workhorse:notes:sep1",
                                             "desk:workhorse:notes:rename", "desk:workhorse:notes:remove"])
        #expect(notes?.submenu.first?.title == "Open notes")
    }

    // MARK: the shape with submenus (issue #107)

    /// The owner's example: a laptop workhorse with six desks, five open and one closed.
    private func sixDesks(signIns: Bool = true) -> MenuLines {
        var status = HostStatus.sampleWithDesk
        func desk(_ name: String, _ windows: [String], tabs: Int) -> HostStatus.Desk {
            .init(name: DeskName(name)!, windows: windows.enumerated().map { .init(index: $0.offset, name: $0.element) },
                  windowCount: windows.count, attached: tabs)
        }
        status.desks = [
            desk("website", ["claude", "zsh", "vim"], tabs: 1), desk("api", ["server", "tests"], tabs: 0),
            desk("notes", ["zsh"], tabs: 1), desk("blog", ["zsh"], tabs: 0), desk("shop", ["web", "db"], tabs: 1),
        ]
        status.definitions = [
            .init(name: DeskName("garden")!, reopen: false, keep: false, folder: "/Users/alex/garden", command: "",
                  permanent: true),
        ]
        return MenuModel.build([.checked(.sample(.ready(signIns: signIns), workhorse: .sample(id: "workhorse", name: "workhorse"),
                                                 status: status, homeReachable: true))])
    }

    /// The rows drawn at the top level: each top-level entry and the lines under it, not what a submenu holds.
    private func topLevel(_ entries: [MenuEntry]) -> [MenuEntry] {
        entries.flatMap { [$0] + topLevel($0.children) }
    }

    @Test func withSixDesksTheTopLevelIsTheHeadlineTheDesksAndNewDesk() {
        let top = topLevel(sixDesks().entries)
        #expect(top.map(\.title) == [
            "workhorse · Ready",
            "website (3 windows: claude, zsh, vim, open in 1 tab)", "api (2 windows: server, tests)",
            "notes (1 window: zsh, open in 1 tab)", "blog (1 window: zsh)", "shop (2 windows: web, db, open in 1 tab)",
            "garden (closed)", "New desk…", "", "Add a Mac…", "Check now",
        ])
        #expect(top.count == 11)   // 35 lines before
        let opens = top.map(\.opensSubmenu)
        #expect(opens == Array(repeating: true, count: 7) + Array(repeating: false, count: 4))
    }

    @Test func withSignInsOffTheHintAndFixAreAtTheTopAboveTheDesks() {
        let top = topLevel(sixDesks(signIns: false).entries)
        #expect(Array(top.prefix(4).map(\.title)) == [
            "workhorse · Ready, sign-ins off", "Tools that keep logins in the keychain look signed out here.", "Fix…",
            "website (3 windows: claude, zsh, vim, open in 1 tab)",
        ])
        #expect(top.count == 13)
        #expect(top[2].action == .tab(["prepare", "workhorse", "--restart-desk-server", "--pause"]))
        // A problem is never inside a submenu.
        let headline = sixDesks(signIns: false).entries[0]
        #expect(!headline.submenu.contains { $0.title == "Fix…" || $0.id.hasSuffix(":hint") })
    }

    /// Every case: no submenu inside a submenu, and nothing drawn under a line inside a submenu.
    @Test func submenusGoOneLevelDeepOnly() {
        func check(_ entries: [MenuEntry], inSubmenu: Bool) {
            for e in entries {
                if inSubmenu { #expect(e.submenu.isEmpty && e.children.isEmpty, "\(e.id)") }
                check(e.submenu, inSubmenu: true)
                check(e.children, inSubmenu: inSubmenu)
            }
        }
        for menu in everySampleMenu() + moreSampleMenus() + [twoWithTheSameDesk(), sixDesks(), sixDesks(signIns: false)] {
            check(menu.entries, inSubmenu: false)
        }
    }

    /// A desk's row does what its first line, Open <desk>, does. The headline's row does nothing of its own.
    @Test func aRowWithAPrimaryActionDoesWhatItsOpenLineDoes() {
        var seen = 0
        for menu in everySampleMenu() + moreSampleMenus() + [twoWithTheSameDesk(), sixDesks()] {
            for e in allEntries(menu.entries) where e.opensSubmenu {
                if e.id.hasPrefix("wh:") {
                    #expect(e.action == .none, "\(e.id)")
                } else {
                    seen += 1
                    guard case .tab(let args) = e.action, args.count == 3, args[0] == "connect" else {
                        Issue.record("\(e.id) has \(e.action)"); continue
                    }
                    #expect(e.submenu.first?.action == e.action, "\(e.id)")
                    #expect(e.submenu.first?.title == "Open \(args[2])", "\(e.id)")
                }
            }
        }
        #expect(seen > 10)
    }

    /// Every state that is not Ready, "Still checking…", "Waiting for the desk server" and "No
    /// workhorses yet" are drawn flat, as before: a menu without a submenu updates at once.
    @Test func onlyAReadyWorkhorseOpensASubmenu() {
        let menus = everySampleMenu() + moreSampleMenus()
        for (i, menu) in menus.enumerated() {
            let ready = menu.entries.contains { $0.title.contains(" · Ready") }
            #expect(menu.hasSubmenu == ready, "menu \(i)")
        }
        #expect(!MenuModel.build([]).hasSubmenu)
    }

    /// No word on screen says view, session, pane or tmux.
    @Test func noTitleNamesTheMachinery() {
        for menu in everySampleMenu() + moreSampleMenus() + [twoWithTheSameDesk(), sixDesks(), sixDesks(signIns: false)] {
            for e in allEntries(menu.entries) {
                let words = e.title.lowercased()
                for bad in ["view", "session", "pane", "tmux"] { #expect(!words.contains(bad), "\(e.title)") }
            }
        }
    }

    /// Every argument of every action in the tree, a row's primary action included, is a plain word.
    @Test func everyActionInTheTreeUsesOnlyPlainWords() {
        var seen = 0
        for menu in everySampleMenu() + moreSampleMenus() + [twoWithTheSameDesk(), sixDesks()] {
            for action in allActions(menu.entries) {
                switch action {
                case .tab(let args), .run(let args):
                    seen += 1
                    #expect(!args.isEmpty)
                    for word in args { #expect(PlainWords.isPlain(word), "\(word)") }
                case .tabs(let list):
                    seen += 1
                    #expect(!list.isEmpty)
                    for args in list {
                        #expect(!args.isEmpty)
                        for word in args { #expect(PlainWords.isPlain(word), "\(word)") }
                    }
                case .focus(let label, let orOpen):
                    seen += 1
                    #expect(!orOpen.isEmpty)
                    #expect(PlainWords.isPlain(label), "\(label)")
                    for word in orOpen { #expect(PlainWords.isPlain(word), "\(word)") }
                case .refresh, .none:
                    break
                }
                for word in action.words { #expect(PlainWords.isPlain(word), "\(word)") }
            }
        }
        #expect(seen > 20)
    }

    @Test func theHintAndTheStatesButtonAreUnderTheHeadline() {
        let m = MenuModel.build([.checked(.sample(.waitingForLogin))])
        #expect(m.entries[0].children.map(\.id) == ["wh:mbp:hint", "wh:mbp:login", "wh:mbp:checklist"])
        let wait = MenuModel.build([.checked(.sample(.notSetUp(.deskServerDown), status: .sampleReady))],
                                   waitingForDeskServer: ["mbp"])
        #expect(wait.entries[0].children.map(\.id) == ["wh:mbp:hint", "wh:mbp:checklist"])
        let still = MenuModel.build([.stillChecking(.sample())])
        #expect(still.entries[0].id == "wh:mbp")
        #expect(still.entries[0].children.map(\.id) == ["wh:mbp:checklist"])
    }

    @Test func separatorsAreTopLevelAndNumberedInOrder() {
        let m = twoWithTheSameDesk()
        #expect(m.entries.filter(\.isSeparator).map(\.id) == ["top:sep1", "top:sep2", "top:sep3", "top:sep4"])
        #expect(m.entries.filter { !$0.isSeparator }.map(\.id)
                == ["wh:workhorse", "wh:daily-mac", "wh:attic", "wh:spare", "top:add", "top:check"])
        #expect(m.entries.allSatisfy { e in e.children.allSatisfy { !$0.isSeparator } })
    }

    @Test func noWorkhorsesIsTwoTopLevelLines() {
        #expect(MenuModel.build([]).entries.map(\.id) == ["top:none", "top:add"])
    }

    // MARK: the ids

    /// Every state at once, each workhorse with an id of its own.
    private func everyStateWithItsOwnID() -> MenuLines {
        let able = Workhorse.sample(id: "w3", osVersion: "27.3", arch: "arm64")
        return MenuModel.build([
            .checked(.sampleReady(id: "w0")),
            .checked(.sample(.ready(signIns: false), workhorse: .sample(id: "w1"), status: .sampleWithDesk, homeReachable: false)),
            .checked(.sample(.waitingForLogin, workhorse: .sample(id: "w2"))),
            .checked(.sample(.locked, workhorse: able)),
            .checked(.sample(.cantVerify, workhorse: .sample(id: "w4"))),
            .checked(.sample(.cantReach(.tailscaleOff), workhorse: .sample(id: "w5"))),
            .checked(.sample(.notSetUp(.notPaired), workhorse: .sample(id: "w6"))),
            .checked(.sample(.notSetUp(.hostScriptMissing), workhorse: .sample(id: "w7"))),
            .stillChecking(.sample(id: "w8")),
        ])
    }

    @Test func idsAreUniqueAcrossTheWholeTree() {
        // The last case of `everySampleMenu()` gives all eight workhorses the id `mbp`; it is in too.
        for menu in everySampleMenu() + moreSampleMenus() + [twoWithTheSameDesk(), everyStateWithItsOwnID()] {
            let ids = allIDs(menu.entries)
            #expect(Set(ids).count == ids.count, "\(ids)")
        }
    }

    // MARK: ids unique for any input (issue #107)

    /// A saved list edited by hand can hold one workhorse id twice; nothing checks that when it is loaded.
    @Test func aRepeatedWorkhorseIDStillGivesUniqueIDs() {
        let build = {
            MenuModel.build([
                .checked(.sampleReady(id: "mbp")),
                .checked(.sampleReady(id: "mbp")),
                .checked(.sample(.locked, workhorse: .sample(id: "mbp"))),
                .stillChecking(.sample(id: "mbp")),
            ])
        }
        let ids = allIDs(build().entries)
        #expect(Set(ids).count == ids.count, "\(ids)")
        #expect(ids == allIDs(build().entries))
        // The first of each keeps its id; a repeat gets a number.
        #expect(ids.first == "wh:mbp")
        #expect(ids.contains("wh:mbp#2") && ids.contains("wh:mbp#3") && ids.contains("wh:mbp#4"))
    }

    /// A report that lists one desk twice.
    @Test func aDeskListedTwiceStillGivesUniqueIDs() {
        var status = HostStatus.sampleWithDesk
        status.desks += status.desks
        let build = {
            MenuModel.build([.checked(.sample(.ready(signIns: true), status: status, homeReachable: true))])
        }
        let ids = allIDs(build().entries)
        #expect(Set(ids).count == ids.count, "\(ids)")
        #expect(ids == allIDs(build().entries))
        #expect(ids.contains("desk:mbp:website") && ids.contains("desk:mbp:website#2"))
    }

    /// An id made with a number can't meet one that already looks like that.
    @Test func aNumberedIDNeverMeetsANaturalOne() {
        let lines = MenuLines(symbol: "x", entries: [
            MenuEntry(id: "a", title: "A"), MenuEntry(id: "a", title: "A"), MenuEntry(id: "a#2", title: "B"),
            MenuEntry(id: "c", title: "C", children: [MenuEntry(id: "a", title: "D")]),
        ])
        let ids = allIDs(lines.entries)
        #expect(ids == ["a", "a#2", "a#2#2", "c", "a#3"])
    }

    @Test func twoWorkhorsesWithADeskOfTheSameNameGiveTwoIDs() {
        let ids = allIDs(twoWithTheSameDesk().entries)
        for id in ["desk:workhorse:website", "desk:daily-mac:website",
                   "desk:workhorse:website:rename", "desk:daily-mac:website:rename", "wh:spare:hint"] {
            #expect(ids.contains(id), "\(id)")
        }
        #expect(!ids.contains("wh:workhorse:hint"))   // Ready with sign-ins working has no hint
        #expect(Set(ids).count == ids.count)
    }

    @Test func idsAreTheSameAcrossTwoBuildsFromTheSameInput() {
        #expect(allIDs(twoWithTheSameDesk().entries) == allIDs(twoWithTheSameDesk().entries))
        for (a, b) in zip(everySampleMenu() + moreSampleMenus(), everySampleMenu() + moreSampleMenus()) {
            #expect(allIDs(a.entries) == allIDs(b.entries))
            #expect(a == b)
        }
    }
}
