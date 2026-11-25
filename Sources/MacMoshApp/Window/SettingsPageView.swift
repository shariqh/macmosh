import MacMoshKit
import SwiftUI

/// The Settings page (main window design, section 7.1 F, issue 157), drawn from `SettingsPage`, which holds every
/// word and rule; `SettingsRunner` saves. This decides nothing but which Advanced parts are open.
///
/// Controls: Text, TextField, Button, and Pickers in the radio-group style only, each naming its style, because the
/// default style on macOS is a pop-up button, which is a menu and would set off the menu-open signal (design,
/// section 7.2). Apple, PickerStyle.automatic (https://developer.apple.com/documentation/swiftui/pickerstyle/automatic):
/// "On macOS, the default is a pop-up button." Apple, PickerStyle.radioGroup (macOS 10.15,
/// https://developer.apple.com/documentation/swiftui/pickerstyle/radiogroup): "A picker style that presents the
/// options as a group of radio buttons." Apple, horizontalRadioGroupLayout() (macOS 10.15,
/// https://developer.apple.com/documentation/swiftui/view/horizontalradiogrouplayout()): "Sets the style for radio
/// group style pickers within this view to be horizontally positioned with the radio buttons inside the layout."
/// Advanced opens with a plain button, not a menu.
struct SettingsPageView: View {
    @ObservedObject var settings: SettingsRunner
    /// Runs a tab button the way the menu runs its line (`MainWindow.run`).
    let run: (BoardButton) -> Void
    /// The workhorses whose Advanced part is open. Closed by default, and again when the window opens.
    @State private var advanced: Set<String> = []

    var body: some View {
        let page = settings.page
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(verbatim: page.heading).font(.title2).bold()
                    .accessibilityIdentifier(SettingsMarks.heading)
                ForEach(Array(page.notices.enumerated()), id: \.offset) { _, notice in
                    Text(verbatim: notice).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier(SettingsMarks.notice)
                }
                thisMac(page.thisMac)
                if let none = page.none {
                    Divider()
                    Text(verbatim: none).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier(SettingsMarks.none)
                }
                ForEach(page.workhorses) { section in
                    Divider()
                    WorkhorseSettingsView(settings: settings, section: section, advancedOpen: advanced.contains(section.id),
                                          toggleAdvanced: { toggle(section.id) }, run: run)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Each opening shows what is saved now. The "Saved." lines of earlier changes go; a refusal stays under its
        // field, and a refused key file opens Advanced so its sentence is seen (`WorkhorseSettings.opensAdvanced`).
        .onAppear {
            let settings = settings
            Task {
                await settings.reload(clearingLines: true)
                advanced.formUnion(settings.page.workhorses.filter(\.opensAdvanced).map(\.id))
            }
        }
    }

    private func thisMac(_ section: ThisMacSettings) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: section.heading).font(.headline)
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    SettingLabel(section.label)
                    VStack(alignment: .leading, spacing: 4) {
                        ChoiceGroup(label: section.label, choices: section.choices, chosen: section.chosen,
                                    mark: SettingsMarks.terminal) { value in
                            let settings = settings
                            Task { await settings.chooseTerminal(value) }
                        }
                        Text(verbatim: section.pickLine).font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier(SettingsMarks.pickForMe)
                        LineView(line: section.line, mark: SettingsMarks.line(SettingsPage.thisMacID, .terminal))
                    }
                }
            }
        }
    }

    private func toggle(_ id: String) {
        if advanced.contains(id) { advanced.remove(id) } else { advanced.insert(id) }
    }
}

/// One workhorse's section: Name, Connection, Typing prediction, Projects folder, Advanced with the ssh key file,
/// and the two buttons that open today's terminal tabs.
struct WorkhorseSettingsView: View {
    @ObservedObject var settings: SettingsRunner
    let section: WorkhorseSettings
    let advancedOpen: Bool
    let toggleAdvanced: () -> Void
    let run: (BoardButton) -> Void

    var body: some View {
        let id = section.id
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: section.heading).font(.headline)
                .accessibilityIdentifier(SettingsMarks.heading(id))
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    SettingLabel(SettingsWords.name)
                    VStack(alignment: .leading, spacing: 3) {
                        SettingTextField(settings: settings, id: id, field: .name, title: SettingsWords.name,
                                         stored: section.name)
                        LineView(line: section.under(.name), mark: SettingsMarks.line(id, .name))
                    }
                }
                GridRow {
                    SettingLabel(SettingsWords.connection)
                    VStack(alignment: .leading, spacing: 3) {
                        ChoiceGroup(label: SettingsWords.connection, choices: section.connectionChoices,
                                    chosen: section.connection, mark: SettingsMarks.field(id, .connection)) { value in
                            save(.connection, value)
                        }
                        Text(verbatim: section.connectionLine).font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier(SettingsMarks.about(id, .connection))
                        LineView(line: section.under(.connection), mark: SettingsMarks.line(id, .connection))
                    }
                }
                GridRow {
                    SettingLabel(SettingsWords.prediction)
                    VStack(alignment: .leading, spacing: 3) {
                        ChoiceGroup(label: SettingsWords.prediction, choices: section.predictionChoices,
                                    chosen: section.prediction, mark: SettingsMarks.field(id, .prediction)) { value in
                            save(.prediction, value)
                        }
                        Text(verbatim: section.predictionLine).font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier(SettingsMarks.about(id, .prediction))
                        LineView(line: section.under(.prediction), mark: SettingsMarks.line(id, .prediction))
                    }
                }
                GridRow {
                    SettingLabel(SettingsWords.projectsFolder)
                    VStack(alignment: .leading, spacing: 3) {
                        SettingTextField(settings: settings, id: id, field: .projectsFolder,
                                         title: SettingsWords.projectsFolder, stored: section.projectsFolder)
                        LineView(line: section.under(.projectsFolder), mark: SettingsMarks.line(id, .projectsFolder))
                    }
                }
            }
            Button(action: toggleAdvanced) {
                HStack(spacing: 4) {
                    Image(systemName: advancedOpen ? "chevron.down" : "chevron.right")
                    Text(verbatim: SettingsWords.advanced)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(SettingsMarks.advanced(id))
            if advancedOpen {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 6) {
                    GridRow {
                        SettingLabel(SettingsWords.keyFile)
                        VStack(alignment: .leading, spacing: 3) {
                            SettingTextField(settings: settings, id: id, field: .keyFile, title: SettingsWords.keyFile,
                                             stored: section.keyFile)
                            Text(verbatim: section.keyFileHelp).font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            LineView(line: section.under(.keyFile), mark: SettingsMarks.line(id, .keyFile))
                        }
                    }
                }
            }
            HStack(spacing: 8) {
                Button { run(section.checklist) } label: { Text(verbatim: section.checklist.title) }
                    .accessibilityIdentifier(SettingsMarks.checklist(id))
                Button { run(section.remove) } label: { Text(verbatim: section.remove.title) }
                    .accessibilityIdentifier(SettingsMarks.remove(id))
            }
            .padding(.top, 4)
        }
        // A container, so its controls keep their own identifiers.
        .accessibilityElement(children: .contain)
    }

    private func save(_ field: SettingField, _ value: String) {
        let settings = settings, id = section.id
        Task { await settings.save(field, of: id, typed: value) }
    }
}

/// A setting's name, in the page's first column.
struct SettingLabel: View {
    let words: String
    init(_ words: String) { self.words = words }

    var body: some View {
        Text(verbatim: words).frame(width: 130, alignment: .leading)
    }
}

/// A radio group for one choice, in its style by name (never the default pop-up).
struct ChoiceGroup: View {
    let label: String
    let choices: [SettingChoice]
    /// nil: no choice is shown as chosen (the settings file can't be read).
    let chosen: String?
    let mark: String
    let choose: (String) -> Void

    var body: some View {
        Picker(selection: Binding(get: { chosen ?? "" }, set: { choose($0) })) {
            ForEach(choices) { choice in
                Text(verbatim: choice.title).tag(choice.value)
            }
        } label: {
            Text(verbatim: label)
        }
        .pickerStyle(.radioGroup)
        .horizontalRadioGroupLayout()
        .labelsHidden()
        .accessibilityIdentifier(mark)
    }
}

/// A setting's text field: saved, through `SettingsRunner` and its checks, when Return is pressed or the field is
/// left, and only when its text differs from what it showed (`shown`) and from what is stored. After each save or
/// refusal it shows what is stored: a refused value is not left in the field as if it were saved. When the page goes
/// away (another sidebar line, or the window closed), focus leaves the field, so text typed and not yet sent is sent
/// then, through the same checks; CI saw this on macOS 15 and 26. On a Mac where focus did not leave, nothing would
/// be saved, and the next opening shows what is stored.
///
/// Apple, View.onSubmit(of:_:) (macOS 12.0, https://developer.apple.com/documentation/swiftui/view/onsubmit(of:_:)):
/// "A TextField, or SecureField will trigger this action when the user hits the hardware or software return key."
/// Apple, FocusState (macOS 12.0, https://developer.apple.com/documentation/swiftui/focusstate): "when focus leaves,
/// the wrapped value of this property resets to nil or false." Apple, onChange(of:initial:_:) (macOS 14.0,
/// https://developer.apple.com/documentation/swiftui/view/onchange(of:initial:_:)): "Adds a modifier for this view
/// that fires an action when a specific value changes."
struct SettingTextField: View {
    @ObservedObject var settings: SettingsRunner
    let id: String
    let field: SettingField
    let title: String
    let stored: String
    @State private var draft: String
    /// What the field showed before the person typed: text equal to it is sent as no change.
    @State private var base: String
    @FocusState private var focused: Bool

    init(settings: SettingsRunner, id: String, field: SettingField, title: String, stored: String) {
        self.settings = settings
        self.id = id
        self.field = field
        self.title = title
        self.stored = stored
        _draft = State(initialValue: stored)
        _base = State(initialValue: stored)
    }

    var body: some View {
        TextField(text: $draft, prompt: Text(verbatim: "")) { Text(verbatim: title) }
            .labelsHidden()
            .frame(maxWidth: 340)
            .focused($focused)
            .onSubmit { send() }
            .onChange(of: focused) { _, now in
                if !now { send() }
            }
            .onChange(of: stored) { _, now in
                if !focused {
                    draft = now
                    base = now
                }
            }
            .accessibilityIdentifier(SettingsMarks.field(id, field))
    }

    private func send() {
        let settings = settings, id = id, field = field, typed = draft, shown = base
        Task {
            await settings.save(field, of: id, typed: typed, shown: shown)
            draft = settings.stored(field, of: id)
            base = draft
        }
    }
}

/// The grey line under a setting, or the red sentence when nothing was saved.
struct LineView: View {
    let line: SettingLine?
    let mark: String

    var body: some View {
        if let line {
            Text(verbatim: line.words).font(.caption)
                .foregroundStyle(line.isProblem ? Color.red : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(mark)
        }
    }
}

/// Accessibility identifiers of the Settings page, for CI's driver only (scripts/ci/drive-window.sh).
enum SettingsMarks {
    static let heading = "settings.heading"
    static let notice = "settings.notice"
    static let none = "settings.none"
    static let terminal = "settings.thisMac.terminal"
    static let pickForMe = "settings.thisMac.pickForMe"
    static func heading(_ id: String) -> String { "settings.\(id).heading" }
    /// A setting's control: `settings.attic.name`, `settings.attic.connection`.
    static func field(_ id: String, _ field: SettingField) -> String { "settings.\(id).\(field.rawValue)" }
    /// The line about the chosen connection or prediction: `settings.attic.connection.about`.
    static func about(_ id: String, _ field: SettingField) -> String { "settings.\(id).\(field.rawValue).about" }
    /// The line of the last change: `settings.attic.name.line`, `settings.thisMac.terminal.line`.
    static func line(_ id: String, _ field: SettingField) -> String { "settings.\(id).\(field.rawValue).line" }
    static func advanced(_ id: String) -> String { "settings.\(id).advanced" }
    static func checklist(_ id: String) -> String { "settings.\(id).checklist" }
    static func remove(_ id: String) -> String { "settings.\(id).remove" }
}
