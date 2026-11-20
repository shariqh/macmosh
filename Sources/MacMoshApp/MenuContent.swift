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
        // Whether macOS runs this each time the menu opens is checked on the Air (Task 20): the log
        // line it writes shows it. If it doesn't, `Check now` and the background schedule still
        // keep the menu fresh.
        .onAppear { Task { await refresher.menuOpened() } }
    }

    /// One typeface and size throughout. Indent shows as three spaces a level: a menu has no margins to set.
    private func label(_ item: MenuItem) -> String {
        String(repeating: "   ", count: item.indent) + item.title
    }
}
