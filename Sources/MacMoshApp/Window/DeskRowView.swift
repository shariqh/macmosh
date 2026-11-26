import MacMoshKit
import SwiftUI

/// A desk's row (look design 6.5), and its detail strip under it when it is open. From left to right: the chevron,
/// the desk's tile with a cell per window, the name with the window names beside it and the second line under them,
/// all one button that opens or closes the strip; then the state cell and Open or Go to, each an element of its own.
struct DeskRowView: View {
    let row: DeskRow
    let isOpen: Bool
    let run: (BoardButton) -> Void
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                // The row is a button, so a click, the keyboard and VoiceOver all open its strip. Apple,
                // onTapGesture(count:perform:) (https://developer.apple.com/documentation/swiftui/view/ontapgesture(count:perform:)):
                // "If you create a control that's functionally equivalent to a Button, use ButtonStyle to
                // create a customized button instead." Apple, PrimitiveButtonStyle.plain (macOS 10.15,
                // https://developer.apple.com/documentation/swiftui/primitivebuttonstyle/plain): "A button
                // style that doesn't style or decorate its content while idle". Its label for VoiceOver and CI is
                // the row's spoken label: the name, the window names, the second line, then the state's words.
                Button(action: { if row.hasStrip { toggle() } }) {
                    HStack(alignment: .center, spacing: 12) {
                        // No chevron on a row with nothing to open, such as a new desk before its check.
                        Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(LookColor.mark(.ink3))
                            .frame(width: 10)
                            .opacity(row.hasStrip ? 1 : 0)
                            .accessibilityHidden(true)
                        DeskTileView(cells: row.cells)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                // Never wraps: whole up to 200 points, cut with "…" beyond, the whole name as help tag.
                                Text(verbatim: row.name)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(LookColor.text(.primary, on: .ground))
                                    .lineLimit(1).truncationMode(.tail)
                                    .frame(maxWidth: LookSize.nameMaxWidth, alignment: .leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .help(Text(verbatim: row.name))
                                    .layoutPriority(1)
                                // The window names give way first.
                                Text(verbatim: row.windowWords)
                                    .foregroundStyle(LookColor.text(.secondary, on: .ground))
                                    .lineLimit(1).truncationMode(.tail)
                            }
                            SecondLineView(line: row.secondLine)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: row.spokenLabel))
                .accessibilityIdentifier(WindowMarks.desk(row.name))
                StateCellView(state: row.state, name: row.name)
                if let open = row.open {
                    // "Go to" or "Open"; the menu's own words for the click ("Go to website", "Open the 1 window
                    // not in a tab") are its help tag. Apple, help(_:) (macOS 11.0,
                    // https://developer.apple.com/documentation/swiftui/view/help(_:)-9lm7l): "Adding help to a
                    // view configures the view's accessibility hint and its help tag (also called a tooltip) in macOS".
                    Button { run(open) } label: { Text(verbatim: open.title) }
                        .buttonStyle(LookButtonStyle(kind: ButtonKind.of(open.action)))
                        .disabled(!open.isEnabled)
                        .help(Text(verbatim: row.openWords ?? ""))
                        .accessibilityIdentifier(WindowMarks.open(row.name))
                }
            }
            .font(.system(size: LookSize.bodyFont))
            .padding(.vertical, 6)
            .frame(minHeight: LookSize.rowHeight)
            if isOpen && row.hasStrip {
                DeskDetail(row: row, run: run)
                    .padding(.bottom, 8)
            }
            Hairline()
        }
    }
}

/// A line one point high in the hairline colour, under a row or a heading.
struct Hairline: View {
    var body: some View {
        Rectangle().fill(LookColor.mark(.hairline)).frame(height: 1).accessibilityHidden(true)
    }
}

/// The desk's 40-point tile: up to six cells in rows of three, lit (ember) for a window in a tab, unlit (clay) for one
/// that is not, a hollow cell for a closed desk, and a small plus after five when there are more. Decoration only:
/// the state cell's words say the same, so it is hidden from VoiceOver.
struct DeskTileView: View {
    let cells: DeskCells

    var body: some View {
        let marks = cells.cells.map { Optional($0) } + (cells.more ? [nil] : [])
        let rows = stride(from: 0, to: marks.count, by: 3).map { Array(marks[$0..<min($0 + 3, marks.count)]) }
        VStack(spacing: LookSize.cellGap) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: LookSize.cellGap) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        CellView(cell: cell)
                    }
                }
            }
        }
        .frame(width: LookSize.deskTile, height: LookSize.deskTile)
        .lookTile(radius: LookSize.deskTileRadius)
        .accessibilityHidden(true)
    }
}

/// One cell, or the small plus when `cell` is nil.
private struct CellView: View {
    let cell: DeskCell?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: LookSize.cellRadius, style: .continuous)
        Group {
            switch cell {
            case .lit: shape.fill(LookColor.mark(.ember))
            case .unlit: shape.fill(LookColor.mark(.clayCell))
            case .hollow: shape.strokeBorder(LookColor.mark(.clayOutline), lineWidth: 1)
            case nil:
                Image(systemName: "plus")
                    .font(.system(size: 6, weight: .bold))
                    .foregroundStyle(LookColor.mark(.clayOutline))
            }
        }
        .frame(width: LookSize.cell, height: LookSize.cell)
    }
}

/// Under the name: the "Made by hand" tag, or the folder and its facts on one line, the folder cut in the middle when
/// the line is too long so the facts always stay (`SecondLine.fitted`). The whole line, or today's sentence for the
/// tag, is the help tag.
///
/// Apple, ViewThatFits (macOS 13.0, https://developer.apple.com/documentation/swiftui/viewthatfits): "A view that
/// adapts to the available space by providing the first child view that fits." and "It selects the first child whose
/// ideal size on the constrained axes fits within the proposed size."
struct SecondLineView: View {
    let line: SecondLine

    var body: some View {
        if let tag = line.tag {
            Text(verbatim: tag)
                .font(.system(size: LookSize.tagFont))
                .foregroundStyle(LookColor.text(.secondary, on: .surface))
                .lineLimit(1).fixedSize()
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background {
                    let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
                    shape.fill(LookColor.background(.surface))
                        .overlay(shape.strokeBorder(LookColor.mark(.hairline), lineWidth: LookSize.ringWidth))
                }
                .help(Text(verbatim: line.help))
        } else if !line.whole.isEmpty {
            ViewThatFits(in: .horizontal) {
                ForEach(Array(SecondLine.widths.enumerated()), id: \.offset) { _, width in
                    Text(verbatim: line.fitted(width)).lineLimit(1).fixedSize()
                }
            }
            .font(.system(size: LookSize.secondFont))
            .foregroundStyle(LookColor.text(.tertiary, on: .ground))
            .help(Text(verbatim: line.help))
        }
    }
}

/// The row's state, 92 points wide: a mark (hidden from VoiceOver) and the words, which carry `desk.<name>.status`
/// so its value is the word alone: "In 2 tabs", "No tab", "Closed", "Updating…".
struct StateCellView: View {
    let state: DeskStateCell
    let name: String

    var body: some View {
        HStack(spacing: 5) {
            mark
            Text(verbatim: state.word)
                .foregroundStyle(LookColor.text(state.kind.textRole, on: .ground))
                .lineLimit(1)
                .accessibilityIdentifier(WindowMarks.status(name))
        }
        .frame(width: LookSize.stateCellWidth, alignment: .leading)
    }

    @ViewBuilder private var mark: some View {
        switch state.kind {
        case .inTabs:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(LookColor.mark(.green)).accessibilityHidden(true)
        case .noTab:
            Image(systemName: "circle").foregroundStyle(LookColor.mark(.ink2)).accessibilityHidden(true)
        case .closed:
            Image(systemName: "minus.circle").foregroundStyle(LookColor.mark(.ink2)).accessibilityHidden(true)
        case .busy:
            EmptyView()
        }
    }
}
