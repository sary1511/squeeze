// swift-tools-version: 6.0
// Open this file in Xcode 26 to edit and run Squeeze. Use build.sh to make the .app and .dmg.
import PackageDescription

let package = Package(
    name: "Squeeze",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "Squeeze",
            path: "Sources/Squeeze",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
