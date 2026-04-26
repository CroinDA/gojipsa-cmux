// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GOJIPSA",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/airbnb/lottie-ios.git", from: "4.5.0"),
    ],
    targets: [
        .target(
            name: "GOJIPSACore",
            dependencies: [
                .product(name: "Lottie", package: "lottie-ios"),
            ],
            path: "Sources/GOJIPSACore",
            resources: [
                .copy("Resources/lottie"),
            ]
        ),
        .executableTarget(
            name: "GOJIPSA",
            dependencies: ["GOJIPSACore"],
            path: "Sources/GOJIPSA"
        ),
        .executableTarget(
            name: "GOJIPSATests",
            dependencies: ["GOJIPSACore"],
            path: "Sources/GOJIPSATests"
        )
    ]
)
