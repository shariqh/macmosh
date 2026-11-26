import Foundation
import ImageIO
import Testing
@testable import MacMoshKit

private func readPlist(_ relativePath: String) throws -> [String: Any]? {
    let url = repoRoot().appendingPathComponent(relativePath)
    return try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any]
}

/// A picture's width and height in pixels, read through ImageIO.
private func pixelSize(_ relativePath: String) throws -> [Int] {
    let url = repoRoot().appendingPathComponent(relativePath)
    let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil), "cannot read \(relativePath)")
    let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    return [properties[kCGImagePropertyPixelWidth] as? Int ?? -1, properties[kCGImagePropertyPixelHeight] as? Int ?? -1]
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
        // A real certificate name has the phrase, a colon, then a space and the owner's name. The plan
        // names the bare prefix, with a backtick after the colon, which is not a certificate name.
        // The phrase is built in pieces so that this file doesn't contain it itself.
        let phrase = "Developer ID " + "Application:" + " "
        var offenders: [String] = []
        for name in names {
            guard let data = FileManager.default.contents(atPath: root.appendingPathComponent(name).path) else { continue }
            if data.range(of: Data(phrase.utf8)) != nil { offenders.append(name) }
        }
        #expect(offenders.isEmpty, "found the signing identity in: \(offenders)")
    }

    @Test func theIconDocumentHasALightAndADarkLayer() throws {
        let url = repoRoot().appendingPathComponent("App/AppIcon.icon/icon.json")
        let json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let layers = try #require(((json["groups"] as? [[String: Any]])?.first?["layers"]) as? [[String: Any]])
        try #require(layers.count == 2)
        #expect(layers.map { $0["name"] as? String } == ["m-light", "m-dark"])
        #expect(layers.map { $0["image-name"] as? String } == ["m-light.png", "m-dark.png"])
        func hidden(_ l: [String: Any]) -> [String] {
            (l["hidden-specializations"] as? [[String: Any]] ?? []).map { "\($0["appearance"] as? String ?? "default")=\($0["value"] as? Bool ?? false)" } }
        #expect(hidden(layers[0]) == ["default=false", "dark=true"] && hidden(layers[1]) == ["default=true", "dark=false"])
        #expect((json["supported-platforms"] as? [String: Any])?["squares"] as? [String] == ["macOS"])
        #expect(try pixelSize("App/AppIcon.icon/Assets/m-light.png") == [1024, 1024])
        #expect(try pixelSize("App/AppIcon.icon/Assets/m-dark.png") == [1024, 1024])
        #expect(try pixelSize("App/AppIcon-16.png") == [16, 16]) }

    @Test func theInfoPlistNamesTheIcon() throws {
        let plist = try readPlist("App/Info.plist")
        #expect(plist?["CFBundleIconFile"] as? String == "AppIcon")
        #expect(plist?["CFBundleIconName"] as? String == "AppIcon") }

    /// Design 8.2: actool before the app is made, Contents/Resources, both files, then signing as today (Review Focus 1, 2 and 4).
    @Test func theBuildScriptMakesTheIconBeforeItSigns() throws {
        let script = try String(contentsOf: repoRoot().appendingPathComponent("scripts/build-app.sh"), encoding: .utf8)
        for part in ["xcrun actool", "App/AppIcon.icon", "--app-icon AppIcon", "--minimum-deployment-target 15.0",
                     "--standalone-icon-behavior all", "Contents/version.plist", "DEVELOPER_DIR=",
                     "icon_16x16.png", "App/AppIcon-16.png", "iconutil -c iconset -o", "iconutil -c icns -o",
                     "$app/Contents/Resources", "Assets.car", "AppIcon.icns"] { #expect(script.contains(part), "\(part)") }
        let compile = try #require(script.range(of: "--app-icon AppIcon"))
        let makeApp = try #require(script.range(of: "rm -rf \"$app\""))
        let sampleCheck = try #require(script.range(of: "sample_variable=MACMOSH_SAMPLE_MENU"))
        let resources = try #require(script.range(of: "$app/Contents/Resources"))
        let firstSign = try #require(script.range(of: "\"${sign[@]}\" \"$app/Contents/Helpers/macmosh\""))
        #expect(compile.lowerBound < makeApp.lowerBound && makeApp.lowerBound < sampleCheck.lowerBound)
        #expect(sampleCheck.lowerBound < resources.lowerBound && resources.lowerBound < firstSign.lowerBound)
        #expect(script.components(separatedBy: "codesign --verify --deep --strict").count == 2) }
}
