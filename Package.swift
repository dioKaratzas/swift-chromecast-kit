// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-chromecast-kit",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15),
        .tvOS(.v13),
        .watchOS(.v6),
    ],
    products: [
        .library(
            name: "ChromecastKit",
            targets: ["ChromecastKit"]
        ),
    ],
    targets: [
        .target(
            name: "ChromecastKit"
        ),
        .testTarget(
            name: "ChromecastKitTests",
            dependencies: ["ChromecastKit"]
        ),
    ]
)
