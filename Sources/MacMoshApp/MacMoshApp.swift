import MacMoshKit
import SwiftUI

/// The menu-bar app: one item, no Dock icon (`LSUIElement` in `App/Info.plist`).
@main
struct MacMoshApp: App {
    /// The only object the app and the menu observe: the menu on screen and its notice (issue #107).
    /// The refresher it follows publishes more, for the main window, and none of that reaches the menu.
    @StateObject private var screen: MenuOnScreen
    private let actions: MenuActionRunner
    /// How the checks wait between two rounds: `PollSchedule`'s delay, or a second for a sample menu.
    private let pause: @Sendable (Duration) async -> Void

    init() {
        MenuLog.write(MenuLog.started(version: MacMoshInfo.version))
        #if DEBUG
        // Debug builds only (issue #113): a sample menu for CI's pictures, with no workhorse checked.
        if let name = SampleMenu.requested {
            guard let sample = SampleMenu(rawValue: name) else {
                FileHandle.standardError.write(Data("MacMosh: no sample menu is named \(name)\n".utf8))
                exit(64)
            }
            MenuLog.write(sample.startedLine)
            _screen = StateObject(wrappedValue: MenuOnScreen(refresher: sample.refresher()))
            actions = SampleMenu.actions
            pause = { _ in try? await Task.sleep(for: SampleMenu.lookEvery) }
            return
        }
        #endif
        _screen = StateObject(wrappedValue: MenuOnScreen(refresher: MenuRefresher.standard()))
        actions = MenuActionRunner(
            macmoshPath: Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/macmosh").path,
            tabs: AppTabs(),
            runner: ProcessRunner(),
            records: TabRecordStore(paths: Paths.standard()))
        pause = { try? await Task.sleep(for: $0) }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(screen: screen, actions: actions)
        } label: {
            Image(systemName: screen.shown.menu.symbol)
                // The label is on screen from launch, so this starts the checks at once. They then
                // follow the schedule in `PollSchedule` and stop when the app does.
                .task {
                    await screen.refresher.runInBackground(sleep: pause)
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
                // A change held while the menu was open is not shown now: on the trial's runners this
                // notice came about 2 ms before the clicked line's action (question 6), so it is shown
                // 300 milliseconds later (`MenuOnScreen.closingWait`), unless the menu opens again first.
                .onReceive(NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification)) { _ in
                    screen.menuEnded()
                }
        }
    }
}

/// Opens a tab the way `macmosh open` does: the saved terminal choice, the same temporary folder
/// for the fallback file, and the real file check. Built on each use, so a changed setting counts.
/// Bringing a tab forward goes the same way, from this app's own process, which holds the Automation
/// permission (menu design 6.2).
struct AppTabs: TabOpening {
    func open(_ command: TabCommand, title: String) async throws -> String? {
        try await opener().open(command, title: title)
    }

    func select(tty: String, terminal: TabRecord.Terminal) async throws -> TabSelection {
        try await opener().select(tty: tty, terminal: terminal)
    }

    private func opener() -> TabOpener {
        let settings = (try? WorkhorseStore(paths: Paths.standard()).loadSettings()) ?? AppSettings()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("macmosh-tabs", isDirectory: true)
        return TabOpener(runner: ProcessRunner(), settings: settings, temporaryFolder: folder,
                         fileExists: { FileManager.default.fileExists(atPath: $0) })
    }
}
