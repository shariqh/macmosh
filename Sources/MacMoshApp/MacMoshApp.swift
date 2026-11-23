import MacMoshKit
import SwiftUI

/// The menu-bar app: one item, no Dock icon (`LSUIElement` in `App/Info.plist`).
@main
struct MacMoshApp: App {
    /// The only object the app and the menu observe: the menu on screen and its notice (issue #107).
    /// The refresher it follows publishes more, for the main window, and none of that reaches the menu.
    @StateObject private var screen = MenuOnScreen(refresher: MenuRefresher.standard())
    private let actions = MenuActionRunner(
        macmoshPath: Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/macmosh").path,
        tabs: AppTabs(),
        runner: ProcessRunner())

    init() {
        MenuLog.write(MenuLog.started(version: MacMoshInfo.version))
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(screen: screen, actions: actions)
        } label: {
            Image(systemName: screen.shown.menu.symbol)
                // The label is on screen from launch, so this starts the checks at once. They then
                // follow the schedule in `PollSchedule` and stop when the app does.
                .task {
                    await screen.refresher.runInBackground(sleep: { try? await Task.sleep(for: $0) })
                }
                // AppKit says when a menu starts being tracked, which is when a person opens it.
                // The app has one menu, this one. (The menu content's `onAppear` runs once, when
                // the app starts, so it can't tell.) Once the app has windows of its own, a popup
                // button in one would count too, and this needs to tell them apart: the tracking
                // line logs which object came. Only the main menu bar is recognised yet; the
                // menu-bar item's own menu is read on a real Mac in a later step.
                // On the trial's runners one begin came per opening and none when a submenu opened.
                .onReceive(NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification)) { note in
                    MenuLog.write(MenuLog.tracking(.of(note.object as AnyObject?, mainMenu: NSApp.mainMenu)))
                    screen.menuBegan()
                    Task { await screen.refresher.menuOpened() }
                }
                // Apple: "Posted when menu tracking ends, even if no action is sent."
                // (https://developer.apple.com/documentation/appkit/nsmenu/didendtrackingnotification)
                // A change held while the menu was open is shown now.
                .onReceive(NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification)) { _ in
                    screen.menuEnded()
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
