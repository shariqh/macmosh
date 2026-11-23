import MacMoshKit
import SwiftUI

/// The menu: the notice line, the rows `MenuLines.rows` gives, and Quit. It observes only
/// `MenuOnScreen`, which changes when `HoldStill` lets a different menu through (issue #107). Every
/// choice about a row is made in `MenuRow`, where it is tested; this only draws it.
struct MenuContent: View {
    @ObservedObject var screen: MenuOnScreen
    let actions: MenuActionRunner

    var body: some View {
        Group {
            // What the last action said, until the next one.
            if let notice = screen.shown.notice {
                Text(verbatim: notice)
                Divider()
            }
            MenuRows(rows: screen.shown.menu.rows, run: run)
            Divider()
            Button("Quit MacMosh") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        // No `onAppear` here: macOS runs it once, when the app starts, not each time the menu
        // opens (seen on the first run, Task 20). The label in `MacMoshApp` hears the menu open.
    }

    /// Does what a line or a row asks, then checks again.
    private func run(_ action: MenuAction, _ title: String) {
        let refresher = screen.refresher, actions = actions
        Task { await refresher.perform(action, title: title, using: actions) }
    }
}

/// A list of rows, keyed by their ids. A row that opens a submenu is a SwiftUI `Menu` inside the menu.
///
/// Apple, Menus and commands (https://developer.apple.com/documentation/swiftui/menus-and-commands):
/// "Create submenus by nesting Menu instances inside others".
/// Apple, Menu (https://developer.apple.com/documentation/swiftui/menu): "The primary action will be
/// performed when the user taps or clicks on the body of the control, and the menu presentation will
/// happen on a secondary gesture". On GitHub's macOS 15 and 26 runners (the `trial-submenus` branch,
/// posted pointer events, not a real trackpad), the pointer resting on such a row opened its submenu,
/// and a click on the row ran the primary action and closed the menu. A `Text` row was grey and a
/// click on it did nothing. None of this has been tried in MacMosh itself on a real Mac yet.
struct MenuRows: View {
    let rows: [MenuRow]
    let run: @MainActor (MenuAction, String) -> Void

    var body: some View {
        ForEach(rows) { row in
            switch row.kind {
            case .separator:
                Divider()
            case .text:
                Text(verbatim: row.label)
            case .button(let action):
                Button { run(action, row.title) } label: { Text(verbatim: row.label) }
            case .submenu(let lines, nil):
                Menu { MenuRows(rows: lines, run: run) } label: { Text(verbatim: row.label) }
            case .submenu(let lines, let primary?):
                Menu { MenuRows(rows: lines, run: run) } label: { Text(verbatim: row.label) } primaryAction: {
                    run(primary, row.title)
                }
            }
        }
    }
}
