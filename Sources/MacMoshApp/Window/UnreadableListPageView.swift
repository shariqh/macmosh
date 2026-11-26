import MacMoshKit
import SwiftUI

/// The page for a saved list that can't be read: the menu's own sentence, in place of an invitation to add a Mac.
/// Look step 2 gives it a heading and a next step (look design 6.7); in step 1 it is today's page in a file of its own.
struct UnreadableListPageView: View {
    let problem: String

    var body: some View {
        Text(verbatim: problem)
            .fixedSize(horizontal: false, vertical: true)
            .padding(20)
            .accessibilityIdentifier(WindowMarks.listProblem)
    }
}
