import MacMoshKit
import SwiftUI

/// The New desk sheet (main window design, sections 7.1 B and 7.5), drawn from `NewDeskForm`, which holds every
/// rule and word; `WindowActionRunner` reads the folders, saves the projects folder and makes the desk.
///
/// Controls: Button, Text, TextField, Toggle, a radio-group Picker and List only (section 7.2). Apple,
/// PickerStyle.radioGroup (macOS 10.15, https://developer.apple.com/documentation/swiftui/pickerstyle/radiogroup):
/// "A picker style that presents the options as a group of radio buttons." Apple, ToggleStyle.checkbox (macOS
/// 10.15, https://developer.apple.com/documentation/swiftui/togglestyle/checkbox): "A toggle style that displays a
/// checkbox followed by its label."
struct NewDeskSheet: View {
    @ObservedObject var forms: WindowActionRunner
    @State var form: NewDeskForm
    let close: () -> Void
    /// Why the last Make desk didn't make it; the sheet stays open with it.
    @State private var failure: String?
    /// Why the projects folder wasn't saved.
    @State private var saveProblem: String?
    /// A Save is running.
    @State private var saving = false

    private var making: Bool { forms.making.contains(form.workhorseID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: form.title).font(.headline)
            Group {
                folders
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(verbatim: NewDeskForm.Words.orAPath)
                        plainField(NewDeskForm.Words.orAPath,
                                   text: Binding(get: { form.typedPath }, set: { form.setTypedPath($0) }))
                            .accessibilityIdentifier(FormMarks.path)
                    }
                    // Why a typed path can't be used; nothing while the field is empty.
                    if let line = form.pathLine {
                        Text(verbatim: line).font(.caption).foregroundStyle(.red)
                            .accessibilityIdentifier(FormMarks.path + ".help")
                    }
                }
                fields
            }
            // Nothing changes under a desk being made: what he sees is what was sent.
            .disabled(making)
            Toggle(isOn: $form.openInTab) { Text(verbatim: NewDeskForm.Words.openInATabNow) }
                .toggleStyle(.checkbox)
                .disabled(making)
                .accessibilityIdentifier(FormMarks.openInTab)
            HStack {
                Spacer()
                Button { close() } label: { Text(verbatim: NewDeskForm.Words.cancel) }
                    // Apple, KeyboardShortcut.cancelAction (macOS 11.0,
                    // https://developer.apple.com/documentation/swiftui/keyboardshortcut/cancelaction): "The standard
                    // keyboard shortcut for cancelling the in-progress action or dismissing a prompt, consisting of
                    // the Escape (⎋) key and no modifiers."
                    .keyboardShortcut(.cancelAction)
                    .disabled(making)
                    .accessibilityIdentifier(FormMarks.cancel)
                Button { make() } label: { Text(verbatim: making ? NewDeskForm.Words.making : NewDeskForm.Words.makeDesk) }
                    // Apple, KeyboardShortcut.defaultAction (macOS 11.0,
                    // https://developer.apple.com/documentation/swiftui/keyboardshortcut/defaultaction): "The standard
                    // keyboard shortcut for the default button, consisting of the Return (↩) key and no modifiers."
                    .keyboardShortcut(.defaultAction)
                    .disabled(!form.canMake || making)
                    .accessibilityIdentifier(FormMarks.make)
            }
            if let failure {
                Text(verbatim: failure).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(FormMarks.failure)
            }
        }
        .padding(20)
        .frame(width: 560)
        // Apple, interactiveDismissDisabled(_:) (macOS 12.0,
        // https://developer.apple.com/documentation/swiftui/view/interactivedismissdisabled(_:)): "Conditionally
        // prevents interactive dismissal of presentations like popovers, sheets, and inspectors."
        .interactiveDismissDisabled(making)
        // A container, so its fields keep their own identifiers (as the detail strip does).
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(FormMarks.newDesk)
        .task { await readFolders() }
    }

    /// Name, Command to start, After a restart, and When its last shell exits.
    private var fields: some View {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text(verbatim: NewDeskForm.Words.name)
                    field(NewDeskForm.Words.name, text: Binding(get: { form.name }, set: { form.setName($0) }),
                          help: form.nameLine, isProblem: form.nameLineIsProblem,
                          mark: FormMarks.name)
                }
                GridRow {
                    Text(verbatim: NewDeskForm.Words.command)
                    field(NewDeskForm.Words.command, text: $form.command,
                          help: form.commandLine, isProblem: form.commandLineIsProblem,
                          mark: FormMarks.command)
                }
                GridRow {
                    Text(verbatim: NewDeskForm.Words.afterARestart)
                    Toggle(isOn: $form.comesBack) { Text(verbatim: NewDeskForm.Words.comesBack) }
                        .toggleStyle(.checkbox)
                        .accessibilityIdentifier(FormMarks.comesBack)
                }
                // Hidden for a script older than 0.5.0 (section 7.2).
                if form.canKeepClosed {
                    GridRow {
                        Text(verbatim: NewDeskForm.Words.whenItsLastShellExits)
                        Picker(selection: $form.keepClosed) {
                            Text(verbatim: NewDeskForm.Words.removeTheDesk).tag(false)
                            Text(verbatim: NewDeskForm.Words.keepItClosed).tag(true)
                        } label: {
                            Text(verbatim: NewDeskForm.Words.whenItsLastShellExits)
                        }
                        .pickerStyle(.radioGroup)
                        .labelsHidden()
                        .accessibilityIdentifier(FormMarks.whenItExits)
                    }
                }
            }
    }

    /// The folder list with its filter, the one line that saves a projects folder, or why the list can't be read.
    @ViewBuilder private var folders: some View {
        switch form.folders {
        case .noProjectsFolder:
            HStack {
                Text(verbatim: form.projectsFolderLine)
                plainField(form.projectsFolderLine, text: $form.projectsFolderDraft)
                    .frame(width: 220)
                    // Return in this field saves, since Make desk (the default button) is off here. Apple,
                    // TextField.init(text:prompt:label:) (https://developer.apple.com/documentation/swiftui/textfield/init(text:prompt:label:)):
                    // "Use the onSubmit(of:_:) modifier to invoke an action whenever the user submits this text field."
                    .onSubmit { save() }
                    .accessibilityIdentifier(FormMarks.projectsFolder)
                Button { save() } label: { Text(verbatim: NewDeskForm.Words.save) }
                    .disabled(!form.canSaveProjectsFolder || saving)
                    .accessibilityIdentifier(FormMarks.saveProjectsFolder)
            }
            if let saveProblem {
                Text(verbatim: saveProblem).foregroundStyle(.red)
            }
        case .reading:
            Text(verbatim: form.folderHeading)
            Text(verbatim: NewDeskForm.Words.reading).foregroundStyle(.secondary)
        case .listed:
            HStack {
                Text(verbatim: form.folderHeading)
                Spacer()
                TextField(NewDeskForm.Words.filter, text: $form.filter)
                    .frame(width: 180)
                    .accessibilityIdentifier(FormMarks.filter)
            }
            List(selection: Binding(get: { form.chosen }, set: { if let folder = $0 { form.choose(folder) } })) {
                ForEach(form.rows) { row in
                    HStack {
                        Text(verbatim: row.name)
                        Spacer()
                        if let note = row.note { Text(verbatim: note).foregroundStyle(.secondary) }
                    }
                    .tag(row.name)
                    .accessibilityIdentifier(FormMarks.folder(row.name))
                }
            }
            .frame(height: 140)
        case .failed(let why):
            Text(verbatim: why).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func field(_ title: String, text: Binding<String>, help: String, isProblem: Bool, mark: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            plainField(title, text: text)
                .accessibilityIdentifier(mark)
            Text(verbatim: help).font(.caption).foregroundStyle(isProblem ? Color.red : Color.secondary)
                .accessibilityIdentifier(mark + ".help")
        }
    }

    private func readFolders() async {
        guard form.folders == .reading else { return }
        let listed = await forms.folders(for: form)
        form.folders = listed
    }

    private func save() {
        guard form.canSaveProjectsFolder, !saving else { return }
        let draft = form.projectsFolderToSave
        saving = true
        Task {
            defer { saving = false }
            if let problem = await forms.saveProjectsFolder(form.workhorseID, draft) {
                saveProblem = problem
                return
            }
            saveProblem = nil
            form.projectsFolderSaved(draft)
            await readFolders()
        }
    }

    /// Makes the desk. Started as a task of its own, so closing the window does not cut it short.
    private func make() {
        guard form.canMake, !making else { return }
        failure = nil
        let sent = form
        Task {
            switch await forms.newDesk(sent) {
            case .done: close()
            case .failed(let why): failure = why
            }
        }
    }
}

/// The Rename sheet (main window design, section 7.2): one field, "New name for <desk>", filled with the old
/// name; Rename and Cancel.
struct RenameSheet: View {
    @ObservedObject var forms: WindowActionRunner
    @State var form: RenameForm
    let close: () -> Void
    @State private var failure: String?

    private var renaming: Bool { forms.busy[form.workhorseID]?[form.desk] == .rename }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: form.title).font(.headline)
            Text(verbatim: form.label)
            plainField(form.label, text: $form.name)
                .frame(width: 320)
                .accessibilityIdentifier(FormMarks.newName)
            if let problem = form.problem {
                Text(verbatim: problem).font(.caption).foregroundStyle(.red)
                    .accessibilityIdentifier(FormMarks.newName + ".help")
            }
            HStack {
                Spacer()
                Button { close() } label: { Text(verbatim: RenameForm.Words.cancel) }
                    .keyboardShortcut(.cancelAction)
                    .disabled(renaming)
                    .accessibilityIdentifier(FormMarks.cancel)
                Button { rename() } label: { Text(verbatim: renaming ? RenameForm.Words.renaming : RenameForm.Words.rename) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!form.canRename || renaming)
                    .accessibilityIdentifier(FormMarks.renameButton)
            }
            if let failure {
                Text(verbatim: failure).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(FormMarks.failure)
            }
        }
        .padding(20)
        .interactiveDismissDisabled(renaming)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(FormMarks.rename)
    }

    private func rename() {
        guard form.canRename, !renaming else { return }
        failure = nil
        let sent = form
        Task {
            switch await forms.rename(sent) {
            case .done: close()
            case .failed(let why): failure = why
            }
        }
    }
}

/// The sheet that names one window of a desk (issue 144), drawn from `WindowNameForm`, which holds every rule and
/// word: the title, the label, one field filled with the window's name and selecting it, the rule or why the name
/// can't be used under it, and "Use its program's name", Cancel and Name (the default button). Controls: Button,
/// Text and TextField only. `WindowActionRunner.nameWindow` sends it.
struct WindowNameSheet: View {
    @ObservedObject var forms: WindowActionRunner
    @State var form: WindowNameForm
    let close: () -> Void
    @State private var failure: String?
    /// Apple, TextField.init(text:selection:prompt:axis:label:) (macOS 15.0,
    /// https://developer.apple.com/documentation/swiftui/textfield/init(text:selection:prompt:axis:label:)):
    /// "Creates a text field with a binding to the current selection"; TextSelection.init(range:) (macOS 15.0,
    /// https://developer.apple.com/documentation/swiftui/textselection/init(range:)): "Create a single selection
    /// with a given range."
    @State private var selection: TextSelection?
    /// Apple, FocusState (macOS 12.0, https://developer.apple.com/documentation/swiftui/focusstate): "A property
    /// wrapper type that can read and write a value that SwiftUI updates as the placement of focus within the scene
    /// changes."
    @FocusState private var fieldHasFocus: Bool

    private var naming: Bool { forms.busy[form.workhorseID]?[form.desk] == .nameWindow }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: form.title).font(.headline)
            Text(verbatim: form.label)
            TextField(text: $form.name, selection: $selection, prompt: Text(verbatim: "")) { Text(verbatim: form.label) }
                .labelsHidden()
                .frame(width: 320)
                .focused($fieldHasFocus)
                .disabled(naming)
                .accessibilityIdentifier(FormMarks.windowName)
            Text(verbatim: form.help).font(.caption)
                .foregroundStyle(form.helpIsProblem ? Color.red : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 320, alignment: .leading)
                .accessibilityIdentifier(FormMarks.windowName + ".help")
            HStack {
                Button { send(.afterItsProgram) } label: { Text(verbatim: WindowNameForm.Words.useProgramsName) }
                    .disabled(naming)
                    .accessibilityIdentifier(FormMarks.useProgramsName)
                Spacer()
                Button { close() } label: { Text(verbatim: WindowNameForm.Words.cancel) }
                    .keyboardShortcut(.cancelAction)
                    .disabled(naming)
                    .accessibilityIdentifier(FormMarks.cancel)
                Button { if let chosen = form.naming { send(chosen) } } label: {
                    Text(verbatim: naming ? WindowNameForm.Words.naming : WindowNameForm.Words.name)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!form.canName || naming)
                .accessibilityIdentifier(FormMarks.nameButton)
            }
            if let failure {
                Text(verbatim: failure).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                    .frame(width: 320, alignment: .leading)
                    .accessibilityIdentifier(FormMarks.failure)
            }
        }
        .padding(20)
        .interactiveDismissDisabled(naming)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(FormMarks.nameWindow)
        // The field takes the focus with its whole name selected, so typing replaces it.
        .task {
            fieldHasFocus = true
            await Task.yield()
            selection = TextSelection(range: form.name.startIndex..<form.name.endIndex)
        }
    }

    private func send(_ chosen: WindowNaming) {
        guard !naming else { return }
        failure = nil
        let sent = form
        Task {
            switch await forms.nameWindow(sent, to: chosen) {
            case .done: close()
            case .failed(let why): failure = why
            }
        }
    }
}

/// A text field with its label beside it already, so it shows no placeholder of its own (the design draws
/// empty fields); the label stays for accessibility. Apple, TextField.init(text:prompt:label:) (macOS 12.0,
/// https://developer.apple.com/documentation/swiftui/textfield/init(text:prompt:label:)): "prompt: A Text
/// representing the prompt of the text field which provides users with guidance on what to type into the
/// text field." "label: A view that describes the purpose of the text field."
fileprivate func plainField(_ title: String, text: Binding<String>) -> some View {
    TextField(text: text, prompt: Text(verbatim: "")) { Text(verbatim: title) }
        .labelsHidden()
}

/// Accessibility identifiers of the forms, for CI's driver only (scripts/ci/drive-window.sh).
enum FormMarks {
    static let newDesk = "form.newDesk"
    static let rename = "form.rename"
    static let path = "form.path"
    static let name = "form.name"
    static let command = "form.command"
    static let comesBack = "form.comesBack"
    static let whenItExits = "form.whenItExits"
    static let openInTab = "form.openInTab"
    static let cancel = "form.cancel"
    static let make = "form.make"
    static let failure = "form.failure"
    static let filter = "form.filter"
    static let projectsFolder = "form.projectsFolder"
    static let saveProjectsFolder = "form.saveProjectsFolder"
    static let newName = "form.newName"
    static let renameButton = "form.renameButton"
    static let nameWindow = "form.nameWindow"
    static let windowName = "form.windowName"
    static let useProgramsName = "form.useProgramsName"
    static let nameButton = "form.nameButton"
    static func folder(_ name: String) -> String { "form.folder.\(name)" }
}
