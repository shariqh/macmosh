import Foundation
import Testing
@testable import MacMoshKit

/// The About section at the end of Settings (look design 6.9 and 13, look step 5b): the app's name and version, the
/// licence, and the two credit lines the v1 design fixes (v1 design, section 11), word for word.
@Suite struct AboutSectionTests {
    private func page(_ list: [Workhorse], listProblem: String? = nil) -> SettingsPage {
        SettingsPage(list: list, listProblem: listProblem, settings: AppSettings(), settingsProblem: nil,
                     pickForMe: .iterm2, lines: [:])
    }

    @Test func theAboutLinesAreExact() {
        let about = AboutSection()
        #expect(about.heading == "About")
        #expect(about.name == "MacMosh")
        #expect(about.version == "Version " + MacMoshInfo.version)
        #expect(about.licence == "Open source under the MIT licence.")
        #expect(about.credits == [
            "Mac and macOS are trademarks of Apple Inc., registered in the U.S. and other countries and regions.",
            "MacMosh is an independent project, not affiliated with Apple or with the mosh project.",
        ])
    }

    @Test func theVersionLineTakesTheNumberItIsGiven() {
        #expect(AboutSection(version: "1.2.3").version == "Version 1.2.3")
    }

    /// Two workhorses; none; a list that can't be read: About is there each time.
    @Test func everySettingsPageEndsWithAbout() {
        let attic = Workhorse.sample(id: "attic", name: "Attic")
        let spare = Workhorse.sample(id: "spare", name: "Spare")
        #expect(page([attic, spare]).about == AboutSection())
        #expect(page([]).about == AboutSection())
        #expect(page([], listProblem: "Can't read MacMosh's saved settings: workhorses.json: not JSON").about
                == AboutSection())
    }
}
