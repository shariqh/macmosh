import Foundation

/// The About section at the end of Settings (look design 6.9): the app's name and version, the licence, and the two
/// credit lines of the v1 design, word for word. There is no About window and no About item in the menu.
public struct AboutSection: Sendable, Equatable {
    public var heading: String
    public var name: String
    /// "Version 0.1.0": `MacMoshInfo.version`, the number the build script writes into the app, so a debug run shows
    /// the same words as a release.
    public var version: String
    public var licence: String
    public var credits: [String]

    public init(version: String = MacMoshInfo.version) {
        heading = SettingsWords.about
        name = SettingsWords.appName
        self.version = SettingsWords.version(version)
        licence = SettingsWords.licence
        credits = SettingsWords.creditLines
    }
}
