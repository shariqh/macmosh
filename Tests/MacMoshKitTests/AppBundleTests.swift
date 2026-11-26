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
        // Round 2, decision 6: with the group's translucency on (the default), ictool's renders lightened the light
        // M's lower rows and darkened the dark M's; with it off they match the layer pictures.
        let translucency = (json["groups"] as? [[String: Any]])?.first?["translucency"] as? [String: Any]
        #expect(translucency?["enabled"] as? Bool == false)
        #expect(try pixelSize("App/AppIcon.icon/Assets/m-light.png") == [1024, 1024])
        #expect(try pixelSize("App/AppIcon.icon/Assets/m-dark.png") == [1024, 1024])
        #expect(try pixelSize("App/AppIcon-16.png") == [16, 16]) }

    /// Round 2, decision 1: the layered icon. Assets.car carries the light and dark M for macOS 26 and newer,
    /// AppIcon.icns the light M for macOS 15.
    @Test func theInfoPlistNamesTheIcon() throws {
        let plist = try readPlist("App/Info.plist")
        #expect(plist?["CFBundleIconFile"] as? String == "AppIcon")
        #expect(plist?["CFBundleIconName"] as? String == "AppIcon") }

    /// Round 2, decisions 2 and 4: the build copies the committed Assets.car and packs the iconset; it never runs
    /// actool, so no Xcode is needed (actool from Xcode 26 crashed on CI's macOS 15 image, pull request 176). Both
    /// files go in after the sample-menu check and before signing, so the final verify covers them.
    @Test func theBuildScriptCopiesTheIconBeforeItSigns() throws {
        let script = try String(contentsOf: repoRoot().appendingPathComponent("scripts/build-app.sh"), encoding: .utf8)
        for part in ["-s App/Assets.car ]", "iconutil -c icns -o", "App/AppIcon.iconset"] {
            #expect(script.contains(part), "\(part)") }
        #expect(!script.contains("actool"))
        let carCheck = try #require(script.range(of: "-s App/Assets.car ]"))
        let pack = try #require(script.range(of: "iconutil -c icns -o"))
        let makeApp = try #require(script.range(of: "rm -rf \"$app\""))
        let sampleCheck = try #require(script.range(of: "sample_variable=MACMOSH_SAMPLE_MENU"))
        let copyCar = try #require(script.range(of: "cp App/Assets.car \"$app/Contents/Resources/\""))
        let copyIcns = try #require(script.range(of: "cp \"$work/AppIcon.icns\" \"$app/Contents/Resources/\""))
        let firstSign = try #require(script.range(of: "\"${sign[@]}\" \"$app/Contents/Helpers/macmosh\""))
        #expect(carCheck.lowerBound < makeApp.lowerBound && pack.lowerBound < makeApp.lowerBound)
        #expect(makeApp.lowerBound < sampleCheck.lowerBound)
        for copy in [copyCar, copyIcns] {
            #expect(sampleCheck.lowerBound < copy.lowerBound && copy.lowerBound < firstSign.lowerBound) }
        #expect(script.components(separatedBy: "codesign --verify --deep --strict").count == 2) }

    /// Round 2, decision 2: App/Assets.car is actool's compile of App/AppIcon.icon, committed. An asset catalog is
    /// a BOM file; the three appearance names are those round 1's compile listed (light, dark and tintable).
    @Test func theCommittedAssetsCarIsThere() throws {
        let car = try Data(contentsOf: repoRoot().appendingPathComponent("App/Assets.car"))
        #expect(car.count > 100_000)
        #expect(car.prefix(8) == Data("BOMStore".utf8))
        for name in ["NSAppearanceNameAqua", "NSAppearanceNameDarkAqua", "ISAppearanceTintable"] {
            #expect(car.range(of: Data(name.utf8)) != nil, "\(name)") } }

    /// Round 2, decision 3: scripts/make-icon.sh is the one written way to make the icon's files again, by hand,
    /// with Xcode 26 or newer. It writes only under App/ and in its own work folder, and deletes nothing.
    @Test func theIconIsMadeAgainOnlyByMakeIcon() throws {
        let url = repoRoot().appendingPathComponent("scripts/make-icon.sh")
        let script = try String(contentsOf: url, encoding: .utf8)
        #expect(script.filter { $0 == "\n" }.count <= 70)
        #expect(FileManager.default.isExecutableFile(atPath: url.path))
        for part in ["xcrun actool \"$PWD/App/AppIcon.icon\"", "--platform macosx", "--minimum-deployment-target 15.0",
                     "--app-icon AppIcon", "--target-device mac", "--standalone-icon-behavior all", "DEVELOPER_DIR",
                     "scripts/draw-icon/main.swift Sources/MacMoshKit/Look/IconArt.swift", "iconutil -c iconset -o",
                     "icon_16x16.png", "App/AppIcon-16.png", "App/Assets.car", "App/AppIcon.iconset", "mktemp -d"] {
            #expect(script.contains(part), "\(part)") }
        for line in script.split(separator: "\n") where line.trimmingCharacters(in: .whitespaces).hasPrefix("cp ") {
            let target = String(line.split(separator: " ").last ?? "")
            #expect(target.hasPrefix("\"App/") || target.hasPrefix("App/") || target.hasPrefix("\"$work"), "\(line)") }
        #expect(script.range(of: #"(^|[\s;|&(])rm\s"#, options: .regularExpression) == nil)
        let check = try String(contentsOf: repoRoot().appendingPathComponent("scripts/check.sh"), encoding: .utf8)
        #expect(check.contains("shellcheck scripts/make-icon.sh"))
        let workflow = try String(contentsOf: repoRoot().appendingPathComponent(".github/workflows/icon-pictures.yml"),
                                  encoding: .utf8)
        #expect(workflow.contains("'scripts/make-icon.sh'"))
        let build = try String(contentsOf: repoRoot().appendingPathComponent("scripts/build-app.sh"), encoding: .utf8)
        // The build only names it, in comments and in its stop message; it never runs it.
        #expect(!build.split(separator: "\n").contains { line in
            let code = line.trimmingCharacters(in: .whitespaces)
            return code.contains("make-icon.sh") && !code.hasPrefix("#") && !code.hasPrefix("echo ") }) }

    /// The iconset that build-app.sh packs into AppIcon.icns: actool's light render, every size, with the solid M at 16.
    @Test func theIconsetHasEverySize() throws {
        let sizes = [("icon_16x16.png", 16), ("icon_16x16@2x.png", 32), ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
                     ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256), ("icon_256x256.png", 256),
                     ("icon_256x256@2x.png", 512), ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)]
        for (name, side) in sizes {
            #expect(try pixelSize("App/AppIcon.iconset/\(name)") == [side, side], "\(name)") }
        // The 16-pixel picture is the solid M, not a shrunk render of the tiles (design 8.1).
        let root = repoRoot()
        #expect(try Data(contentsOf: root.appendingPathComponent("App/AppIcon.iconset/icon_16x16.png"))
            == Data(contentsOf: root.appendingPathComponent("App/AppIcon-16.png"))) }

    /// A runner that stayed light must not leave light pictures under dark names: the dark pictures
    /// run only when the switch to dark was read back.
    @Test func theDarkPicturesWaitForTheDarkSwitch() throws {
        let workflow = try String(contentsOf: repoRoot().appendingPathComponent(".github/workflows/icon-pictures.yml"),
                                  encoding: .utf8)
        let steps = workflow.components(separatedBy: "      - name: ")
        let turn = try #require(steps.first { $0.hasPrefix("Turn on dark\n") })
        let dark = try #require(steps.first { $0.hasPrefix("The icon in dark\n") })
        #expect(turn.contains("        id: dark\n"))
        #expect(dark.contains("steps.dark.outcome == 'success'"))
    }
}
