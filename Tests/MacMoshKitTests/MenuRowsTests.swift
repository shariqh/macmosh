import Foundation
import Testing
@testable import MacMoshKit

/// The rows the menu's view draws, one for one (issue #107): every decision the view makes is here.
@Suite struct MenuRowsTests {
    @Test func aReadyMenuIsTheHeadlineItsDesksNewDeskAndTheLastLines() {
        let m = MenuModel.build([.checked(.sampleReady(id: "mbp", name: "MacBook Pro"))])
        let rows = m.rows
        #expect(rows.map(\.id) == ["wh:mbp", "desk:mbp:website", "wh:mbp:newDesk", "top:sep1", "top:add", "top:check"])
        #expect(rows.map(\.label) == ["MacBook Pro · Ready", "   website (2 windows: zsh, vim, open in 1 tab)",
                                      "   New desk…", "", "Add a Mac…", "Check now"])
        guard case .submenu(let head, let none) = rows[0].kind,
              case .submenu(let desk, let open) = rows[1].kind else {
            Issue.record("the headline and the desk should open submenus"); return
        }
        #expect(none == nil)   // the headline's row runs nothing
        #expect(open == .tab(["connect", "mbp", "website"]))
        #expect(rows[1].title == "website (2 windows: zsh, vim, open in 1 tab)")
        #expect(rows[2].kind == .button(.tab(["desk", "new", "mbp"])))
        #expect(rows[3].kind == .separator)
        #expect(rows[5].kind == .button(.refresh))

        // Inside a submenu nothing is indented.
        // Changed on purpose for issue #124: the summary is one fact per line, each grey text.
        #expect(head.map(\.label) == ["Share screen", "Turn on lid-closed mode…", "Restart…", "",
                                      "Sign-ins working", "Awake on power", "Lid-closed mode off", "On power, 82%",
                                      "Home address reachable from here: yes", "", "Run the checklist…"])
        #expect(head.map(\.kind) == [
            .button(.run(["screen", "mbp"])), .button(.tab(["power", "mbp", "lid", "on"])), .button(.tab(["restart", "mbp"])),
            .separator, .text, .text, .text, .text, .text, .separator, .button(.tab(["prepare", "mbp", "--pause"])),
        ])
        #expect(desk.map(\.label) == ["Open website", "New window", "", "Rename website…", "Remove website…"])
        #expect(desk.first?.kind == .button(.tab(["connect", "mbp", "website"])))
    }

    /// The two tab actions of issue #120 are drawn as any other action: a line that does one is a button, and a
    /// row that opens a submenu carries one as its primary action. Nothing builds them yet.
    @Test func theTabsAndFocusActionsAreButtonsAndPrimaryActions() {
        let open = ["connect", "mbp", "website", "--window", "@1"]
        let focus = MenuAction.focus(label: "9f3a1c2e", orOpen: open)
        let tabs = MenuAction.tabs([open, ["connect", "mbp", "website", "--window", "@2"]])
        let menu = MenuLines(symbol: "checkmark.circle", entries: [
            MenuEntry(id: "desk:mbp:website", title: "website", action: focus,
                      submenu: [MenuEntry(id: "desk:mbp:website:open", title: "Open website in 2 tabs", action: tabs)]),
        ])
        #expect(menu.rows.map(\.kind) == [.submenu([MenuRow(id: "desk:mbp:website:open", label: "Open website in 2 tabs",
                                                           title: "Open website in 2 tabs", kind: .button(tabs))],
                                                   primaryAction: focus)])
        #expect(menu.items.map(\.action) == [focus, tabs])
    }

    /// A menu with no submenu is drawn as before: each line at its indent, three spaces a level; a line
    /// with no action is text, a separator a divider, anything else a button.
    @Test func aMenuWithNoSubmenuIsDrawnLineForLineAsBefore() {
        let flat = (everySampleMenu() + moreSampleMenus()).filter { !$0.hasSubmenu }
        #expect(flat.count >= 9)
        for menu in flat {
            let rows = menu.rows
            #expect(rows.map(\.label) == menu.items.map { String(repeating: "   ", count: $0.indent) + $0.title })
            #expect(rows.map(\.title) == menu.items.map(\.title))
            for (row, item) in zip(rows, menu.items) {
                let want: MenuRow.Kind = item.isSeparator ? .separator
                    : item.action == .none ? .text : .button(item.action)
                #expect(row.kind == want, "\(item.title)")
            }
        }
    }

    @Test func theRowsCarryTheTreesIDs() {
        for menu in everySampleMenu() + moreSampleMenus() {
            func ids(_ rows: [MenuRow]) -> [String] {
                rows.flatMap { row -> [String] in
                    if case .submenu(let lines, _) = row.kind { return [row.id] + ids(lines) }
                    return [row.id]
                }
            }
            let rowIDs = ids(menu.rows)
            #expect(Set(rowIDs) == Set(allIDs(menu.entries)))
            #expect(Set(rowIDs).count == rowIDs.count)
        }
    }

    /// Sign-ins off: the hint is text and Fix… a button, both at the top level under the headline.
    @Test func withSignInsOffTheHintAndFixAreTopLevelRows() {
        let m = MenuModel.build([.checked(.sample(.ready(signIns: false), status: .sampleWithDesk))])
        let rows = m.rows
        #expect(rows[1].label == "   Tools that keep logins in the keychain look signed out here.")
        #expect(rows[1].kind == .text)
        #expect(rows[2].label == "   Fix…")
        #expect(rows[2].kind == .button(.tab(["prepare", "mbp", "--restart-desk-server", "--pause"])))
    }
}
