import Foundation
import Testing
@testable import MacMoshKit

/// What CI runs to picture the menu bar (look step 6, issue 183), pinned as `AppBundleTests` pins the icon's scripts.
@Suite struct MenuBarPicturesTests {
    func file(_ path: String) throws -> String {
        try String(contentsOf: repoRoot().appendingPathComponent(path), encoding: .utf8) }

    /// Look step 6: CI pictures the menu bar in light and dark, every sample in Task 2's order.
    @Test func ciPicturesTheMenuBarInLightAndDark() throws {
        #expect(try file("scripts/check.sh").contains("shellcheck scripts/ci/drive-menu-bar.sh"))
        let flow = try file(".github/workflows/menu-pictures.yml")
        let steps = flow.components(separatedBy: "      - name: ")
        let light = try #require(steps.first { $0.hasPrefix("Picture the menu bar\n") })
        let dark = try #require(steps.first { $0.hasPrefix("Picture the menu bar in dark\n") })
        #expect(light.contains("MENU_BAR_APPEARANCE: light") && dark.contains("MENU_BAR_APPEARANCE: dark"))
        #expect(light.contains("run: scripts/ci/drive-menu-bar.sh") && dark.contains("run: scripts/ci/drive-menu-bar.sh"))
        let driver = try file("scripts/ci/drive-menu-bar.sh")
        #expect(driver.contains("samples=\"six-desks sign-ins-off waiting-for-login locked unreadable-list cant-reach not-set-up still-checking no-workhorses\""))
        let ax = try file("scripts/ci/menu-ax.applescript")   // the AX attribute, never System Events' description
        #expect(ax.contains("value of attribute \"AXDescription\"") && ax.contains("barinfo pos="))
    }
}
