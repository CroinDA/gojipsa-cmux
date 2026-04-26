// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Sentinel",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/airbnb/lottie-ios.git", from: "4.5.0"),
    ],
    targets: [
        .target(
            name: "SentinelCore",
            dependencies: [
                .product(name: "Lottie", package: "lottie-ios"),
            ],
            path: "Sources/SentinelCore",
            resources: [
                .copy("Resources/lottie"),
            ]
        ),
        .executableTarget(
            name: "Sentinel",
            dependencies: ["SentinelCore"],
            path: "Sources/Sentinel"
        ),
        .executableTarget(
            name: "SentinelTests",
            dependencies: ["SentinelCore"],
            path: "Sources/SentinelTests"
        )
    ]
)
