import Foundation
import Testing
@testable import MacMoshKit

/// Every id in a tree, depth first.
private func allIDs(_ entries: [MenuEntry]) -> [String] {
    entries.flatMap { [$0.id] + allIDs($0.children) }
}

private func entry(_ entries: [MenuEntry], _ id: String) -> MenuEntry? {
    for e in entries {
        if e.id == id { return e }
        if let found = entry(e.children, id) { return found }
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

    @Test func theLinesAreTheFlattenedTree() {
        for menu in everySampleMenu() + moreSampleMenus() + [twoWithTheSameDesk()] {
            #expect(menu.items == MenuEntry.flatten(menu.entries))
        }
    }

    // MARK: the shape

    @Test func aWorkhorseIsOneEntryWithItsLinesUnderIt() {
        let m = MenuModel.build([.checked(.sampleReady(id: "mbp", name: "MacBook Pro"))])
        #expect(m.entries.map(\.id) == ["wh:mbp", "top:sep1", "top:add", "top:check"])
        let block = m.entries[0]
        #expect(block.title == "MacBook Pro · Ready")
        #expect(block.action == .none)
        #expect(block.children.map(\.id) == [
            "desk:mbp:website", "wh:mbp:newDesk", "wh:mbp:share", "wh:mbp:restart", "wh:mbp:lid",
            "wh:mbp:summary", "wh:mbp:home", "wh:mbp:checklist",
        ])
        #expect(m.entries[1].isSeparator)
        #expect(m.entries[2].title == "Add a Mac…" && m.entries[3].title == "Check now")
    }

    @Test func aDeskIsOneEntryThatOpensItWithItsActionsUnderIt() {
        let m = MenuModel.build([.checked(.sampleReady(id: "mbp"))])
        let desk = entry(m.entries, "desk:mbp:website")
        #expect(desk?.title == "website (2 windows: zsh, vim, open in 1 tab)")
        #expect(desk?.action == .tab(["connect", "mbp", "website"]))
        #expect(desk?.children.map(\.id) == ["desk:mbp:website:window", "desk:mbp:website:rename", "desk:mbp:website:remove"])
        #expect(desk?.children.allSatisfy(\.children.isEmpty) == true)
    }

    @Test func aClosedPermanentDeskHasOnlyRenameAndRemoveUnderIt() {
        let notes = entry(twoWithTheSameDesk().entries, "desk:workhorse:notes")
        #expect(notes?.title == "notes (closed)")
        #expect(notes?.children.map(\.id) == ["desk:workhorse:notes:rename", "desk:workhorse:notes:remove"])
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

    /// Every state at once, each workhorse with an id of its own. (The last case of `everySampleMenu()`
    /// gives all eight the id `mbp`, which the saved list never holds twice, so it is left out below.)
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
        let samples = Array(everySampleMenu().dropLast()) + moreSampleMenus()
        for menu in samples + [twoWithTheSameDesk(), everyStateWithItsOwnID()] {
            let ids = allIDs(menu.entries)
            #expect(Set(ids).count == ids.count, "\(ids)")
        }
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
