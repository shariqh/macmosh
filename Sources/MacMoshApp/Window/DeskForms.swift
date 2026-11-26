import MacMoshKit
import SwiftUI

/// The New desk sheet (main window design, sections 7.1 B and 7.5), drawn from `NewDeskForm`, which holds every
/// rule and word; `WindowActionRunner` reads the folders, saves the projects folder and makes the desk.
///
/// Look step 4 (look design 6.8): the system's sheet on the look's ground, with the look's button styles (Make desk
/// primary, `FormButton`), labels level with their field's first line, help lines at 11 points in ink-3, refusals in
/// red words under their field, and "Choose a folder first." beside a Make desk that is off for want of a folder.
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
            sheetTitle(form.title)
            Group {
                folders
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        formLabel(NewDeskForm.Words.orAPath)
                        plainField(NewDeskForm.Words.orAPath,
                                   text: Binding(get: { form.typedPath }, set: { form.setTypedPath($0) }))
                            .accessibilityIdentifier(FormMarks.path)
                    }
                    // Why a typed path can't be used; nothing while the field is empty.
                    if let line = form.pathLine {
                        helpLine(line, isProblem: true)
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
            HStack(spacing: 8) {
                Spacer()
                // Why Make desk is off, only for want of a folder (look design 6.8); every other reason is the refusal
                // under its field. On Make desk's line, read by VoiceOver just before the two buttons.
                if let reason = form.makeReason {
                    Text(verbatim: reason)
                        .font(.system(size: LookSize.tagFont))
                        .foregroundStyle(LookColor.text(.tertiary, on: .ground))
                        .lineLimit(1)
                        .accessibilityIdentifier(FormMarks.makeReason)
                }
                Button { close() } label: { Text(verbatim: NewDeskForm.Words.cancel) }
                    .buttonStyle(LookButtonStyle(kind: FormButton.cancel.kind))
                    // Apple, KeyboardShortcut.cancelAction (macOS 11.0,
                    // https://developer.apple.com/documentation/swiftui/keyboardshortcut/cancelaction): "The standard
                    // keyboard shortcut for cancelling the in-progress action or dismissing a prompt, consisting of
                    // the Escape (⎋) key and no modifiers."
                    .keyboardShortcut(.cancelAction)
                    .disabled(making)
                    .accessibilityIdentifier(FormMarks.cancel)
                Button { make() } label: { Text(verbatim: making ? NewDeskForm.Words.making : NewDeskForm.Words.makeDesk) }
                    .buttonStyle(LookButtonStyle(kind: FormButton.makeDesk.kind))
                    // Apple, KeyboardShortcut.defaultAction (macOS 11.0,
                    // https://developer.apple.com/documentation/swiftui/keyboardshortcut/defaultaction): "The standard
                    // keyboard shortcut for the default button, consisting of the Return (↩) key and no modifiers."
                    .keyboardShortcut(.defaultAction)
                    .disabled(!form.canMake || making)
                    .accessibilityIdentifier(FormMarks.make)
            }
            if let failure {
                failureLine(failure)
            }
        }
        .padding(20)
        .frame(width: 560)
        .lookSheetGround()
        // Apple, interactiveDismissDisabled(_:) (macOS 12.0,
        // https://developer.apple.com/documentation/swiftui/view/interactivedismissdisabled(_:)): "Conditionally
        // prevents interactive dismissal of presentations like popovers, sheets, and inspectors."
        .interactiveDismissDisabled(making)
        // A container, so its fields keep their own identifiers (as the detail strip does).
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(FormMarks.newDesk)
        .task { await readFolders() }
    }

    /// Name, First window, Command to start, After a restart, and When its last shell exits.
    private var fields: some View {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow(alignment: .firstTextBaseline) {
                    formLabel(NewDeskForm.Words.name)
                    field(NewDeskForm.Words.name, text: Binding(get: { form.name }, set: { form.setName($0) }),
                          help: form.nameLine, isProblem: form.nameLineIsProblem,
                          mark: FormMarks.name)
                }
                // The first window's name (issue 163), hidden for a script older than 0.12.0. A checkbox Toggle, and a
                // field with its line while the box is clear; NewDeskForm decides what is sent. Every label sits level
                // with its field's first line, not with the middle of the column (look design 6.8). Apple,
                // GridRow.init(alignment:content:) (macOS 13.0,
                // https://developer.apple.com/documentation/swiftui/gridrow/init(alignment:content:)): "Creates a
                // horizontal row of child views in a grid." Apple, VerticalAlignment.firstTextBaseline (macOS 10.15,
                // https://developer.apple.com/documentation/swiftui/verticalalignment/firsttextbaseline): "A guide
                // that marks the top-most text baseline in a view."
                if form.canNameFirstWindow {
                    GridRow(alignment: .firstTextBaseline) {
                        formLabel(NewDeskForm.Words.firstWindow)
                        VStack(alignment: .leading, spacing: 4) {
                            Toggle(isOn: $form.windowSameAsDesk) { Text(verbatim: NewDeskForm.Words.sameAsDesk) }
                                .toggleStyle(.checkbox)
                                .accessibilityIdentifier(FormMarks.sameAsDesk)
                            if let line = form.firstWindowLine {
                                field(NewDeskForm.Words.firstWindow, text: $form.windowName,
                                      help: line, isProblem: form.firstWindowLineIsProblem,
                                      mark: FormMarks.firstWindowName)
                            }
                        }
                    }
                }
                GridRow(alignment: .firstTextBaseline) {
                    formLabel(NewDeskForm.Words.command)
                    field(NewDeskForm.Words.command, text: $form.command,
                          help: form.commandLine, isProblem: form.commandLineIsProblem,
                          mark: FormMarks.command)
                }
                GridRow(alignment: .firstTextBaseline) {
                    formLabel(NewDeskForm.Words.afterARestart)
                    Toggle(isOn: $form.comesBack) { Text(verbatim: NewDeskForm.Words.comesBack) }
                        .toggleStyle(.checkbox)
                        .accessibilityIdentifier(FormMarks.comesBack)
                }
                // Hidden for a script older than 0.5.0 (section 7.2).
                if form.canKeepClosed {
                    GridRow(alignment: .firstTextBaseline) {
                        formLabel(NewDeskForm.Words.whenItsLastShellExits)
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
            HStack(alignment: .firstTextBaseline) {
                formLabel(form.projectsFolderLine)
                plainField(form.projectsFolderLine, text: $form.projectsFolderDraft)
                    .frame(width: 220)
                    // Return in this field saves, since Make desk (the default button) is off here. Apple,
                    // TextField.init(text:prompt:label:) (https://developer.apple.com/documentation/swiftui/textfield/init(text:prompt:label:)):
                    // "Use the onSubmit(of:_:) modifier to invoke an action whenever the user submits this text field."
                    .onSubmit { save() }
                    .accessibilityIdentifier(FormMarks.projectsFolder)
                Button { save() } label: { Text(verbatim: NewDeskForm.Words.save) }
                    .buttonStyle(LookButtonStyle(kind: FormButton.save.kind))
                    .disabled(!form.canSaveProjectsFolder || saving)
                    .accessibilityIdentifier(FormMarks.saveProjectsFolder)
            }
            if let saveProblem {
                helpLine(saveProblem, isProblem: true)
            }
        case .reading:
            formLabel(form.folderHeading)
            Text(verbatim: NewDeskForm.Words.reading).foregroundStyle(LookColor.text(.secondary, on: .ground))
        case .listed:
            HStack(alignment: .firstTextBaseline) {
                formLabel(form.folderHeading)
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
            Text(verbatim: why).foregroundStyle(LookColor.text(.secondary, on: .ground))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func field(_ title: String, text: Binding<String>, help: String, isProblem: Bool, mark: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            plainField(title, text: text)
                .accessibilityIdentifier(mark)
            helpLine(help, isProblem: isProblem)
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
            sheetTitle(form.title)
            formLabel(form.label)
            plainField(form.label, text: $form.name)
                .frame(width: 320)
                .accessibilityIdentifier(FormMarks.newName)
            if let problem = form.problem {
                helpLine(problem, isProblem: true)
                    .accessibilityIdentifier(FormMarks.newName + ".help")
            }
            HStack(spacing: 8) {
                Spacer()
                Button { close() } label: { Text(verbatim: RenameForm.Words.cancel) }
                    .buttonStyle(LookButtonStyle(kind: FormButton.cancel.kind))
                    .keyboardShortcut(.cancelAction)
                    .disabled(renaming)
                    .accessibilityIdentifier(FormMarks.cancel)
                Button { rename() } label: { Text(verbatim: renaming ? RenameForm.Words.renaming : RenameForm.Words.rename) }
                    .buttonStyle(LookButtonStyle(kind: FormButton.rename.kind))
                    .keyboardShortcut(.defaultAction)
                    .disabled(!form.canRename || renaming)
                    .accessibilityIdentifier(FormMarks.renameButton)
            }
            if let failure {
                failureLine(failure)
            }
        }
        .padding(20)
        .lookSheetGround()
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
/// can't be used under it, and "Name it after the program running in it", Cancel and Name (the default button, the
/// sheet's primary one). Controls: Button, Text and TextField only. `WindowActionRunner.nameWindow` sends it.
struct WindowNameSheet: View {
    @ObservedObject var forms: WindowActionRunner
    @State var form: WindowNameForm
    let close: () -> Void
    @State private var failure: String?
    /// Apple, TextField.init(_:text:selection:prompt:axis:) with a title that is a `StringProtocol` (macOS 15.0,
    /// https://developer.apple.com/documentation/swiftui/textfield/init(_:text:selection:prompt:axis:)-80y12):
    /// "Creates a text field with a binding to the current selection and a text label generated from a title
    /// string." (The form with a label closure is not in Xcode 16.4's SDK: the macos-15 runner refused it.)
    /// TextSelection.init(range:) (macOS 15.0,
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
            sheetTitle(form.title)
            formLabel(form.label)
            TextField(form.label, text: $form.name, selection: $selection, prompt: Text(verbatim: ""))
                .labelsHidden()
                .frame(width: 320)
                .focused($fieldHasFocus)
                .disabled(naming)
                .accessibilityIdentifier(FormMarks.windowName)
            helpLine(form.help, isProblem: form.helpIsProblem)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 320, alignment: .leading)
                .accessibilityIdentifier(FormMarks.windowName + ".help")
            HStack(spacing: 8) {
                Button { send(.afterItsProgram) } label: { Text(verbatim: WindowNameForm.Words.useProgramsName) }
                    .buttonStyle(LookButtonStyle(kind: FormButton.nameAfterProgram.kind))
                    .disabled(naming)
                    .accessibilityIdentifier(FormMarks.useProgramsName)
                Spacer()
                Button { close() } label: { Text(verbatim: WindowNameForm.Words.cancel) }
                    .buttonStyle(LookButtonStyle(kind: FormButton.cancel.kind))
                    .keyboardShortcut(.cancelAction)
                    .disabled(naming)
                    .accessibilityIdentifier(FormMarks.cancel)
                Button { if let chosen = form.naming { send(chosen) } } label: {
                    Text(verbatim: naming ? WindowNameForm.Words.naming : WindowNameForm.Words.name)
                }
                .buttonStyle(LookButtonStyle(kind: FormButton.name.kind))
                .keyboardShortcut(.defaultAction)
                .disabled(!form.canName || naming)
                .accessibilityIdentifier(FormMarks.nameButton)
            }
            if let failure {
                failureLine(failure)
                    .frame(width: 320, alignment: .leading)
            }
        }
        .padding(20)
        .lookSheetGround()
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

/// A sheet's title: 13 points semibold, in ink on the ground (look design 5.2 and 6.8).
fileprivate func sheetTitle(_ words: String) -> some View {
    Text(verbatim: words)
        .font(.system(size: LookSize.bodyFont, weight: .semibold))
        .foregroundStyle(LookColor.text(.primary, on: .ground))
}

/// A field's label, in ink on the ground.
fileprivate func formLabel(_ words: String) -> some View {
    Text(verbatim: words).foregroundStyle(LookColor.text(.primary, on: .ground))
}

/// A line under a field (look design 6.8): its help at 11 points in ink-3, or why it can't be used in red words.
fileprivate func helpLine(_ words: String, isProblem: Bool) -> some View {
    Text(verbatim: words)
        .font(.system(size: LookSize.tagFont))
        .foregroundStyle(LookColor.text(isProblem ? .cannot : .tertiary, on: .ground))
}

/// Why the last try didn't work, in red words under the buttons; the sheet stays open with it.
fileprivate func failureLine(_ words: String) -> some View {
    Text(verbatim: words)
        .font(.system(size: LookSize.bodyFont))
        .foregroundStyle(LookColor.text(.cannot, on: .ground))
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier(FormMarks.failure)
}

extension View {
    /// The sheet stays the system's; only its background becomes the look's ground, so every word sits on a background
    /// the pairs table knows (look step 4, decision 4). Apple, presentationBackground(_:) (macOS 13.3,
    /// https://developer.apple.com/documentation/swiftui/view/presentationbackground(_:)): "Sets the presentation
    /// background of the enclosing sheet using a shape style." and "Sheet presentations on macOS do not support
    /// translucency or transparency — the background is always opaque."
    fileprivate func lookSheetGround() -> some View {
        presentationBackground(LookColor.background(.ground))
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
    static let sameAsDesk = "form.sameAsDesk"
    static let firstWindowName = "form.firstWindowName"
    static let whenItExits = "form.whenItExits"
    static let openInTab = "form.openInTab"
    static let cancel = "form.cancel"
    static let make = "form.make"
    /// "Choose a folder first." beside Make desk (look step 4).
    static let makeReason = "form.make.reason"
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
