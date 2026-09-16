// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "diskscope",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DiskKit", targets: ["DiskKit"]),
        .executable(name: "dscope", targets: ["dscope"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        .target(name: "DiskKit"),
        .executableTarget(
            name: "dscope",
            dependencies: [
                "DiskKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(name: "DiskKitTests", dependencies: ["DiskKit"]),
    ]
)
