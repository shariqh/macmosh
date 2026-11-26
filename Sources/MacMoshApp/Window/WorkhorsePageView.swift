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

/// The Ended group (step 5, look design 6.7): the heading as the Desks heading, then each ended desk in the desk row's
/// parts: the chevron's place left empty, a tile with one hollow cell, the name with when it ended beside it, the folder
/// and command on one cut line, then Start again and Start again and keep it at the left and Forget alone at the right,
/// and the note under them when there is one. Button and Text only.
struct EndedList: View {
    let heading: String
    let rows: [EndedRow]
    let run: (BoardButton) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: heading)
                .font(.system(size: LookSize.bodyFont, weight: .semibold))
                .foregroundStyle(LookColor.text(.primary, on: .ground))
                .accessibilityIdentifier(WindowMarks.endedHeading)
                .padding(.bottom, 8)
            Hairline()
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: 12) {
                        // The chevron's place: an ended desk has no details to open.
                        Color.clear.frame(width: 10, height: 1).accessibilityHidden(true)
                        DeskTileView(cells: EndedRow.cells)
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                CappedWidth(cap: LookSize.nameMaxWidth) {
                                    Text(verbatim: row.name)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(LookColor.text(.primary, on: .ground))
                                        .lineLimit(1).truncationMode(.tail)
                                }
                                .help(Text(verbatim: row.name))
                                .layoutPriority(1)
                                Text(verbatim: row.when)
                                    .foregroundStyle(LookColor.text(.secondary, on: .ground))
                                    .lineLimit(1)
                                    .accessibilityIdentifier(WindowMarks.ended(row.name, "when"))
                            }
                            // One line: a long command is cut on screen, never in what Start again sends. Apple,
                            // lineLimit(_:) (macOS 10.15, https://developer.apple.com/documentation/swiftui/view/linelimit(_:)-513mb):
                            // "Sets the maximum number of lines that text can occupy in this view." Apple,
                            // truncationMode(_:) (macOS 10.15, https://developer.apple.com/documentation/swiftui/view/truncationmode(_:)):
                            // "Sets the truncation mode for lines of text that are too long to fit in the available
                            // space."; Text.TruncationMode.tail: "Truncate at the end of the line."
                            Text(verbatim: row.second)
                                .font(.system(size: LookSize.secondFont))
                                .foregroundStyle(LookColor.text(.tertiary, on: .ground))
                                .lineLimit(1).truncationMode(.tail)
                                .help(Text(verbatim: row.second))
                                .accessibilityIdentifier(WindowMarks.ended(row.name, "second"))
                            buttons(row)
                                .padding(.top, 2)
                            if let note = row.note {
                                Text(verbatim: note)
                                    .foregroundStyle(LookColor.text(.secondary, on: .ground))
                                    .fixedSize(horizontal: false, vertical: true)
                                    .accessibilityIdentifier(WindowMarks.ended(row.name, "note"))
                            }
                        }
                    }
                    .font(.system(size: LookSize.bodyFont))
                    .padding(.vertical, 8)
                    Hairline()
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(WindowMarks.ended(row.name))
            }
        }
        .padding(.top, 8)
    }

    /// Start again and Start again and keep it at the left, Forget alone at the right. With keep it, what kept means
    /// (issue 156 item 2): beside the buttons when the row has room, under them when it does not (look step 4,
    /// decision 5). Apple, ViewThatFits (macOS 13.0, https://developer.apple.com/documentation/swiftui/viewthatfits):
    /// "A view that adapts to the available space by providing the first child view that fits."
    @ViewBuilder private func buttons(_ row: EndedRow) -> some View {
        if let keepHelp = row.keepHelp {
            ViewThatFits(in: .horizontal) {
                buttonLine(row, beside: keepLine(keepHelp, row))
                VStack(alignment: .leading, spacing: 4) {
                    buttonLine(row, beside: EmptyView())
                    keepLine(keepHelp, row)
                }
            }
        } else {
            buttonLine(row, beside: EmptyView())
        }
    }

    private func buttonLine(_ row: EndedRow, beside: some View) -> some View {
        HStack(spacing: 8) {
            ButtonRow(buttons: row.split.left, run: run)
            beside
            Spacer(minLength: 24)
            if let right = row.split.right {
                ButtonRow(buttons: [right], run: run)
            }
        }
    }

    private func keepLine(_ words: String, _ row: EndedRow) -> some View {
        Text(verbatim: words)
            .font(.system(size: LookSize.secondFont))
            .foregroundStyle(LookColor.text(.tertiary, on: .ground))
            .lineLimit(1)
            .accessibilityIdentifier(WindowMarks.ended(row.name, "keepHelp"))
    }
}

/// The desks of the last Ready check under a workhorse that is not Ready (look design 6.7): in a surface-2 panel, the
/// heading and the lines in the faintest grey, with no buttons.
struct StaleList: View {
    let stale: StaleDesks

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: stale.heading)
                .fontWeight(.semibold)
            ForEach(Array(stale.lines.enumerated()), id: \.offset) { _, line in
                Text(verbatim: line).fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.system(size: LookSize.bodyFont))
        .foregroundStyle(LookColor.text(.tertiary, on: .surface2))
        .padding(LookSize.panelPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lookPanel()
        .padding(.top, 8)
    }
}
