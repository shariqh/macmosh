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

    private var making: Bool { forms.making.contains(form.workhorseID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: form.title).font(.headline)
            folders
            HStack {
                Text(verbatim: NewDeskForm.Words.orAPath)
                TextField(NewDeskForm.Words.orAPath, text: Binding(get: { form.typedPath }, set: { form.setTypedPath($0) }))
                    .labelsHidden()
                    .accessibilityIdentifier(FormMarks.path)
            }
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
            Toggle(isOn: $form.openInTab) { Text(verbatim: NewDeskForm.Words.openInATabNow) }
                .toggleStyle(.checkbox)
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

    /// The folder list with its filter, the one line that saves a projects folder, or why the list can't be read.
    @ViewBuilder private var folders: some View {
        switch form.folders {
        case .noProjectsFolder:
            HStack {
                Text(verbatim: form.projectsFolderLine)
                TextField(form.projectsFolderLine, text: $form.projectsFolderDraft)
                    .labelsHidden()
                    .frame(width: 220)
                    .accessibilityIdentifier(FormMarks.projectsFolder)
                Button { save() } label: { Text(verbatim: NewDeskForm.Words.save) }
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
            TextField(title, text: text)
                .labelsHidden()
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
        let draft = form.projectsFolderDraft
        Task {
            if let problem = await forms.saveProjectsFolder(form.workhorseID, draft) {
                saveProblem = problem
                return
            }
            saveProblem = nil
            form.projectsFolderSaved(draft.trimmingCharacters(in: .whitespaces))
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
            TextField(form.label, text: $form.name)
                .labelsHidden()
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
    static func folder(_ name: String) -> String { "form.folder.\(name)" }
}
