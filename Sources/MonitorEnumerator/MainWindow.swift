import AppKit
import SwiftUI

/// Owns the main "Monitors" window so we control exactly when it appears,
/// hides, and whether the app shows a Dock icon / menu bar at all.
final class MainWindowController: NSWindowController, NSWindowDelegate {
    init() {
        let hosting = NSHostingController(rootView: ContentView())
        let window = NSWindow(contentViewController: hosting)
        window.title = "Monitors"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 560, height: 500))
        window.contentMinSize = NSSize(width: 520, height: 420)
        window.center()
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // Implicit last-window termination is disabled app-wide, so quit explicitly
    // when the user closes the main window. (Hiding for an overlay uses orderOut,
    // which does not fire this.)
    func windowWillClose(_ notification: Notification) {
        NSApp.terminate(nil)
    }

    /// Show the window and make the app a regular foreground app (Dock icon + menu bar).
    func show() {
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Hide the window and drop the Dock icon / menu-bar presence.
    func hideAndDetach() {
        window?.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
    }
}

/// Coordinates the lifecycle between the main window and overlays.
final class MainWindowCoordinator {
    static let shared = MainWindowCoordinator()

    var controller: MainWindowController?
    /// True when the main window was shown then hidden for an overlay (UI click),
    /// meaning we should bring it back once all overlays are gone. False when the
    /// app was launched straight into an overlay via --monitor (nothing to return to).
    private var restoreMainOnFinish = false

    private init() {}

    /// User clicked a monitor: hide the main window and remember to restore it later.
    func hideForOverlay() {
        restoreMainOnFinish = true
        controller?.hideAndDetach()
    }

    /// Launched directly into an overlay via CLI: main window never appears.
    func suppressForCLI() {
        restoreMainOnFinish = false
        NSApp.setActivationPolicy(.accessory)
    }

    /// Called when the last overlay has been closed by the user.
    func overlaysDidFinish() {
        if restoreMainOnFinish {
            restoreMainOnFinish = false
            controller?.show()
        } else {
            NSApp.terminate(nil)
        }
    }
}
