// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodingPlanMonitor",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "CodingPlanMonitor",
            path: "Sources/CodingPlanMonitor"
        )
    ]
)
