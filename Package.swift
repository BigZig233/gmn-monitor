// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "GMNUsageMonitor",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "GMNUsageMonitor",
            targets: ["GMNUsageMonitor"]
        )
    ],
    dependencies: [
        .package(path: "/tmp/DockProgress")
    ],
    targets: [
        .executableTarget(
            name: "GMNUsageMonitor",
            dependencies: ["DockProgress"]
        )
    ]
)
