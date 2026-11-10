// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Sidle",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "MTBridge", path: "Sources/MTBridge"),
        .executableTarget(
            name: "Sidle",
            dependencies: ["MTBridge"],
            path: "Sources/Sidle",
            swiftSettings: [.unsafeFlags(["-parse-as-library"])],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("Carbon"),
                .linkedFramework("IOKit"),
            ]
        ),
    ],
    swiftLanguageVersions: [.v5]
)
