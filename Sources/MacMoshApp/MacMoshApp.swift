import MacMoshKit
import SwiftUI

/// The menu-bar app: one item, no Dock icon (`LSUIElement` in `App/Info.plist`).
@main
struct MacMoshApp: App {
    @StateObject private var refresher = MenuRefresher.standard()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(refresher: refresher)
        } label: {
            Image(systemName: refresher.menu.symbol)
                // The label is on screen from launch, so this runs at once and then every 30 seconds.
                // Task 27 replaces the timer with the schedule in the plan.
                .task {
                    while !Task.isCancelled {
                        await refresher.refresh()
                        try? await Task.sleep(for: .seconds(30))
                    }
                }
        }
    }
}
