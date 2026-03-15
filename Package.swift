// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "OpenAITTSKit",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "OpenAITTSKit", targets: ["OpenAITTSKit"]),
    ],
    targets: [
        .target(
            name: "OpenAITTSKit",
            path: "Sources/OpenAITTSKit",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ]),
        .testTarget(
            name: "OpenAITTSKitTests",
            dependencies: ["OpenAITTSKit"],
            path: "Tests/OpenAITTSKitTests",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                .enableExperimentalFeature("SwiftTesting"),
            ]),
    ])
