import MacMoshKit
import SwiftUI

/// The Add a Mac page (look design 6.10, look-b-add-a-mac.png): a tile with a small M beside the title, the first line,
/// the two settings as a numbered card with each setting's name in semibold, the closing paragraph in ink-2 and the
/// menu's Add a Mac… button, primary with its plus. The words are today's (`AddMacPage.standard`). Under the text, the
/// dotted mountain sits at the page's lower right, flush with the window's edges: its region starts under the text, so
/// it can never sit behind it, and when the page is too short its top is cut first.
///
/// Apple, clipped(antialiased:) (macOS 10.15, https://developer.apple.com/documentation/swiftui/view/clipped(antialiased:)):
/// "Clips this view to its bounding rectangular frame." and "By default, a view's bounding frame is used only for
/// layout, so any content that extends beyond the edges of the frame is still visible." Apple,
/// overlay(alignment:content:) (macOS 12.0, https://developer.apple.com/documentation/swiftui/view/overlay(alignment:content:)):
/// "Layers the views that you specify in front of this view."
struct AddMacPageView: View {
    let page: AddMacPage
    let notice: String?
    let run: (BoardButton) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    LetterMTile()
                    Text(verbatim: page.heading)
                        .font(.system(size: LookSize.titleFont, weight: .semibold))
                        .foregroundStyle(LookColor.text(.primary, on: .ground))
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier(WindowMarks.addMac)
                }
                NoticeLine(notice: notice)
                Text(verbatim: page.intro)
                    .foregroundStyle(LookColor.text(.primary, on: .ground))
                    .fixedSize(horizontal: false, vertical: true)
                card
                Text(verbatim: page.closing)
                    .font(.system(size: LookSize.secondFont))
                    .foregroundStyle(LookColor.text(.secondary, on: .ground))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 470, alignment: .leading)
                ButtonRow(buttons: [page.button], run: run)
            }
            .padding(LookSize.pagePadding)
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .bottomTrailing) { MountainArtView() }
                .clipped()
        }
        .font(.system(size: LookSize.bodyFont))
    }

    /// The two settings, a row each with its number on a small grey tile, a hairline between them. Each setting's
    /// sentence is one static text (`page.addMac.step.1`), its name in semibold; the numbers are hidden from VoiceOver.
    /// Apple, LocalizedStringKey.StringInterpolation.appendInterpolation(_:) for a Text (macOS 11.0,
    /// https://developer.apple.com/documentation/swiftui/localizedstringkey/stringinterpolation/appendinterpolation(_:)-4qyfo):
    /// "Appends the string displayed by a text view to a string interpolation." It replaces Text's `+`, which Apple
    /// deprecates in macOS 26.0: "Use string interpolation on `Text` instead"
    /// (https://developer.apple.com/documentation/swiftui/text/+(_:_:)).
    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(page.steps.enumerated()), id: \.offset) { index, step in
                if index > 0 {
                    Rectangle().fill(LookColor.mark(.hairline)).frame(height: 1).accessibilityHidden(true)
                }
                HStack(spacing: 12) {
                    Text(verbatim: "\(step.number)")
                        .foregroundStyle(LookColor.text(.tertiary, on: .surface2))
                        .frame(width: LookSize.smallTile, height: LookSize.smallTile)
                        .background(RoundedRectangle(cornerRadius: LookSize.smallTileRadius, style: .continuous)
                            .fill(LookColor.background(.surface2)))
                        .accessibilityHidden(true)
                    Text("\(Text(verbatim: step.name).fontWeight(.semibold))\(Text(verbatim: step.rest))")
                        .foregroundStyle(LookColor.text(.primary, on: .surface))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier(WindowMarks.addMacStep(step.number))
                    Spacer(minLength: 0)
                }
                .padding(12)
            }
        }
        .frame(maxWidth: 470, alignment: .leading)
        .lookTile(radius: LookSize.panelRadius)
    }
}

/// The icon's M (look design 8.1) in a desk-sized tile: 5 by 5 cells, lit in ember where `LetterM` says, clay elsewhere.
/// Decoration, hidden from VoiceOver.
struct LetterMTile: View {
    var body: some View {
        VStack(spacing: LookSize.mCellGap) {
            ForEach(0..<LetterM.size, id: \.self) { row in
                HStack(spacing: LookSize.mCellGap) {
                    ForEach(0..<LetterM.size, id: \.self) { column in
                        RoundedRectangle(cornerRadius: LookSize.mCellRadius, style: .continuous)
                            .fill(LookColor.mark(LetterM.isLit(row: row, column: column) ? .ember : .clayCell))
                            .frame(width: LookSize.mCell, height: LookSize.mCell)
                    }
                }
            }
        }
        .frame(width: LookSize.deskTile, height: LookSize.deskTile)
        .lookTile(radius: LookSize.deskTileRadius)
        .accessibilityHidden(true)
    }
}

/// The dotted mountain (look design 6.10), drawn from `MountainArt`'s table of dots at `LookSize.mountainScale`: one
/// filled path per strength, each in the clay art colour at that strength's opacity. Decoration, hidden from VoiceOver.
///
/// Apple, Canvas (macOS 12.0, https://developer.apple.com/documentation/swiftui/canvas): "A view type that supports
/// immediate mode drawing." and "A canvas doesn't offer interactivity or accessibility for individual elements".
/// Apple, GraphicsContext.fill(_:with:style:)
/// (https://developer.apple.com/documentation/swiftui/graphicscontext/fill(_:with:style:)): "Draws a path into the
/// context and fills the outlined region."
struct MountainArtView: View {
    var body: some View {
        let scale: Double = LookSize.mountainScale
        Canvas { context, _ in
            for strength in MountainArt.strengths.indices {
                var path = Path()
                for dot in MountainArt.dots where dot.strength == strength {
                    let r: Double = dot.radius * scale
                    let x: Double = dot.x * scale - r
                    let y: Double = dot.y * scale - r
                    path.addEllipse(in: CGRect(x: x, y: y, width: 2 * r, height: 2 * r))
                }
                let opacity: Double = MountainArt.strengths[strength]
                context.fill(path, with: .color(LookColor.mark(.clayArt).opacity(opacity)))
            }
        }
        .frame(width: MountainArt.width * scale, height: MountainArt.height * scale)
        .accessibilityHidden(true)
    }
}
