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
