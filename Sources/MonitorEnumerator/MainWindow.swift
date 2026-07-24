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
        // Keep the window alive across close so it can be reopened from the menu.
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // Closing the main window must not quit the app — it's a persistent agent.
    // Hide it (and drop the Dock/menu-bar app) instead; reopen via Settings…,
    // quit via the menu-bar Quit item.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hideAndDetach()
        return false
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

    private init() {}

    /// Show the main window (menu-bar Settings, or after the last overlay closes).
    func showMainWindow() {
        controller?.show()
    }

    /// User clicked a monitor: hide the main window and drop the Dock/menu-bar app.
    func hideForOverlay() {
        controller?.hideAndDetach()
    }

    /// Launched directly into an overlay via CLI: main window never appears.
    func suppressForCLI() {
        NSApp.setActivationPolicy(.accessory)
    }

    /// The user closed (Esc'd) the last visible overlay — bring the main window
    /// back so the app is never left invisible with no window. Quitting is done
    /// explicitly via the menu-bar Quit item.
    func overlaysDidFinish() {
        showMainWindow()
    }
}
