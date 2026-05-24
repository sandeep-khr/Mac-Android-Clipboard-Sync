// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "ClipSyncMac",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "ClipSyncMac",
            targets: ["ClipSyncMac"]
        )
    ],
    targets: [
        .executableTarget(
            name: "ClipSyncMac"
        )
    ]
)
