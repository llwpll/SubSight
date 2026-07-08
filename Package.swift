// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "SubSight",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "SubSightCore", targets: ["SubSightCore"]),
        .executable(name: "SubSight", targets: ["SubscriptionLedgerApp"]),
        .executable(name: "subsightctl", targets: ["SubSightCLI"])
    ],
    targets: [
        .target(
            name: "SubSightCore"
        ),
        .executableTarget(
            name: "SubscriptionLedgerApp",
            dependencies: ["SubSightCore"]
        ),
        .executableTarget(
            name: "SubSightCLI",
            dependencies: ["SubSightCore"]
        ),
        .testTarget(
            name: "SubSightCoreTests",
            dependencies: ["SubSightCore"]
        )
    ]
)
