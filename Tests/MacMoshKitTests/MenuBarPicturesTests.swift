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
        #expect(ax.contains("value of attribute \"AXTitle\"") && driver.contains("[ \"$title\" = \"$want\" ]"))
    }

    /// The driver's verdict for "the system recolours the mark", run as `drive-menu-bar.sh --verdict`.
    func verdict(ours ink: Int, theirs tink: Int, oursFar od: String, theirsFar td: String) throws -> String {
        let run = Process()
        run.executableURL = URL(fileURLWithPath: "/bin/bash")
        run.arguments = [repoRoot().appendingPathComponent("scripts/ci/drive-menu-bar.sh").path,
            "--verdict", String(ink), String(tink), od, td]
        let pipe = Pipe()
        run.standardOutput = pipe
        try run.run()
        let out = pipe.fileHandleForReading.readDataToEndOfFile()
        run.waitUntilExit()
        return String(decoding: out, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The check can fail for the fault it is there for. On the runners' dark bar (0.024) a mark the system left
    /// black is within bartool's 0.1 of the bar, so it has no ink at all: that is a FAIL, not NOT-SHOWN.
    @Test func theRecolourCheckFailsOnAMarkLeftBlack() throws {
        #expect(try verdict(ours: 0, theirs: 232, oursFar: "0.000", theirsFar: "0.826") == "FAIL")     // black, dark bar
        #expect(try verdict(ours: 55, theirs: 232, oursFar: "0.730", theirsFar: "0.826") == "PASS")    // recoloured, dark
        #expect(try verdict(ours: 55, theirs: 232, oursFar: "-0.730", theirsFar: "0.826") == "FAIL")   // sides differ
        #expect(try verdict(ours: 55, theirs: 232, oursFar: "-0.730", theirsFar: "-0.730") == "PASS")  // light bar
        #expect(try verdict(ours: 55, theirs: 3, oursFar: "0.730", theirsFar: "0.000") == "NOT-SHOWN") // no system ink
        #expect(try verdict(ours: 55, theirs: 232, oursFar: "0.200", theirsFar: "0.826") == "NOT-SHOWN")
    }

    /// The words are kept in one place: the driver expects `MenuBarMark.spokenName` of each sample's symbol.
    @Test func theDriverExpectsTheSameWords() throws {
        let pairs = ["six-desks": "checkmark.circle", "sign-ins-off": "exclamationmark.circle",
            "waiting-for-login": "person.crop.circle.badge.questionmark", "locked": "lock.circle",
            "unreadable-list": "exclamationmark.triangle", "cant-reach": "wifi.slash", "not-set-up": "wrench.and.screwdriver",
            "still-checking": "ellipsis.circle", "no-workhorses": "plus.circle"]
        let driver = try file("scripts/ci/drive-menu-bar.sh")
        for (sample, symbol) in pairs {
            #expect(driver.contains("        \(sample)) echo \"\(MenuBarMark.spokenName(for: symbol) ?? "")\" ;;"), "\(sample)") }
        #expect(Set(pairs.values) == Set(MenuBarMark.symbols)) }
}
