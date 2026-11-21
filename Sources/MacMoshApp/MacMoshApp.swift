import MacMoshKit
import SwiftUI

/// The menu-bar app: one item, no Dock icon (`LSUIElement` in `App/Info.plist`).
@main
struct MacMoshApp: App {
    @StateObject private var refresher = MenuRefresher.standard()
    private let actions = MenuActionRunner(
        macmoshPath: Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/macmosh").path,
        tabs: AppTabs(),
        runner: ProcessRunner())

    init() {
        MenuLog.write(MenuLog.started(version: MacMoshInfo.version))
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(refresher: refresher, actions: actions)
        } label: {
            Image(systemName: refresher.menu.symbol)
                // The label is on screen from launch, so this starts the checks at once. They then
                // follow the schedule in `PollSchedule` and stop when the app does.
                .task {
                    await refresher.runInBackground(sleep: { try? await Task.sleep(for: $0) })
                }
                // AppKit says when a menu starts being tracked, which is when a person opens it.
                // The app has one menu, this one. (The menu content's `onAppear` runs once, when
                // the app starts, so it can't tell.) Once the app has windows of its own, a popup
                // button in one would count too, and this needs to tell them apart.
                .onReceive(NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification)) { _ in
                    Task { await refresher.menuOpened() }
                }
        }
    }
}

/// Opens a tab the way `macmosh open` does: the saved terminal choice, the same temporary folder
/// for the fallback file, and the real file check. Built on each use, so a changed setting counts.
struct AppTabs: TabOpening {
    func open(_ command: TabCommand, title: String) async throws -> String? {
        let settings = (try? WorkhorseStore(paths: Paths.standard()).loadSettings()) ?? AppSettings()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("macmosh-tabs", isDirectory: true)
        let opener = TabOpener(runner: ProcessRunner(), settings: settings, temporaryFolder: folder,
                               fileExists: { FileManager.default.fileExists(atPath: $0) })
        return try await opener.open(command, title: title)
    }
}
