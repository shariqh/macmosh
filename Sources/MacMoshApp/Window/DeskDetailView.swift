import MacMoshKit
import SwiftUI

/// A desk's opened details (look design 6.6): an inset panel in surface-2 under the row, starting under the desk's
/// tile. Inside, one line per window (its cell, its name, its state's words, and the small Go to or Open and Name…)
/// beside the facts (Starts with, After a restart, When its last shell exits, "Keeps its command running"), or the
/// facts under the lines in a narrow page; under a hairline, New window, Name its window… and Rename… at the left and
/// Remove… alone at the right. Every button inside the panel is small.
///
/// The panel is a group whose children keep their own elements (`.contain`), so each button keeps its identifier and
/// each window's name and state are static texts of their own.
struct DeskDetail: View {
    let row: DeskRow
    let run: (BoardButton) -> Void

    var body: some View {
        let split = row.detailSplit
        let hasLines = !row.windowLines.isEmpty
        let hasFacts = !(row.detail.isEmpty && row.facts.isEmpty)
        let hasFoot = !split.left.isEmpty || split.right != nil
        VStack(alignment: .leading, spacing: 10) {
            if hasLines && hasFacts {
                DetailColumns(stackBelow: LookSize.detailsStackBelowColumnsWidth) {
                    lines
                    Rectangle().fill(LookColor.mark(.hairline)).accessibilityHidden(true)
                    facts
                }
            } else if hasLines {
                lines
            } else if hasFacts {
                facts
            }
            if (hasLines || hasFacts) && hasFoot {
                Hairline()
            }
            if hasFoot {
                HStack(spacing: 8) {
                    ButtonRow(buttons: split.left, small: true, run: run)
                    Spacer(minLength: 16)
                    if let right = split.right {
                        ButtonRow(buttons: [right], small: true, run: run)
                    }
                }
            }
        }
        .padding(LookSize.panelPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lookPanel()
        // Under the desk's tile: the chevron's 10 points and the row's 12-point gap.
        .padding(.leading, LookSize.detailsInset)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(WindowMarks.strip(row.name))
    }

    /// One line per window, in a grid so the names, the states and the buttons each stand in a column.
    private var lines: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
            ForEach(row.windowLines) { line in
                WindowLineRow(desk: row.name, line: line, run: run)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(WindowMarks.lines(row.name))
    }

    /// The facts as a two-column list, labels in the faintest grey, values in ink, each on one line with its whole
    /// value as its help tag; then "Keeps its command running" when it is set.
    private var facts: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !row.detail.isEmpty {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                    ForEach(Array(row.detail.enumerated()), id: \.offset) { _, fact in
                        GridRow {
                            Text(verbatim: fact.label)
                                .foregroundStyle(LookColor.text(.tertiary, on: .surface2))
                                .lineLimit(1)
                            Text(verbatim: fact.value)
                                .foregroundStyle(LookColor.text(.primary, on: .surface2))
                                .lineLimit(1).truncationMode(.tail)
                                .help(Text(verbatim: fact.value))
                        }
                    }
                }
            }
            ForEach(Array(row.facts.enumerated()), id: \.offset) { _, fact in
                Text(verbatim: fact)
                    .foregroundStyle(LookColor.text(.primary, on: .surface2))
                    .lineLimit(1)
            }
        }
        .font(.system(size: LookSize.secondFont))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(WindowMarks.facts(row.name))
    }
}

/// One window's line: its cell (hidden from VoiceOver), its name, its state's words in green or the faintest grey,
/// then the small Go to or Open and Name…. Without the menu's facts (an older script, the Tabs connection) the name
/// stands alone and the cell's place stays empty. The menu's whole line is the buttons' help tag, so the button's
/// accessibility hint names its window.
struct WindowLineRow: View {
    let desk: String
    let line: WindowLine
    let run: (BoardButton) -> Void

    var body: some View {
        GridRow {
            Group {
                // Not `CellView(cell: nil)`, which draws the tile's small plus.
                if let cell = line.cell {
                    CellView(cell: cell)
                } else {
                    Color.clear.frame(width: LookSize.cell, height: LookSize.cell)
                }
            }
            .accessibilityHidden(true)
            Text(verbatim: line.title)
                .foregroundStyle(LookColor.text(.primary, on: .surface2))
                .lineLimit(1).truncationMode(.tail)
                .accessibilityIdentifier(WindowMarks.windowLine(desk, line.id))
            if let state = line.state {
                Text(verbatim: state.words)
                    .font(.system(size: LookSize.secondFont))
                    .foregroundStyle(LookColor.text(state.textRole, on: .surface2))
                    .lineLimit(1)
                    .accessibilityIdentifier(WindowMarks.windowState(desk, line.id))
            } else {
                Color.clear.frame(width: 0, height: 0).accessibilityHidden(true)
            }
            HStack(spacing: 6) {
                if let open = line.button {
                    Button { run(open) } label: { Text(verbatim: open.title) }
                        .buttonStyle(LookButtonStyle(kind: ButtonKind.of(open.action), small: true))
                        .disabled(!open.isEnabled)
                        .help(Text(verbatim: line.help))
                        .accessibilityIdentifier(WindowMarks.window(desk, line.id))
                }
                if let name = line.name {
                    Button { run(name) } label: { Text(verbatim: name.title) }
                        .buttonStyle(LookButtonStyle(kind: ButtonKind.of(name.action), small: true))
                        .disabled(!name.isEnabled)
                        .help(Text(verbatim: line.help))
                        .accessibilityIdentifier(WindowMarks.nameWindow(desk, line.id))
                }
            }
        }
    }
}

/// The window lines, a hairline, and the facts: side by side when it is offered at least `stackBelow` points (the
/// lines at their own width, the hairline one point wide and as tall as the taller column, the facts in the rest),
/// one under the other below that, the hairline then one point high across. Three subviews, in that order.
///
/// Apple, Layout (macOS 13.0, https://developer.apple.com/documentation/swiftui/layout): "A type that defines the
/// geometry of a collection of views."
struct DetailColumns: Layout {
    let stackBelow: CGFloat
    /// Between each column and the hairline.
    private let gap: CGFloat = 12

    private func beside(_ width: CGFloat?) -> Bool {
        guard let width, width.isFinite else { return true }
        return width >= stackBelow
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 3 else { return .zero }
        let (lines, facts) = (subviews[0], subviews[2])
        if beside(proposal.width) {
            let l = lines.sizeThatFits(.unspecified)
            if let width = proposal.width, width.isFinite {
                let rest = max(width - min(l.width, width) - 2 * gap - 1, 0)
                let f = facts.sizeThatFits(ProposedViewSize(width: rest, height: nil))
                return CGSize(width: width, height: max(l.height, f.height))
            }
            let f = facts.sizeThatFits(.unspecified)
            return CGSize(width: l.width + 2 * gap + 1 + f.width, height: max(l.height, f.height))
        }
        let width = proposal.width ?? 0
        let l = lines.sizeThatFits(ProposedViewSize(width: width, height: nil))
        let f = facts.sizeThatFits(ProposedViewSize(width: width, height: nil))
        return CGSize(width: width, height: l.height + 2 * gap + 1 + f.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 3 else { return }
        let (lines, hairline, facts) = (subviews[0], subviews[1], subviews[2])
        if beside(bounds.width) {
            let lw = min(lines.sizeThatFits(.unspecified).width, bounds.width)
            lines.place(at: bounds.origin, proposal: ProposedViewSize(width: lw, height: nil))
            hairline.place(at: CGPoint(x: bounds.minX + lw + gap, y: bounds.minY),
                           proposal: ProposedViewSize(width: 1, height: bounds.height))
            let fx = bounds.minX + lw + 2 * gap + 1
            facts.place(at: CGPoint(x: fx, y: bounds.minY), proposal: ProposedViewSize(width: max(bounds.maxX - fx, 0), height: nil))
        } else {
            let across = ProposedViewSize(width: bounds.width, height: nil)
            let l = lines.sizeThatFits(across)
            lines.place(at: bounds.origin, proposal: across)
            hairline.place(at: CGPoint(x: bounds.minX, y: bounds.minY + l.height + gap),
                           proposal: ProposedViewSize(width: bounds.width, height: 1))
            facts.place(at: CGPoint(x: bounds.minX, y: bounds.minY + l.height + 2 * gap + 1), proposal: across)
        }
    }
}

/// A panel (look design 6.6 and 6.7): surface-2 with corners of `LookSize.panelRadius` and a one-point hairline ring,
/// no shadow. The opened details and the greyed list sit in one.
struct LookPanel: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: LookSize.panelRadius, style: .continuous)
        content.background {
            shape.fill(LookColor.background(.surface2))
                .overlay(shape.strokeBorder(LookColor.mark(.hairline), lineWidth: LookSize.ringWidth))
        }
    }
}

extension View {
    func lookPanel() -> some View { modifier(LookPanel()) }
}
