// swift-tools-version: 6.0
// A throwaway trial, not part of MacMosh: it answers how SwiftUI menus behave inside a
// MenuBarExtra. It runs only on GitHub's macOS runners (.github/workflows/trial-submenus.yml).
import PackageDescription

let package = Package(
    name: "SubmenuTrial",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(name: "SubmenuTrial"),
        .executableTarget(name: "trialtool"),
    ],
    swiftLanguageModes: [.v5]
)
