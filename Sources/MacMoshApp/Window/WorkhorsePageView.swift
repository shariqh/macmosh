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
                // Under the desks the last row's line is enough; otherwise a line sets the foot apart.
                if page.desksHeading == nil || page.desks.isEmpty || page.endedHeading != nil || page.stale != nil {
                    Hairline()
                }
                PageFoot(left: page.footLeft, right: page.footRight, home: page.home, run: run)
                    .equatable()
            }
            .padding(LookSize.pagePadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // The ground behind the page shows through. Apple, scrollContentBackground(_:) (macOS 13.0,
        // https://developer.apple.com/documentation/swiftui/view/scrollcontentbackground(_:)): "Specifies the
        // visibility of the background for scrollable views within this view."
        .scrollContentBackground(.hidden)
    }

    private func desks(_ heading: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(verbatim: heading)
                    .font(.system(size: LookSize.bodyFont, weight: .semibold))
                    .foregroundStyle(LookColor.text(.primary, on: .ground))
                Spacer()
                ButtonRow(buttons: page.deskButtons, run: run)
            }
            .padding(.bottom, 8)
            Hairline()
            if let none = page.noDesks {
                Text(verbatim: none)
                    .foregroundStyle(LookColor.text(.secondary, on: .ground))
                    .padding(.vertical, 8)
            }
            ForEach(page.desks) { row in
                DeskRowView(row: row, isOpen: openRow == row.id, run: run) {
                    openRow = openRow == row.id ? nil : row.id
                }
                .equatable()
            }
        }
    }

}

/// The rarer buttons (look design 6.4): Share screen, the lid-closed button and Run the checklist… at the left,
/// Restart… alone at the right, and the home-address line under them. When the page is too narrow for one line,
/// Restart… moves to a line of its own, still at the right, and then the left buttons take two lines. Equal when its
/// buttons and line are, so a check that changes none of them does not draw it again.
struct PageFoot: View, Equatable {
    let left: [BoardButton]
    let right: BoardButton?
    let home: String?
    let run: (BoardButton) -> Void

    nonisolated static func == (a: PageFoot, b: PageFoot) -> Bool { a.left == b.left && a.right == b.right && a.home == b.home }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    ButtonRow(buttons: left, run: run)
                    Spacer(minLength: 16)
                    restart
                }
                VStack(alignment: .leading, spacing: 8) {
                    ButtonRow(buttons: left, run: run)
                    HStack { Spacer(minLength: 0); restart }
                }
                VStack(alignment: .leading, spacing: 8) {
                    ButtonRow(buttons: Array(left.dropLast()), run: run)
                    HStack(spacing: 8) {
                        ButtonRow(buttons: Array(left.suffix(1)), run: run)
                        Spacer(minLength: 16)
                        restart
                    }
                }
            }
            if let home {
                Text(verbatim: home)
                    .foregroundStyle(LookColor.text(.tertiary, on: .ground))
            }
        }
        .font(.system(size: LookSize.bodyFont))
    }

    @ViewBuilder private var restart: some View {
        if let right {
            ButtonRow(buttons: [right], run: run)
        }
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
