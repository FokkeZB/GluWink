// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SharedKit",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v16),
        .watchOS(.v10),
        // macOS isn't an app target — it's only declared so the SPM test
        // target can compile and run on the host (`swift test`) without
        // standing up an iOS Simulator. Pick the lowest version that
        // satisfies the APIs SharedKit currently uses (URLSession async
        // `data(for:)` requires macOS 12+).
        .macOS(.v13),
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
        .testTarget(
            name: "SharedKitTests",
            dependencies: ["SharedKit"]
        ),
    ]
)
