import MacMoshKit
import SwiftUI

/// The MacMosh window: the sidebar beside the page for what it has selected (main window design,
/// section 7.2). It observes only `BoardOnScreen`, never the menu's object. Every word, button and order
/// comes from the board and the page models in MacMoshKit (`WorkhorsePage`, `SidebarItem`,
/// `WindowSelection`, `AddMacPage`), where they are tested; this only lays them out.
///
/// The controls are only Button, Text and List: no pop-up, context menu, `Menu` or toolbar, because the
/// app can't yet tell the window's menus from the menu-bar menu (design, section 7.2). It is a plain
/// split of two views, not a `NavigationSplitView`, which brings a sidebar button of its own.
struct MainWindow: View {
    @ObservedObject var screen: BoardOnScreen
    let actions: MenuActionRunner
    /// New desk, Rename and Remove, run in this process (step 4). The app's, not the window's, so an action
    /// started just before the window closes still finishes.
    @ObservedObject var forms: WindowActionRunner
    /// What the person chose in the sidebar. A choice that is no longer on the board falls back as
    /// `WindowSelection.resolve` says. Lost when the window closes, which is harmless.
    @State private var chosen: WindowSelection?
    /// The open New desk or Rename form, and the Remove confirmation; an open one is lost with the window.
    @State private var newDesk: NewDeskForm?
    @State private var renaming: RenameForm?
    @State private var removing: RemoveConfirmation?
    @State private var confirmingRemove = false

    var body: some View {
        let selection = WindowSelection.resolve(chosen, board: screen.board, listUnreadable: screen.listProblem != nil)
        HStack(spacing: 0) {
            Sidebar(items: SidebarItem.list(screen.board), selection: selection) { chosen = $0 }
                .frame(width: 200)
            Divider()
            Group {
                switch selection {
                case .workhorse(let id):
                    if let page = screen.page(id, activity: forms.activity(id)) {
                        WorkhorsePageView(page: page, notice: page.notice(screen.notice), run: run)
                            .id(id)   // a new page for another workhorse: no detail strip carried over
                    }
                case .addMac:
                    AddMacPageView(page: .standard, notice: screen.notice, run: run)
                case .unreadableList:
                    // The menu's own sentence, in place of an invitation to add a Mac.
                    Text(verbatim: screen.listProblem ?? "")
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(20)
                        .accessibilityIdentifier(WindowMarks.listProblem)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 700, minHeight: 440)
        // Apple, sheet(item:onDismiss:content:) (macOS 10.15,
        // https://developer.apple.com/documentation/swiftui/view/sheet(item:ondismiss:content:)): "Presents a
        // sheet using the given item as a data source for the sheet's content."
        .sheet(item: $newDesk) { form in
            NewDeskSheet(forms: forms, form: form) { newDesk = nil }
        }
        .sheet(item: $renaming) { form in
            RenameSheet(forms: forms, form: form) { renaming = nil }
        }
        // Apple, confirmationDialog(_:isPresented:titleVisibility:presenting:actions:message:) (macOS 13.0,
        // https://developer.apple.com/documentation/swiftui/view/confirmationdialog(_:ispresented:titlevisibility:presenting:actions:message:)):
        // "All actions in a confirmation dialog will dismiss the dialog after the action runs." Apple,
        // ButtonRole.destructive (macOS 12.0, https://developer.apple.com/documentation/swiftui/buttonrole/destructive):
        // "Use this role for a button that deletes user data, or performs an irreversible operation."
        .confirmationDialog(removing?.title ?? "", isPresented: $confirmingRemove, titleVisibility: .visible,
                            presenting: removing) { confirmation in
            Button(role: .destructive) { remove(confirmation) } label: { Text(verbatim: confirmation.button) }
            Button(role: .cancel) { removing = nil } label: { Text(verbatim: RemoveConfirmation.cancel) }
        } message: { confirmation in
            Text(verbatim: confirmation.message)
        }
        // The one check the window adds, when it opens (design 7.2). Started as a task of its own rather
        // than with `.task`, which Apple says is cancelled "If the task doesn't finish before SwiftUI
        // removes the view" (https://developer.apple.com/documentation/swiftui/view/task(name:priority:file:line:_:)):
        // the check is the menu's too, and closing the window must not cut it short.
        .onAppear {
            let screen = screen
            Task { await screen.opened() }
            #if DEBUG
            WindowKeysMonitor.logMainMenu()   // what the main menu holds, for CI (issue #147); nothing otherwise
            #endif
            // Paste, copy, cut, select all, undo, redo and Command-W in the window (issue #147).
            let forms = forms
            WindowKeysMonitor.shared.start(making: { !forms.making.isEmpty })
        }
    }

    /// Opens the form a button names (`WindowRun.form`), or runs its action the way the menu runs its line:
    /// the refresher's `perform` with the app's `MenuActionRunner`, then a check.
    private func run(_ button: BoardButton) {
        guard button.isEnabled else { return }
        if let form = WindowRun.form(for: button.action) {
            open(form)
            return
        }
        guard let action = WindowRun.menuAction(for: button.action) else { return }
        #if DEBUG
        SampleRun.windowRan(action)   // a sample's log line for CI; nothing otherwise
        #endif
        let refresher = screen.refresher, actions = actions, title = button.title
        Task { await refresher.perform(action, title: title, from: .window, using: actions) }
    }

    private func open(_ form: WindowForm) {
        switch form {
        case .newDesk(let id):
            let forms = forms
            Task { newDesk = await forms.newDeskForm(id) }
        case .rename(let id, let desk):
            renaming = forms.renameForm(id, desk: desk)
        case .remove(let id, let desk):
            removing = forms.removeConfirmation(id, desk: desk)
            confirmingRemove = removing != nil
        }
    }

    /// The explicit yes the typed `yes` was: removes the desk the confirmation named, in a task of its own.
    private func remove(_ confirmation: RemoveConfirmation) {
        removing = nil
        let forms = forms
        Task { _ = await forms.remove(confirmation) }
    }
}

/// Accessibility identifiers, for CI's driver only (scripts/ci/drive-window.sh). Apple,
/// accessibilityIdentifier(_:) (https://developer.apple.com/documentation/swiftui/view/accessibilityidentifier(_:)):
/// "Use this value for testing. It isn't visible to the user."
enum WindowMarks {
    static func sidebar(_ selection: WindowSelection) -> String {
        switch selection {
        case .workhorse(let id): return "sidebar.\(id)"
        case .addMac: return "sidebar.addMac"
        case .unreadableList: return "sidebar.unreadableList"
        }
    }
    static func desk(_ name: String) -> String { "desk.\(name)" }
    static func open(_ name: String) -> String { "desk.\(name).open" }
    static func strip(_ name: String) -> String { "desk.\(name).strip" }
    /// A window's button in its desk's strip: `desk.website.win.@3`.
    static func window(_ name: String, _ id: String) -> String { "desk.\(name).win.\(id)" }
    /// A button by what it does: `button.openAllWithoutTab`, `button.menu.connect.attic.api`.
    static func button(_ b: BoardButton) -> String {
        switch b.action {
        case .window(.newDesk): return "button.newDesk"
        case .window(.rename): return "button.rename"
        case .window(.remove): return "button.remove"
        case .window(.openAllWithoutTab): return "button.openAllWithoutTab"
        case .window(.startAgain), .window(.forget): return "button.ended"
        case .menu(.refresh): return "button.checkNow"
        case .menu(let action): return (["button.menu"] + action.words).joined(separator: ".")
        }
    }
    /// The text after a desk's name: its tabs, or "Updating…" and the like.
    static func status(_ name: String) -> String { "desk.\(name).status" }
    static let result = "page.result"
    static let headline = "page.headline"
    static let addMac = "page.addMac"
    static let listProblem = "page.listProblem"
}

/// Each workhorse with its state's symbol, then Add a Mac….
struct Sidebar: View {
    let items: [SidebarItem]
    let selection: WindowSelection
    let choose: (WindowSelection) -> Void

    var body: some View {
        List(selection: Binding(get: { Optional(selection) }, set: { if let next = $0 { choose(next) } })) {
            ForEach(items) { item in
                Label { Text(verbatim: item.title) } icon: { Image(systemName: item.symbol) }
                    .tag(item.selection)
                    .accessibilityIdentifier(WindowMarks.sidebar(item.selection))
            }
        }
        .listStyle(.sidebar)
    }
}

/// The last action's sentence, the one the menu shows as its first line.
struct NoticeLine: View {
    let notice: String?

    var body: some View {
        if let notice {
            Text(verbatim: notice)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A row of buttons, each with the board's title.
struct ButtonRow: View {
    let buttons: [BoardButton]
    let run: (BoardButton) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(buttons.enumerated()), id: \.offset) { _, button in
                Button { run(button) } label: { Text(verbatim: button.title) }
                    .disabled(!button.isEnabled)
                    .accessibilityIdentifier(WindowMarks.button(button))
            }
        }
    }
}

/// Section 7.1 E: what to switch on at the other Mac, and the menu's Add a Mac… button.
struct AddMacPageView: View {
    let page: AddMacPage
    let notice: String?
    let run: (BoardButton) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: page.heading).font(.title2).bold()
                .accessibilityIdentifier(WindowMarks.addMac)
            NoticeLine(notice: notice)
            ForEach(Array(page.lines.enumerated()), id: \.offset) { _, line in
                Text(verbatim: line).fixedSize(horizontal: false, vertical: true)
            }
            ButtonRow(buttons: [page.button], run: run)
        }
        .padding(20)
    }
}
