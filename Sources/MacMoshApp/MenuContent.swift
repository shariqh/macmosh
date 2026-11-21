import MacMoshKit
import SwiftUI

/// The menu's lines. An item with an action is a button: it does what the model says (open a tab, or
/// run `macmosh` in the background) and then checks again. An item with no action stays a line of text.
struct MenuContent: View {
    @ObservedObject var refresher: MenuRefresher
    let actions: MenuActionRunner

    var body: some View {
        Group {
            // What the last action said, until the next one.
            if let notice = refresher.notice {
                Text(notice)
                Divider()
            }
            let items = Array(refresher.menu.items.enumerated())
            ForEach(items, id: \.offset) { _, item in
                if item.isSeparator {
                    Divider()
                } else if item.action == .none {
                    Text(label(item))
                } else {
                    Button(label(item)) { Task { await refresher.perform(item, using: actions) } }
                }
            }
            Divider()
            Button("Quit MacMosh") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        // No `onAppear` here: macOS runs it once, when the app starts, not each time the menu
        // opens (seen on the first run, Task 20). The label in `MacMoshApp` hears the menu open.
    }

    /// One typeface and size throughout. Indent shows as three spaces a level: a menu has no margins to set.
    private func label(_ item: MenuItem) -> String {
        String(repeating: "   ", count: item.indent) + item.title
    }
}
