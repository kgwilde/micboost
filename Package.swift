// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MicBoost",
    platforms: [
        .macOS(.v12)
    ],
    targets: [
        .target(
            name: "MicBoostIPC",
            path: "Sources/MicBoostIPC"
        ),
        .executableTarget(
            name: "MicBoost",
            dependencies: ["MicBoostIPC"],
            path: "Sources/MicBoost"
        ),
        .executableTarget(
            name: "micboostctl",
            dependencies: ["MicBoostIPC"],
            path: "Sources/MicBoostCLI"
        )
    ]
)
