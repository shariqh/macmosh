import Foundation
import Testing

/// Issue 189: the app's two programs must not carry folder paths of the Mac that built them. `swift build -c release`
/// keeps debugging entries that name every source and object file by its full path; `scripts/build-app.sh` strips
/// them from a release build and then searches both programs.
@Suite struct BuildPathsTests {
    private func buildScript() throws -> String {
        try String(contentsOf: repoRoot().appendingPathComponent("scripts/build-app.sh"), encoding: .utf8)
    }

    /// Stripping changes the file, so it comes after the two comparisons with the build's own output and before the
    /// first signature. Only a release build is stripped: CI's pictures use the debug build as it is.
    @Test func aReleaseBuildIsStrippedBeforeItIsSigned() throws {
        let script = try buildScript()
        let strip = try #require(script.range(of: "strip -S -no_code_signature_warning \"$file\""))
        let lastCompare = try #require(script.range(of: "cmp -s \"$bin/macmosh\" \"$app/Contents/Helpers/macmosh\""))
        let firstSign = try #require(script.range(of: "\"${sign[@]}\" \"$app/Contents/Helpers/macmosh\""))
        #expect(lastCompare.lowerBound < strip.lowerBound && strip.lowerBound < firstSign.lowerBound)

        let before = script[..<strip.lowerBound]
        let releaseOnly = try #require(before.range(of: "if [ \"$config\" = release ]; then", options: .backwards))
        let between = before[releaseOnly.upperBound...]
        #expect(!between.contains("\nfi"), "the strip is inside the release-only branch")
        #expect(between.contains("for file in \"$app/Contents/MacOS/MacMosh\" \"$app/Contents/Helpers/macmosh\"; do"))
    }

    /// The search reads the file's bytes. `strings -a <file> | grep /Users/` found none of the 209 and 313 places a
    /// byte search found on 26 November 2026, so no line of the script may rely on `strings`.
    @Test func theSearchForBuildPathsReadsTheBytes() throws {
        let script = try buildScript()
        let strip = try #require(script.range(of: "strip -S -no_code_signature_warning \"$file\""))
        let search = try #require(script.range(of: "LC_ALL=C grep -qaF \"$needle\" \"$file\""))
        let firstSign = try #require(script.range(of: "\"${sign[@]}\" \"$app/Contents/Helpers/macmosh\""))
        #expect(strip.lowerBound < search.lowerBound && search.lowerBound < firstSign.lowerBound)
        #expect(script.contains("for needle in \"/Users/\" \"$root\"; do"))
        #expect(script.contains("still holds a folder path from the Mac that built it"))
        for line in script.split(separator: "\n") where !line.trimmingCharacters(in: .whitespaces).hasPrefix("#") {
            #expect(!line.contains("strings "), "\(line)")
        }
    }
}
