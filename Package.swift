// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MonitorOverlay",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        // The executable (and thus the process / menu-bar / Dock name).
        .executable(name: "Monitor Overlay", targets: ["MonitorOverlay"])
    ],
    targets: [
        .executableTarget(
            name: "MonitorOverlay",
            path: "Sources/MonitorEnumerator"
        )
    ]
)
