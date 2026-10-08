// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "SKHynixMenuBar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "SKHynixMenuBar", targets: ["SKHynixMenuBar"])
    ],
    targets: [
        .executableTarget(
            name: "SKHynixMenuBar",
            path: "Sources"
        ),
        .testTarget(
            name: "SKHynixMenuBarTests",
            dependencies: ["SKHynixMenuBar"],
            path: "Tests"
        )
    ]
)
