import AppKit
import MacMoshKit
import SwiftUI

/// The MacMosh window: the sidebar beside the page for what it has selected (main window design,
/// section 7.2). It observes only `BoardOnScreen`, never the menu's object. Every word, button and order
/// comes from the board and the page models in MacMoshKit (`WorkhorsePage`, `SidebarItem`,
/// `WindowSelection`, `AddMacPage`), where they are tested; this only lays them out.
///
/// The controls are only Button, Text, TextField and radio-group Pickers: no pop-up, context menu, `Menu` or toolbar,
/// because the app can't yet tell the window's menus from the menu-bar menu (design, section 7.2). It is a plain
/// split of two views, not a `NavigationSplitView`, which brings a sidebar button of its own; the sidebar is a column
/// of buttons (look design 6.2), 200 points wide, that cannot be hidden or resized.
struct MainWindow: View {
    @ObservedObject var screen: BoardOnScreen
    let actions: MenuActionRunner
    /// New desk, Rename, Remove, naming a window, Start again and Forget, run in this process (steps 4 and 5, issue
    /// 144). The app's, not the window's, so an action started just before the window closes still finishes.
    @ObservedObject var forms: WindowActionRunner
    /// The Settings page's saves (issue 157). The app's, like `forms`.
    let settings: SettingsRunner
    /// What the person chose in the sidebar. A choice that is no longer on the board falls back as
    /// `WindowSelection.resolve` says. Lost when the window closes, which is harmless.
    @State private var chosen: WindowSelection?
    /// The open New desk or Rename form, and the Remove confirmation; an open one is lost with the window.
    @State private var newDesk: NewDeskForm?
    @State private var renaming: RenameForm?
    @State private var removing: RemoveConfirmation?
    /// The open sheet that names a window (issue 144).
    @State private var namingWindow: WindowNameForm?
    @State private var confirmingRemove = false

    var body: some View {
        let selection = WindowSelection.resolve(chosen, board: screen.board, listUnreadable: screen.listProblem != nil)
        HStack(spacing: 0) {
            Sidebar(items: SidebarItem.list(screen.board), selection: selection) { next in
                // A Settings field being typed in ends its editing first, so it sends what it holds while it is still
                // on screen (`endTextEditing`); the page changes one turn later. Otherwise the change is at once.
                if endTextEditing() {
                    Task { chosen = next }
                } else {
                    chosen = next
                }
            }
            .frame(width: LookSize.sidebarWidth)
            Rectangle()
                .fill(LookColor.mark(.hairline))
                .frame(width: 1)
                .accessibilityHidden(true)
            Group {
                switch selection {
                case .workhorse(let id):
                    if let page = screen.page(id, activity: forms.activity(id)) {
                        WorkhorsePageView(page: page, notice: page.notice(screen.notice), run: run)
                            .id(id)   // a new page for another workhorse: no detail strip carried over
                    }
                case .addMac:
                    AddMacPageView(page: .standard, notice: screen.notice, run: run)
                case .settings:
                    // The page follows the saved files at each check, as the sidebar does: a workhorse removed (by
                    // its own Remove button, say) or a value set with `macmosh set` shows without leaving the page.
                    // Lines are kept, and a field being typed in keeps its text. Apple, onReceive(_:perform:)
                    // (macOS 10.15, https://developer.apple.com/documentation/swiftui/view/onreceive(_:perform:)):
                    // "Adds an action to perform when this view detects data emitted by the given publisher." Apple,
                    // Publisher filter(_:) (https://developer.apple.com/documentation/combine/publisher/filter(_:)):
                    // "Republishes all elements that match a provided closure."
                    SettingsPageView(settings: settings, run: run)
                        .onReceive(screen.refresher.$isRefreshing.filter { $0 }) { _ in
                            let settings = settings
                            Task { await settings.reload() }
                        }
                case .unreadableList:
                    UnreadableListPageView(page: ListProblemPage(problem: screen.listProblem ?? ""))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        // The sidebar and the page share the look's warm ground, with a one-point hairline between them (look design
        // 6.1).
        .background(LookColor.background(.ground))
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
        .sheet(item: $namingWindow) { form in
            WindowNameSheet(forms: forms, form: form) { namingWindow = nil }
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
        // An ended desk's buttons (step 5): run by the app's runner, in a task of its own.
        switch button.action {
        case .window(.startAgain(let id, let desk, let keepIt)):
            let forms = forms
            Task { _ = await forms.startAgain(id, desk: desk, keepIt: keepIt) }
            return
        case .window(.forget(let id, let desk)):
            forms.forget(id, desk: desk)
            return
        default:
            break
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
        case .nameWindow(let id, let desk, let window):
            namingWindow = forms.nameWindowForm(id, desk: desk, window: window)
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
        case .settings: return "sidebar.settings"
        }
    }
    static func desk(_ name: String) -> String { "desk.\(name)" }
    static func open(_ name: String) -> String { "desk.\(name).open" }
    static func strip(_ name: String) -> String { "desk.\(name).strip" }
    /// A window's button in its desk's strip: `desk.website.win.@3`.
    static func window(_ name: String, _ id: String) -> String { "desk.\(name).win.\(id)" }
    /// A window's Name… button in its desk's strip: `desk.website.name.@3` (issue 144).
    static func nameWindow(_ name: String, _ id: String) -> String { "desk.\(name).name.\(id)" }
    /// A window's name in its desk's details, a static text: `desk.website.line.@3` (look step 2).
    static func windowLine(_ name: String, _ id: String) -> String { "desk.\(name).line.\(id)" }
    /// A window's state in its desk's details, a static text: `desk.website.state.@3` (look step 2).
    static func windowState(_ name: String, _ id: String) -> String { "desk.\(name).state.\(id)" }
    /// The window lines and the facts in a desk's details, each a group (look step 2).
    static func lines(_ name: String) -> String { "desk.\(name).lines" }
    static func facts(_ name: String) -> String { "desk.\(name).facts" }
    /// A button by what it does: `button.openAllWithoutTab`, `button.menu.connect.attic.api`.
    static func button(_ b: BoardButton) -> String {
        switch b.action {
        case .window(.newDesk): return "button.newDesk"
        case .window(.rename): return "button.rename"
        case .window(.remove): return "button.remove"
        case .window(.nameWindow): return "button.nameWindow"
        case .window(.openAllWithoutTab): return "button.openAllWithoutTab"
        case .window(.startAgain(_, let desk, let keepIt)): return "ended.\(desk).\(keepIt ? "keep" : "startAgain")"
        case .window(.forget(_, let desk)): return "ended.\(desk).forget"
        case .menu(.refresh): return "button.checkNow"
        case .menu(let action): return (["button.menu"] + action.words).joined(separator: ".")
        }
    }
    /// The text after a desk's name: its tabs, or "Updating…" and the like.
    static func status(_ name: String) -> String { "desk.\(name).status" }
    /// An ended desk's block (step 5), its time, its second line and its note: `ended.recipes`, `ended.recipes.when`.
    static func ended(_ name: String) -> String { "ended.\(name)" }
    static func ended(_ name: String, _ part: String) -> String { "ended.\(name).\(part)" }
    static let endedHeading = "ended.heading"
    static let result = "page.result"
    static let headline = "page.headline"
    static let addMac = "page.addMac"
    /// A setting's sentence on the Add a Mac page, one static text: `page.addMac.step.1` (look step 3).
    static func addMacStep(_ number: Int) -> String { "page.addMac.step.\(number)" }
    static let listProblem = "page.listProblem"
    /// The unreadable-list page's heading and next step (look step 2).
    static let listProblemHeading = "page.listProblemHeading"
    static let listProblemNext = "page.listProblemNext"
}

/// Ends the editing of a text field that is being typed in, so it sends what it holds (a Settings field sends when its
/// focus leaves, `SettingTextField`): true when one was being typed in and gave up the keyboard. A click on a sidebar
/// row, a plain button, may not take the keyboard from it as the system's list did (look step 3, Review Focus 1).
/// A typing text field's first responder is expected to be the window's field editor, an `NSTextView` (not found in
/// Apple's pages; CI's key-file check settles it). Apple, NSWindow.makeFirstResponder(_:)
/// (https://developer.apple.com/documentation/appkit/nswindow/makefirstresponder(_:)): "If responder is nil, this method
/// still sends resignFirstResponder() to the current first responder." and "If the current first responder returns
/// true from resignFirstResponder(), the window is made its own first responder and this method returns true." Apple,
/// NSWindow.fieldEditor(_:for:) (https://developer.apple.com/documentation/appkit/nswindow/fieldeditor(_:for:)): "The
/// field editor is a single NSTextView object that is shared among all the controls in a window". Apple,
/// NSApplication.keyWindow (https://developer.apple.com/documentation/appkit/nsapplication/keywindow): "The window that
/// currently receives keyboard events."
@MainActor private func endTextEditing() -> Bool {
    guard let window = NSApp.keyWindow, window.firstResponder is NSTextView else { return false }
    return window.makeFirstResponder(nil)
}

/// The sidebar (look design 6.2): a column of buttons on the ground, not the system's selectable list, each workhorse
/// with its state's symbol and second line, then Add a Mac… and Settings. A click calls `choose`. It gives up the
/// system's sidebar material, its selection drawing and the arrow keys between Macs; every row stays a button that Tab
/// reaches when keyboard navigation is on, and the chosen one carries the selected trait.
///
/// Apple, ScrollView (macOS 10.15, https://developer.apple.com/documentation/swiftui/scrollview): "A scrollable view."
/// Apple, scrollContentBackground(_:) (macOS 13.0,
/// https://developer.apple.com/documentation/swiftui/view/scrollcontentbackground(_:)): "Specifies the visibility of
/// the background for scrollable views within this view." It is hidden, as look design 6.1 says, so the ground shows.
struct Sidebar: View {
    let items: [SidebarItem]
    let selection: WindowSelection
    let choose: (WindowSelection) -> Void

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(items) { item in
                    SidebarRow(item: item, isChosen: item.selection == selection) { choose(item.selection) }
                }
            }
            .padding(10)
        }
        .scrollContentBackground(.hidden)
    }
}

/// One row of the sidebar (look design 6.2, look-b-light.png): a small tile with the symbol, the name on one line
/// (cut with "…") and the second line under it in ink-3; the chosen row is a card with the selected trait. One
/// button, whose label for VoiceOver and CI is the name, then the second line ("Workhorse, Ready · 6 desks"). No help
/// tag: a click leaves CI's pointer on the row, and the spoken label and the page's title carry a cut name whole.
///
/// Apple, PrimitiveButtonStyle.plain (macOS 10.15, https://developer.apple.com/documentation/swiftui/primitivebuttonstyle/plain):
/// "A button style that doesn't style or decorate its content while idle, but may apply a visual effect to indicate the
/// pressed, focused, or enabled state of the button." Apple, accessibilityLabel(_:)
/// (https://developer.apple.com/documentation/swiftui/view/accessibilitylabel(_:)): "Adds a label to the view that
/// describes its contents." Apple, accessibilityAddTraits(_:) (macOS 11.0,
/// https://developer.apple.com/documentation/swiftui/view/accessibilityaddtraits(_:)): "Adds the given traits to the
/// view."; AccessibilityTraits.isSelected (macOS 10.15,
/// https://developer.apple.com/documentation/swiftui/accessibilitytraits/isselected): "The accessibility element is
/// currently selected."
struct SidebarRow: View {
    let item: SidebarItem
    let isChosen: Bool
    let choose: () -> Void

    var body: some View {
        let on: BackgroundRole = isChosen ? .surface : .ground
        Button(action: choose) {
            HStack(spacing: 10) {
                SidebarTile(symbol: item.symbol, tone: item.tone, onCard: isChosen)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: item.title)
                        .font(.system(size: LookSize.bodyFont, weight: isChosen ? .semibold : .regular))
                        .foregroundStyle(LookColor.text(.primary, on: on))
                        .lineLimit(1).truncationMode(.tail)
                    if let second = item.second {
                        Text(verbatim: second)
                            .font(.system(size: LookSize.tagFont))
                            .foregroundStyle(LookColor.text(.tertiary, on: on))
                            .lineLimit(LookSize.sidebarSecondLines)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .background {
                if isChosen { Color.clear.lookTile(radius: LookSize.smallTileRadius) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: item.spokenLabel))
        .accessibilityAddTraits(isChosen ? .isSelected : [])
        .accessibilityIdentifier(WindowMarks.sidebar(item.selection))
    }
}

/// A sidebar row's tile: a small square, white on the ground and grey on the chosen card, with the state's symbol in its
/// tone (the plus and the gear in ink). Decoration: the row's words say the same, so it is hidden from VoiceOver.
///
/// The symbol's name stays the menu's; the tile draws its filled variant where it has one, as look-b-light.png and
/// look-b-dark.png draw the tick and the gear. Apple, symbolVariant(_:) (macOS 12.0,
/// https://developer.apple.com/documentation/swiftui/view/symbolvariant(_:)): "Makes symbols within the view show a
/// particular variant." and "A symbol that doesn’t have the specified variant remains unaffected."
struct SidebarTile: View {
    let symbol: String
    let tone: PillTone?
    let onCard: Bool

    var body: some View {
        Image(systemName: symbol)
            .symbolVariant(.fill)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(LookColor.mark(tone?.textRole.token ?? .ink))
            .frame(width: LookSize.smallTile, height: LookSize.smallTile)
            .lookTile(radius: LookSize.smallTileRadius, fill: onCard ? .surface2 : .surface)
            .accessibilityHidden(true)
    }
}

/// The last action's sentence, the one the menu shows as its first line.
struct NoticeLine: View {
    let notice: String?

    var body: some View {
        if let notice {
            Text(verbatim: notice)
                .foregroundStyle(LookColor.text(.secondary, on: .ground))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A row of buttons, each with the board's title, in the look's style for what it does (`ButtonKind`); small inside a
/// desk's opened details.
struct ButtonRow: View {
    let buttons: [BoardButton]
    var small = false
    let run: (BoardButton) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(buttons.enumerated()), id: \.offset) { _, button in
                Button { run(button) } label: { Text(verbatim: button.title) }
                    .buttonStyle(LookButtonStyle(kind: ButtonKind.of(button.action),
                                                 glyph: LookButtonStyle.glyph(for: button.action), small: small))
                    .disabled(!button.isEnabled)
                    .accessibilityIdentifier(WindowMarks.button(button))
            }
        }
    }
}
