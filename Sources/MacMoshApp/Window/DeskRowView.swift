import MacMoshKit
import SwiftUI

/// A desk's row (look design 6.5), and its detail strip under it when it is open. From left to right: the chevron,
/// the desk's tile with a cell per window, the name with the window names beside it and the second line under them,
/// all one button that opens or closes the strip; then the state cell and Open or Go to, each an element of its own.
///
/// Equal when its row and whether it is open are: each check redraws the page, and a row that has not changed is
/// not drawn again (`.equatable()` where it is used). Apple, equatable() (macOS 10.15,
/// https://developer.apple.com/documentation/swiftui/view/equatable()): "Prevents the view from updating its child
/// view when its new value is the same as its old value."
struct DeskRowView: View, Equatable {
    let row: DeskRow
    let isOpen: Bool
    let run: (BoardButton) -> Void
    let toggle: () -> Void

    nonisolated static func == (a: DeskRowView, b: DeskRowView) -> Bool { a.row == b.row && a.isOpen == b.isOpen }

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
                                CappedWidth(cap: LookSize.nameMaxWidth) {
                                    Text(verbatim: row.name)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(LookColor.text(.primary, on: .ground))
                                        .lineLimit(1).truncationMode(.tail)
                                }
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
                // A hand-made desk's row says "Made by hand"; today's sentence, its tag's help, is the row's hint so
                // VoiceOver still reads why its folder is not shown. Apple, accessibilityHint(_:) (macOS 11.0,
                // https://developer.apple.com/documentation/swiftui/view/accessibilityhint(_:)): "Communicates to
                // the user what happens after performing the view's action."
                .accessibilityHint(Text(verbatim: row.secondLine.tag == nil ? "" : row.secondLine.help))
                .accessibilityIdentifier(WindowMarks.desk(row.name))
                StateCellView(state: row.state, name: row.name)
                // The trailing slot is never narrower than Open, so the state cells stay in one column on a row with
                // no button (a new desk before its check) or a shorter one. Apple, hidden() (macOS 10.15,
                // https://developer.apple.com/documentation/swiftui/view/hidden()): "Hidden views are invisible and
                // can't receive or respond to interactions. However, they do remain in the view hierarchy and affect
                // layout."
                ZStack(alignment: .trailing) {
                    Button {} label: { Text(verbatim: "Open") }
                        .buttonStyle(LookButtonStyle(kind: .secondary))
                        .hidden()
                        .accessibilityHidden(true)
                    if let open = row.open {
                        // "Go to" or "Open"; the menu's own words for the click ("Go to website", "Open the 1 window
                        // not in a tab") are its help tag. Apple, help(_:) (macOS 11.0,
                        // https://developer.apple.com/documentation/swiftui/view/help(_:)-9lm7l): "Adding help to a
                        // view configures the view's accessibility hint and its help tag (also called a tooltip) in
                        // macOS".
                        Button { run(open) } label: { Text(verbatim: open.title) }
                            .buttonStyle(LookButtonStyle(kind: ButtonKind.of(open.action)))
                            .disabled(!open.isEnabled)
                            .help(Text(verbatim: row.openWords ?? ""))
                            .accessibilityIdentifier(WindowMarks.open(row.name))
                    }
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

/// Its one view at its own width, but never wider than `cap`: a short name takes only its width, so the window
/// names follow it, and a long one is offered `cap` points and cut there. Apple, Layout (macOS 13.0,
/// https://developer.apple.com/documentation/swiftui/layout): "A type that defines the geometry of a collection of
/// views."
struct CappedWidth: Layout {
    let cap: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let view = subviews.first else { return .zero }
        return view.sizeThatFits(ProposedViewSize(width: min(proposal.width ?? cap, cap), height: proposal.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
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

    /// The line at each width of `SecondLine.widths`, longest first, each different one once.
    private var fittings: [String] {
        SecondLine.widths.map(line.fitted).reduce(into: [String]()) { if $0.last != $1 { $0.append($1) } }
    }

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
            // The last, shortest cut is not fixed to one line: when even it is too wide (both facts in a narrow
            // window) it wraps within the column instead of running under the state cell. Apple,
            // fixedSize(horizontal:vertical:) (macOS 10.15,
            // https://developer.apple.com/documentation/swiftui/view/fixedsize(horizontal:vertical:)): "Fixes this
            // view at its ideal size in the specified dimensions."
            ViewThatFits(in: .horizontal) {
                ForEach(Array(fittings.enumerated()), id: \.offset) { index, words in
                    if index == fittings.count - 1 {
                        Text(verbatim: words).fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(verbatim: words).lineLimit(1).fixedSize()
                    }
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
