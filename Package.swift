// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacMosh",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "MacMoshKit", targets: ["MacMoshKit"]),
        .executable(name: "macmosh", targets: ["macmosh"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.8.2"),
    ],
    targets: [
        .target(name: "MacMoshKit"),
        .executableTarget(
            name: "macmosh",
            dependencies: [
                "MacMoshKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(name: "MacMoshKitTests", dependencies: ["MacMoshKit"]),
    ]
)
