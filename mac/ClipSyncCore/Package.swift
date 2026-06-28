// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "ClipSyncCore",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "ClipSyncCore",
            targets: ["ClipSyncCore"]
        ),
        .executable(
            name: "clipsync-cli",
            targets: ["clipsync-cli"]
        )
    ],
    targets: [
        .target(
            name: "ClipSyncCore"
        ),
        .executableTarget(
            name: "clipsync-cli",
            dependencies: ["ClipSyncCore"]
        ),
        .testTarget(
            name: "ClipSyncCoreTests",
            dependencies: ["ClipSyncCore"]
        )
    ]
)
