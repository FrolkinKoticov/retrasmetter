// swift-tools-version: 5.9
import PackageDescription

// Requires Xcode 15+ (Xcode 16+ to include Apple Translation support; older SDKs compile it out).
let package = Package(
    name: "GameLanguageCompanion",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "GameLanguageCompanion",
            path: "Sources/GameLanguageCompanion"
        )
    ]
)
