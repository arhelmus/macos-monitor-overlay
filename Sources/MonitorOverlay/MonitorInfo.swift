import AppKit
import CoreGraphics

/// A snapshot of one physical display's properties.
struct MonitorInfo: Identifiable {
    let id: CGDirectDisplayID
    let name: String
    let isMain: Bool
    /// Point-based frame in the global coordinate space (origin bottom-left).
    let frame: CGRect
    /// Backing scale factor: 2.0 for Retina, 1.0 otherwise.
    let scaleFactor: CGFloat
    /// Native pixel dimensions of the display.
    let pixelSize: CGSize
    /// Refresh rate in Hz, or nil if it can't be determined.
    let refreshRate: Double?

    var pointSize: CGSize { frame.size }

    /// Enumerate every currently active display attached to this Mac.
    static func all() -> [MonitorInfo] {
        NSScreen.screens.map { screen in
            let displayID = screen.displayID
            let pixelWidth = CGDisplayPixelsWide(displayID)
            let pixelHeight = CGDisplayPixelsHigh(displayID)
            let mode = CGDisplayCopyDisplayMode(displayID)

            return MonitorInfo(
                id: displayID,
                name: screen.readableName,
                isMain: screen == NSScreen.main,
                frame: screen.frame,
                scaleFactor: screen.backingScaleFactor,
                pixelSize: CGSize(width: pixelWidth, height: pixelHeight),
                refreshRate: mode.map(\.refreshRate).flatMap { $0 > 0 ? $0 : nil }
            )
        }
    }
}

extension NSScreen {
    /// The CoreGraphics display ID backing this screen.
    var displayID: CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return deviceDescription[key] as? CGDirectDisplayID ?? 0
    }

    /// A human-readable name for the display (e.g. "Built-in Retina Display").
    var readableName: String {
        if #available(macOS 10.15, *) {
            return localizedName
        }
        return "Display \(displayID)"
    }
}
