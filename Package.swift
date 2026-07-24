// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MonitorOverlay",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        // Executable name → `swift run MonitorOverlay`. The nice spaced display
        // name ("Monitor Overlay") is set at runtime for the menu bar / Dock.
        .executable(name: "MonitorOverlay", targets: ["MonitorOverlay"])
    ],
    targets: [
        .executableTarget(
            name: "MonitorOverlay"
        )
    ]
)
