import MacMoshKit
import SwiftUI

/// The menu-bar app: one item, no Dock icon (`LSUIElement` in `App/Info.plist`), and the MacMosh
/// window, which opens only from the menu's Open MacMosh line (main window design, section 7.2).
@main
struct MacMoshApp: App {
    /// The only object the app and the menu observe: the menu on screen and its notice (issue #107).
    /// The refresher it follows publishes more, for the main window, and none of that reaches the menu.
    @StateObject private var screen: MenuOnScreen
    /// Keeps the app running when its last window closes; see `AppDelegate`.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    /// The window's own object, which only the window's views observe. It is not a state object of the
    /// app, so a new board never makes the app's scenes, and with them the menu, draw again.
    private let board: BoardOnScreen
    private let actions: MenuActionRunner
    /// The window's New desk, Rename and Remove (step 4). The app's, so an action started just before the
    /// window closes still finishes.
    private let forms: WindowActionRunner
    /// The Settings page's saves (issue 157), the app's like `forms`.
    private let settings: SettingsRunner
    /// How the checks wait between two rounds: `PollSchedule`'s delay, or a second for a sample menu.
    private let pause: @Sendable (Duration) async -> Void

    init() {
        MenuLog.write(MenuLog.started(version: MacMoshInfo.version))
        #if DEBUG
        // Debug builds only (issue #113): a sample menu for CI's pictures, with no workhorse checked.
        if let name = SampleMenu.requested {
            guard let sample = SampleRun.named(name) else {
                FileHandle.standardError.write(Data("MacMosh: no sample menu is named \(name)\n".utf8))
                exit(64)
            }
            MenuLog.write(sample.startedLine)
            let refresher = sample.refresher
            _screen = StateObject(wrappedValue: MenuOnScreen(refresher: refresher))
            let sampleBoard = BoardOnScreen(refresher: refresher, load: sample.load)
            board = sampleBoard
            actions = sample.actions
            forms = WindowActionRunner(refresher: refresher, commands: sample.ssh, paths: sample.paths,
                                       menuActions: sample.actions)
            // The sample's stand-in store, never the person's saved list or settings.
            settings = Self.settingsRunner(WorkhorseStore(paths: sample.settingsPaths), board: sampleBoard)
            pause = { _ in try? await Task.sleep(for: SampleMenu.lookEvery) }
            return
        }
        #endif
        // The menu's object and the window's follow this one refresher. That relies on `@main` making
        // the app once: a second init would give the board a refresher nothing runs.
        let refresher = MenuRefresher.standard()
        _screen = StateObject(wrappedValue: MenuOnScreen(refresher: refresher))
        let realBoard = BoardOnScreen(refresher: refresher, load: { try WorkhorseStore(paths: Paths.standard()).load() })
        board = realBoard
        actions = MenuActionRunner(
            macmoshPath: Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/macmosh").path,
            tabs: AppTabs(),
            runner: ProcessRunner(),
            records: TabRecordStore(paths: Paths.standard()))
        forms = WindowActionRunner(refresher: refresher, commands: ProcessRunner(), paths: Paths.standard(),
                                   menuActions: actions)
        settings = Self.settingsRunner(WorkhorseStore(paths: Paths.standard()), board: realBoard)
        pause = { try? await Task.sleep(for: $0) }
    }

    /// The Settings page's runner on that store: a key file is looked for on this Mac, Pick for me is `TabOpener`'s
    /// rule with no setting, and after each save the window's board reads the saved list again, so the sidebar and
    /// the page's heading show a new name at once. Nothing here starts a check.
    private static func settingsRunner(_ store: WorkhorseStore, board: BoardOnScreen) -> SettingsRunner {
        SettingsRunner(
            store: store, home: FileManager.default.homeDirectoryForCurrentUser.path,
            keyFileExists: { path in
                var folder: ObjCBool = false
                return FileManager.default.fileExists(atPath: path, isDirectory: &folder) && !folder.boolValue
            },
            pickForMe: { TabOpener.terminal(settings: AppSettings(), fileExists: { FileManager.default.fileExists(atPath: $0) }) },
            saved: { await board.reloadList() })
    }

    /// Apple, MenuBarExtra `init(isInserted:content:label:)` (macOS 13.0,
    /// https://developer.apple.com/documentation/swiftui/menubarextra/init(isinserted:content:label:)):
    /// "If the user removes the item from the menu bar, the binding will be set to false." The menu used
    /// `init(content:label:)` before, of which Apple says "When this item is removed from the system menu
    /// bar by the user, the application will be automatically quit. As such, it should not be used in
    /// conjunction with other scene types in your App."
    /// (https://developer.apple.com/documentation/swiftui/menubarextra/init(content:label:)). So the app
    /// quits itself when the binding turns false, and removing the icon still quits it, as before.
    private var inserted: Binding<Bool> {
        Binding(get: { true }, set: { stillThere in
            if !stillThere {
                MenuLog.write(MenuLog.iconRemoved)
                NSApplication.shared.terminate(nil)
            }
        })
    }

    var body: some Scene {
        // The menu-bar item stays the first scene. Apple, Window
        // (https://developer.apple.com/documentation/swiftui/window): "If your app uses a single window
        // as its primary scene, the app quits when the window closes." The window is the second scene.
        MenuBarExtra(isInserted: inserted) {
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
                // the app starts, so it can't tell.) The window has no pop-up, context menu, `Menu` or
                // toolbar (main window design 7.2), but a right-click in a text field would still show
                // the system's edit menu and count here: the tracking line logs which object came.
                // Only the main menu bar is recognised yet; the menu-bar item's own menu is read on a
                // real Mac in a later sitting.
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

        // Apple, Window: "A scene that presents its content in a single, unique window." … "If the
        // window is already open when you call this action, the action brings the open window to the
        // front." (macOS 13.0, https://developer.apple.com/documentation/swiftui/window)
        Window(WindowWords.title, id: WindowWords.windowID) {
            MainWindow(screen: board, actions: actions, forms: forms, settings: settings)
        }
        // "The scene will not present itself in the absence of any previously restored scenes."
        // (SceneLaunchBehavior.suppressed, macOS 15.0,
        // https://developer.apple.com/documentation/swiftui/scenelaunchbehavior/suppressed ;
        // https://developer.apple.com/documentation/swiftui/scene/defaultlaunchbehavior(_:)). With the
        // restoration below there is never a restored one, so it opens only when asked for.
        .defaultLaunchBehavior(.suppressed)
        // "The disabled behavior. The scene's windows will not be restored." (SceneRestorationBehavior
        // .disabled, macOS 15.0, https://developer.apple.com/documentation/swiftui/scenerestorationbehavior/disabled ;
        // https://developer.apple.com/documentation/swiftui/scene/restorationbehavior(_:))
        .restorationBehavior(.disabled)
        // "Sets a default width and height for a window." (macOS 13.0,
        // https://developer.apple.com/documentation/swiftui/scene/defaultsize(width:height:)). It fits
        // the CI runners' 1024 by 768 screen, with room for the foot under one open detail strip.
        .defaultSize(width: 880, height: 680)
        // contentMinSize: "A minimum size that matches the minimum size of the window's content." and
        // "No maximum size." (macOS 13.0, https://developer.apple.com/documentation/swiftui/windowresizability/contentminsize ;
        // https://developer.apple.com/documentation/swiftui/scene/windowresizability(_:)). The minimum is
        // the frame `MainWindow` sets.
        .windowResizability(.contentMinSize)
    }
}

/// The app's delegate, for two AppKit questions SwiftUI leaves open.
///
/// On GitHub's macOS 15 and 26 runners, with the window scene added, the app quit with nothing on
/// stderr when the menu closed after a click on a desk's line (with no window open), and when the
/// MacMosh window was closed (pull request #126, first run). A menu-bar app must outlive both. AppKit
/// asks this each time the menu closes too, so it writes no log line.
/// Apple, `applicationShouldTerminateAfterLastWindowClosed(_:)`
/// (https://developer.apple.com/documentation/appkit/nsapplicationdelegate/applicationshouldterminateafterlastwindowclosed(_:)):
/// "If your implementation returns false, control returns to the main event loop and the application
/// is not terminated." Apple, NSApplicationDelegateAdaptor
/// (https://developer.apple.com/documentation/swiftui/nsapplicationdelegateadaptor): "SwiftUI
/// instantiates the delegate and calls the delegate's methods in response to life cycle events."
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        MenuLog.write(MenuLog.quitting)
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
