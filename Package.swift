// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MicBoost",
    platforms: [
        .macOS(.v12)
    ],
    targets: [
        .executableTarget(
            name: "MicBoost",
            path: "Sources/MicBoost"
        )
    ]
)
