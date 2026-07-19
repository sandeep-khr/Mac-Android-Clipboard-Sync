// swift-tools-version: 6.0

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
        ),
        .executable(
            name: "clipsync-menubar",
            targets: ["clipsync-menubar"]
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
        .executableTarget(
            name: "clipsync-menubar",
            dependencies: ["ClipSyncCore"]
        ),
        .testTarget(
            name: "ClipSyncCoreTests",
            dependencies: ["ClipSyncCore"]
        )
    ]
)
