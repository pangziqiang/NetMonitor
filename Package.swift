// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NetworkMonitor",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "NetworkMonitorCore",
            path: "Sources/NetworkMonitorCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "NetworkMonitor",
            dependencies: ["NetworkMonitorCore"],
            path: "Sources/NetworkMonitor"
        ),
        .testTarget(
            name: "NetworkMonitorTests",
            dependencies: ["NetworkMonitorCore"],
            path: "Tests/NetworkMonitorTests"
        )
    ]
)
