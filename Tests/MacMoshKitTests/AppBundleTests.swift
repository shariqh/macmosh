import Foundation
import Testing
@testable import MacMoshKit

private func readPlist(_ relativePath: String) throws -> [String: Any]? {
    let url = repoRoot().appendingPathComponent(relativePath)
    return try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any]
}

@Suite struct AppBundleTests {
    @Test func theInfoPlistSaysWhatTheDesignSays() throws {
        let plist = try readPlist("App/Info.plist")
        #expect(plist?["CFBundleIdentifier"] as? String == "io.github.shariqh.macmosh")
        #expect(plist?["CFBundleIdentifier"] as? String == MacMoshInfo.bundleID)
        #expect(plist?["CFBundleName"] as? String == "MacMosh")
        #expect(plist?["CFBundleDisplayName"] as? String == "MacMosh")
        #expect(plist?["CFBundleExecutable"] as? String == "MacMosh")
        #expect(plist?["CFBundlePackageType"] as? String == "APPL")
        #expect(plist?["LSUIElement"] as? Bool == true)
        #expect(plist?["LSMinimumSystemVersion"] as? String == "15.0")
        #expect((plist?["NSAppleEventsUsageDescription"] as? String)?.isEmpty == false)
        #expect((plist?["NSLocalNetworkUsageDescription"] as? String)?.isEmpty == false)
    }

    @Test func theEntitlementsFileHasOnlyAppleEvents() throws {
        let plist = try readPlist("App/MacMosh.entitlements")
        #expect(plist?.count == 1)
        #expect(plist?["com.apple.security.automation.apple-events"] as? Bool == true)
    }

    /// `MacMosh` and `macmosh` are one file on a case-insensitive volume (macOS's default), so the app
    /// and the command can't share a folder. The command lives in `Contents/Helpers`.
    @Test func theBundleKeepsTheAppAndTheCommandApart() throws {
        let url = repoRoot().appendingPathComponent("scripts/build-app.sh")
        let script = try String(contentsOf: url, encoding: .utf8)
        #expect(script.contains("Contents/Helpers/macmosh"))
        #expect(!script.contains("Contents/MacOS/macmosh"))
    }

    @Test func theSigningIdentityIsNeverInTheRepo() throws {
        let root = repoRoot()
        let git = Process()
        git.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        git.arguments = ["ls-files", "-z"]
        git.currentDirectoryURL = root
        let pipe = Pipe()
        git.standardOutput = pipe
        try git.run()
        let listing = pipe.fileHandleForReading.readDataToEndOfFile()
        git.waitUntilExit()
        #expect(git.terminationStatus == 0)

        let names = String(decoding: listing, as: UTF8.self).split(separator: "\0").map(String.init)
        #expect(names.contains("Package.swift"))   // the listing worked
        // A real identity reads `Developer ID Application: <name> (<team>)`, so the phrase is followed
        // by a space. The plan names the bare prefix, with a backtick after it, which is not an identity.
        // The phrase is built in pieces so that this file doesn't contain it itself.
        let phrase = "Developer ID " + "Application:" + " "
        var offenders: [String] = []
        for name in names {
            guard let data = FileManager.default.contents(atPath: root.appendingPathComponent(name).path) else { continue }
            if data.range(of: Data(phrase.utf8)) != nil { offenders.append(name) }
        }
        #expect(offenders.isEmpty, "found the signing identity in: \(offenders)")
    }
}
