// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MonitorEnumerator",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "MonitorEnumerator",
            path: "Sources/MonitorEnumerator"
        )
    ]
)
