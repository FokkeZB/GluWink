// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SharedKit",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v16),
        .watchOS(.v10),
    ],
    products: [
        .library(
            name: "SharedKit",
            targets: ["SharedKit"]
        ),
    ],
    targets: [
        .target(
            name: "SharedKit",
            resources: [
                .process("Resources"),
            ]
        ),
    ]
)
