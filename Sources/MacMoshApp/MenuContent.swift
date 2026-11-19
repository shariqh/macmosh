import MacMoshKit
import SwiftUI

/// The menu's lines, read-only for now: every item is a line of text. Task 27 wires up the actions.
struct MenuContent: View {
    @ObservedObject var refresher: MenuRefresher

    var body: some View {
        let items = Array(refresher.menu.items.enumerated())
        ForEach(items, id: \.offset) { _, item in
            if item.isSeparator {
                Divider()
            } else if item.action == .refresh {
                // The model's own "Check now" line is the real button.
                Button("Check now") { Task { await refresher.refresh() } }
            } else {
                // One typeface and size throughout. Indent shows with spaces: a menu has no margins to set.
                Text(String(repeating: "    ", count: item.indent) + item.title)
            }
        }
        Divider()
        Button("Quit MacMosh") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}
