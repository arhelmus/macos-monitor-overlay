import Foundation

/// Persistent storage for app settings. Uses an explicit suite so the domain is
/// stable even though this is an unbundled binary (no bundle identifier).
enum Persistence {
    static let defaults: UserDefaults = UserDefaults(suiteName: "com.arhelmus.MonitorOverlay") ?? .standard

    enum Key {
        static let autoRestore = "autoRestoreOnReconnect"
        static let overlayURL = "overlayURLString"
        static let desiredUUIDs = "deployedDisplayUUIDs"
    }
}
