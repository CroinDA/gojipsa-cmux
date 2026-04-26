// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Sentinel",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "SentinelCore",
            path: "Sources/SentinelCore"
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
