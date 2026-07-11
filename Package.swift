// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NetMonitor",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "NetMonitorCore",
            path: "Sources/NetMonitorCore",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .linkedFramework("IOKit")
            ]
        ),
        .executableTarget(
            name: "NetMonitor",
            dependencies: ["NetMonitorCore"],
            path: "Sources/NetMonitor"
        ),
        .testTarget(
            name: "NetMonitorTests",
            dependencies: ["NetMonitorCore"],
            path: "Tests/NetMonitorTests"
        )
    ]
)
