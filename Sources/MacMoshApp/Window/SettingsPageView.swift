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
///
/// Look step 4 (look design 6.9): on the ground, one soft panel per Mac and one for This Mac, each with its name as
/// the panel's heading; "Each change is saved as you make it." under the page's heading; a green tick before
/// "Saved."; Run the checklist… secondary, and Remove MacMosh from this workhorse… last in its panel in red words with
/// its grey line. Apple, AccessibilityTraits.isHeader (macOS 10.15,
/// https://developer.apple.com/documentation/swiftui/accessibilitytraits/isheader): "The accessibility element is a
/// header that divides content into sections, like the title of a navigation bar."
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
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: page.heading)
                        .font(.system(size: LookSize.titleFont, weight: .semibold))
                        .foregroundStyle(LookColor.text(.primary, on: .ground))
                        .accessibilityIdentifier(SettingsMarks.heading)
                    Text(verbatim: page.howSaved)
                        .font(.system(size: LookSize.secondFont))
                        .foregroundStyle(LookColor.text(.tertiary, on: .ground))
                        .accessibilityIdentifier(SettingsMarks.howSaved)
                }
                ForEach(Array(page.notices.enumerated()), id: \.offset) { _, notice in
                    Text(verbatim: notice).foregroundStyle(LookColor.text(.cannot, on: .ground))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier(SettingsMarks.notice)
                }
                thisMac(page.thisMac)
                if let none = page.none {
                    Text(verbatim: none).foregroundStyle(LookColor.text(.secondary, on: .ground))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier(SettingsMarks.none)
                }
                ForEach(page.workhorses) { section in
                    WorkhorseSettingsView(settings: settings, section: section, advancedOpen: advanced.contains(section.id),
                                          toggleAdvanced: { toggle(section.id) }, run: run)
                }
            }
            .font(.system(size: LookSize.bodyFont))
            .padding(LookSize.pagePadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // The ground behind the page shows through, as on a workhorse's page. Apple, scrollContentBackground(_:) (macOS
        // 13.0, https://developer.apple.com/documentation/swiftui/view/scrollcontentbackground(_:)): "Specifies the
        // visibility of the background for scrollable views within this view."
        .scrollContentBackground(.hidden)
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
        SettingsPanel(heading: section.heading, mark: nil) {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    SettingLabel(section.label)
                    VStack(alignment: .leading, spacing: 4) {
                        ChoiceGroup(label: section.label, choices: section.choices, chosen: section.chosen,
                                    mark: SettingsMarks.terminal) { value in
                            let settings = settings
                            Task { await settings.chooseTerminal(value) }
                        }
                        AboutLine(words: section.pickLine)
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
        SettingsPanel(heading: section.heading, mark: SettingsMarks.heading(id)) {
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
                        AboutLine(words: section.connectionLine)
                            .accessibilityIdentifier(SettingsMarks.about(id, .connection))
                        // Only while it is on Tabs and this Mac opens tabs in Terminal (issue 160 item 2).
                        if let note = section.connectionNote {
                            AboutLine(words: note)
                                .accessibilityIdentifier(SettingsMarks.inTerminal(id))
                        }
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
                        AboutLine(words: section.predictionLine)
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
                        .foregroundStyle(LookColor.text(.tertiary, on: .surface))
                    Text(verbatim: SettingsWords.advanced)
                        .foregroundStyle(LookColor.text(.primary, on: .surface))
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
                            AboutLine(words: section.keyFileHelp)
                            LineView(line: section.under(.keyFile), mark: SettingsMarks.line(id, .keyFile))
                        }
                    }
                }
            }
            Button { run(section.checklist) } label: { Text(verbatim: section.checklist.title) }
                .buttonStyle(LookButtonStyle(kind: ButtonKind.of(section.checklist.action)))
                .accessibilityIdentifier(SettingsMarks.checklist(id))
                .padding(.top, 4)
            // Last in the panel, on its own line, in red words, with what it opens under it (issue 160 item 1).
            VStack(alignment: .leading, spacing: 4) {
                Button { run(section.remove) } label: { Text(verbatim: section.remove.title) }
                    .buttonStyle(LookButtonStyle(kind: ButtonKind.of(section.remove.action)))
                    .accessibilityIdentifier(SettingsMarks.remove(id))
                AboutLine(words: section.removeHelp)
                    .accessibilityIdentifier(SettingsMarks.removeAbout(id))
            }
            .padding(.top, 8)
        }
    }

    private func save(_ field: SettingField, _ value: String) {
        let settings = settings, id = section.id
        Task { await settings.save(field, of: id, typed: value) }
    }
}

/// One soft panel (look design 6.9): a surface tile with corners of 12, its name as the heading, read as a header.
struct SettingsPanel<Content: View>: View {
    let heading: String
    /// The heading's identifier; This Mac's has none.
    let mark: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            title
            content
        }
        .padding(LookSize.panelPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lookTile(radius: LookSize.panelRadius)
        // A container, so its controls keep their own identifiers.
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var title: some View {
        let text = Text(verbatim: heading)
            .font(.system(size: LookSize.bodyFont, weight: .semibold))
            .foregroundStyle(LookColor.text(.primary, on: .surface))
            .accessibilityAddTraits(.isHeader)
        if let mark { text.accessibilityIdentifier(mark) } else { text }
    }
}

/// A grey line about a setting, in a panel: 11 points in ink-3 on the surface.
struct AboutLine: View {
    let words: String

    var body: some View {
        Text(verbatim: words)
            .font(.system(size: LookSize.tagFont))
            .foregroundStyle(LookColor.text(.tertiary, on: .surface))
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A setting's name, in the panel's first column.
struct SettingLabel: View {
    let words: String
    init(_ words: String) { self.words = words }

    var body: some View {
        Text(verbatim: words)
            .foregroundStyle(LookColor.text(.primary, on: .surface))
            .frame(width: 130, alignment: .leading)
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
/// refusal it shows what is stored: a refused value is not left in the field as if it were saved. When another
/// sidebar line is chosen, focus leaves the field, so text typed and not yet sent is sent then, through the same
/// checks. When the window is closed it is not sent at once: on the CI runners (macOS 15 and 26) it was sent when
/// the window was opened again and the field lost focus, and it is not saved while the window stays closed.
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

/// The grey line under a setting, with a small green tick before "Saved." (look design 6.9), or the red sentence
/// when nothing was saved. The identifier is on the words alone, so its value stays the words.
struct LineView: View {
    let line: SettingLine?
    let mark: String

    var body: some View {
        if let line {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if line.showsTick {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: LookSize.tagFont))
                        .foregroundStyle(LookColor.mark(.green))
                        .accessibilityHidden(true)
                }
                Text(verbatim: line.words)
                    .font(.system(size: LookSize.tagFont))
                    .foregroundStyle(LookColor.text(line.isProblem ? .cannot : .tertiary, on: .surface))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(mark)
            }
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
    /// "Each change is saved as you make it." under the heading (look step 4).
    static let howSaved = "settings.howSaved"
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
    /// The line under Connection while tabs open in Terminal: `settings.spare.connection.inTerminal` (look step 4).
    static func inTerminal(_ id: String) -> String { "settings.\(id).connection.inTerminal" }
    /// The grey line under Remove MacMosh from this workhorse…: `settings.attic.remove.about` (look step 4).
    static func removeAbout(_ id: String) -> String { "settings.\(id).remove.about" }
}
