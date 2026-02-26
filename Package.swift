// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-chromecast-kit",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15),
    ],
    products: [
        .library(
            name: "ChromecastKit",
            targets: ["ChromecastKit"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.35.1"),
    ],
    targets: [
        .target(
            name: "ChromecastKit",
            dependencies: [
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ]
        ),
        .testTarget(
            name: "ChromecastKitTests",
            dependencies: ["ChromecastKit"]
        ),
    ]
)
