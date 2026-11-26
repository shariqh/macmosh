import MacMoshKit
import SwiftUI

/// The page for a saved list that can't be read (look design 6.7): a heading, the menu's own sentence, then what
/// happens next, in place of an invitation to add a Mac. No pill, since it shows no workhorse. Every word is
/// `ListProblemPage`'s.
struct UnreadableListPageView: View {
    let page: ListProblemPage

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Apple, AccessibilityTraits.isHeader (macOS 10.15, https://developer.apple.com/documentation/swiftui/accessibilitytraits/isheader):
            // "The accessibility element is a header that divides content into sections, like the title of a navigation bar."
            Text(verbatim: page.heading)
                .font(.system(size: LookSize.titleFont, weight: .semibold))
                .foregroundStyle(LookColor.text(.primary, on: .ground))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(WindowMarks.listProblemHeading)
            Text(verbatim: page.problem)
                .foregroundStyle(LookColor.text(.primary, on: .ground))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(WindowMarks.listProblem)
            Text(verbatim: page.nextStep)
                .foregroundStyle(LookColor.text(.secondary, on: .ground))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(WindowMarks.listProblemNext)
        }
        .font(.system(size: LookSize.bodyFont))
        .padding(LookSize.pagePadding)
    }
}
