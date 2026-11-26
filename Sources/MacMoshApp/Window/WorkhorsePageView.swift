import MacMoshKit
import SwiftUI

/// One workhorse's page (main window design, sections 7.1 A and D), drawn from `WorkhorsePage`: the
/// header, the buttons under the hint, the desks with their detail strips, the greyed list of the last
/// Ready check, and the rarer buttons at the foot. It decides nothing but which row's strip is open.
struct WorkhorsePageView: View {
    let page: WorkhorsePage
    let notice: String?
    let run: (BoardButton) -> Void
    /// The desk whose detail strip is open; one at a time.
    @State private var openRow: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                WorkhorseHeader(page: page, notice: notice, run: run)
                if !page.underHint.isEmpty {
                    ButtonRow(buttons: page.underHint, run: run)
                }
                if let heading = page.desksHeading {
                    desks(heading)
                }
                if let heading = page.endedHeading {
                    EndedList(heading: heading, rows: page.ended, run: run)
                }
                if let stale = page.stale {
                    StaleList(stale: stale)
                }
                Divider()
                foot
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // The ground behind the page shows through. Apple, scrollContentBackground(_:) (macOS 13.0,
        // https://developer.apple.com/documentation/swiftui/view/scrollcontentbackground(_:)): "Specifies the
        // visibility of the background for scrollable views within this view."
        .scrollContentBackground(.hidden)
    }

    private func desks(_ heading: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(verbatim: heading).font(.headline)
                Spacer()
                ButtonRow(buttons: page.deskButtons, run: run)
            }
            Divider()
            if let none = page.noDesks {
                Text(verbatim: none).foregroundStyle(.secondary)
            }
            ForEach(page.desks) { row in
                DeskRowView(row: row, isOpen: openRow == row.id, run: run) {
                    openRow = openRow == row.id ? nil : row.id
                }
            }
        }
    }

    /// The rarer buttons in the menu's order: all but the checklist on one line, then the checklist with
    /// the home-address line, as in the design's drawing.
    private var foot: some View {
        VStack(alignment: .leading, spacing: 8) {
            if page.foot.count > 1 {
                ButtonRow(buttons: Array(page.foot.dropLast()), run: run)
            }
            HStack(spacing: 12) {
                ButtonRow(buttons: Array(page.foot.suffix(1)), run: run)
                if let home = page.home {
                    Text(verbatim: home).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// A desk's short row, and its detail strip under it when it is open. A click on the row (not on its
/// Open button) opens or closes the strip.
struct DeskRowView: View {
    let row: DeskRow
    let isOpen: Bool
    let run: (BoardButton) -> Void
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 12) {
                // The row is a button, so a click, the keyboard and VoiceOver all open its strip. Apple,
                // onTapGesture(count:perform:) (https://developer.apple.com/documentation/swiftui/view/ontapgesture(count:perform:)):
                // "If you create a control that's functionally equivalent to a Button, use ButtonStyle to
                // create a customized button instead." Apple, PrimitiveButtonStyle.plain (macOS 10.15,
                // https://developer.apple.com/documentation/swiftui/primitivebuttonstyle/plain): "A button
                // style that doesn't style or decorate its content while idle". The chevron says it opens;
                // Image(systemName:) "Creates a system symbol image." (macOS 11.0,
                // https://developer.apple.com/documentation/swiftui/image/init(systemname:)).
                Button(action: { if row.hasStrip { toggle() } }) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        // No chevron on a row with nothing to open, such as a new desk before its check.
                        Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                            .font(.caption).foregroundStyle(.secondary).frame(width: 10)
                            .opacity(row.hasStrip ? 1 : 0)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 12) {
                                Text(verbatim: row.name).fontWeight(.semibold)
                                    .frame(width: 110, alignment: .leading)
                                Text(verbatim: row.windows).foregroundStyle(.secondary).lineLimit(1)
                            }
                            // Wraps rather than cutting: the facts after the folder are what the line is for.
                            // Apple, fixedSize(horizontal:vertical:) (https://developer.apple.com/documentation/swiftui/view/fixedsize(horizontal:vertical:)):
                            // "Fixes this view at its ideal size in the specified dimensions."
                            Text(verbatim: row.second).font(.callout).foregroundStyle(.secondary)
                                .padding(.leading, 122)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(WindowMarks.desk(row.name))
                // "Renaming…", "Removing…" or "Updating…" while the window's action on it runs, else its tabs.
                if let shown = row.status ?? row.tabs {
                    Text(verbatim: shown).foregroundStyle(.secondary)
                        .accessibilityIdentifier(WindowMarks.status(row.name))
                }
                if let open = row.open {
                    // "Go to" or "Open"; the menu's own words for the click ("Go to website", "Open the 1 window
                    // not in a tab") are its help tag. Apple, help(_:) (macOS 11.0,
                    // https://developer.apple.com/documentation/swiftui/view/help(_:)-9lm7l): "Adding help to a
                    // view configures the view's accessibility hint and its help tag (also called a tooltip) in macOS".
                    Button { run(open) } label: { Text(verbatim: open.title) }
                        .disabled(!open.isEnabled)
                        .help(Text(verbatim: row.openWords ?? ""))
                        .accessibilityIdentifier(WindowMarks.open(row.name))
                }
            }
            if isOpen && row.hasStrip {
                DeskDetail(row: row, run: run)
            }
            Divider()
        }
    }
}

/// The detail strip: one line per window when the desk has the menu's line per window (its words and a small
/// "Go to" or "Open" button) or its windows can be named (a small "Name…", issue 144), then Folder, Starts with,
/// After a restart, When its last shell exits, "Keeps its command running" when set, and New window, Name its
/// window… (a desk with one window), Rename…, Remove….
struct DeskDetail: View {
    let row: DeskRow
    let run: (BoardButton) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !row.windowLines.isEmpty {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 3) {
                    ForEach(row.windowLines) { line in
                        GridRow {
                            Text(verbatim: line.words)
                            // Apple, controlSize(_:) (macOS 10.15, https://developer.apple.com/documentation/swiftui/view/controlsize(_:)):
                            // "Sets the size for controls within this view."; ControlSize.small: "A control version
                            // that is proportionally smaller size for space-constrained views."
                            // The window's words are its help tag too, so the button's accessibility hint names
                            // its window (help(_:), quoted above).
                            HStack(spacing: 6) {
                                if let open = line.button {
                                    Button { run(open) } label: { Text(verbatim: open.title) }
                                        .controlSize(.small)
                                        .disabled(!open.isEnabled)
                                        .help(Text(verbatim: line.words))
                                        .accessibilityIdentifier(WindowMarks.window(row.name, line.id))
                                }
                                if let name = line.name {
                                    Button { run(name) } label: { Text(verbatim: name.title) }
                                        .controlSize(.small)
                                        .disabled(!name.isEnabled)
                                        .help(Text(verbatim: line.words))
                                        .accessibilityIdentifier(WindowMarks.nameWindow(row.name, line.id))
                                }
                            }
                        }
                    }
                }
                Divider()
            }
            if !row.detail.isEmpty {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 3) {
                    ForEach(Array(row.detail.enumerated()), id: \.offset) { _, line in
                        GridRow {
                            Text(verbatim: line.label).foregroundStyle(.secondary)
                            Text(verbatim: line.value)
                        }
                    }
                }
            }
            ForEach(Array(row.facts.enumerated()), id: \.offset) { _, fact in
                Text(verbatim: fact)
            }
            ButtonRow(buttons: row.detailButtons, run: run)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.1)))
        .padding(.leading, 122)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(WindowMarks.strip(row.name))
    }
}

/// The Ended group (step 5): one block per ended desk, with its name and when it ended, its folder and command on
/// one line, its buttons, and the note under them when there is one. Button and Text only.
struct EndedList: View {
    let heading: String
    let rows: [EndedRow]
    let run: (BoardButton) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: heading).font(.headline)
                .accessibilityIdentifier(WindowMarks.endedHeading)
            Divider()
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(verbatim: row.name).fontWeight(.semibold)
                            .frame(width: 110, alignment: .leading)
                        Text(verbatim: row.when).foregroundStyle(.secondary).lineLimit(1)
                            .accessibilityIdentifier(WindowMarks.ended(row.name, "when"))
                    }
                    .padding(.leading, 14)
                    // One line: a long command is cut on screen, never in what Start again sends. Apple,
                    // lineLimit(_:) (macOS 10.15, https://developer.apple.com/documentation/swiftui/view/linelimit(_:)-513mb):
                    // "Sets the maximum number of lines that text can occupy in this view." Apple, truncationMode(_:)
                    // (macOS 10.15, https://developer.apple.com/documentation/swiftui/view/truncationmode(_:)): "Sets the
                    // truncation mode for lines of text that are too long to fit in the available space."; Text.TruncationMode
                    // .tail: "Truncate at the end of the line."
                    Text(verbatim: row.second).font(.callout).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.tail)
                        .help(Text(verbatim: row.second))
                        .padding(.leading, 136)
                        .accessibilityIdentifier(WindowMarks.ended(row.name, "second"))
                    ButtonRow(buttons: row.buttons, run: run)
                        .padding(.leading, 136)
                    if let note = row.note {
                        Text(verbatim: note).font(.callout).fixedSize(horizontal: false, vertical: true)
                            .padding(.leading, 136)
                            .accessibilityIdentifier(WindowMarks.ended(row.name, "note"))
                    }
                    Divider()
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(WindowMarks.ended(row.name))
            }
        }
        .padding(.top, 8)
    }
}

/// The desks of the last Ready check under a workhorse that is not Ready, greyed, with no buttons.
struct StaleList: View {
    let stale: StaleDesks

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: stale.heading).font(.headline)
            ForEach(Array(stale.lines.enumerated()), id: \.offset) { _, line in
                Text(verbatim: line).fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(.secondary)
        .padding(.top, 8)
    }
}
