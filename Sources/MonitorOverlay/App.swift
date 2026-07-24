import SwiftUI

struct MonitorOverlayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // No auto-created window: the main window is managed manually by
        // AppDelegate/MainWindowController so we control if and when it appears.
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let mainWindow = MainWindowController()
    private var statusItem: NSStatusItem?
    private var userRequestedQuit = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        installStatusItem()

        let options = CLIOptions.parse(Array(CommandLine.arguments.dropFirst()))
        if options.showHelp {
            print(CLIOptions.helpText)
            exit(0)
        }

        // Seed the overlay URL (also prefills the main-window text field).
        if let urlString = options.urlString {
            OverlaySettings.shared.overlayURLString = urlString
        }

        MainWindowCoordinator.shared.controller = mainWindow

        // Enumerate monitors on start and log them to the console.
        let monitors = MonitorInfo.all()
        print("Detected \(monitors.count) monitor(s):")
        for (index, monitor) in monitors.enumerated() {
            print("""
              [\(index + 1)] \(monitor.name)\(monitor.isMain ? " (main)" : "")
                  id:        \(monitor.id)
                  position:  (\(Int(monitor.frame.origin.x)), \(Int(monitor.frame.origin.y)))
                  points:    \(Int(monitor.pointSize.width)) × \(Int(monitor.pointSize.height))
                  pixels:    \(Int(monitor.pixelSize.width)) × \(Int(monitor.pixelSize.height))
                  scale:     \(monitor.scaleFactor)x
                  refresh:   \(monitor.refreshRate.map { String(format: "%.0f Hz", $0) } ?? "unknown")
            """)
        }

        // Re-deploy overlays that were active in a previous run (connected displays).
        WebWindowManager.shared.restorePersisted(using: monitors)

        // --monitor: auto-open an overlay on the selected display at launch.
        // If it resolves, the main window is never shown.
        if let selector = options.monitorSelector {
            if let monitor = resolveMonitor(selector, in: monitors) {
                print("Auto-opening overlay on: \(monitor.name)\(monitor.isMain ? " (main)" : "")")
                MainWindowCoordinator.shared.suppressForCLI()
                WebWindowManager.shared.open(on: monitor) // uses OverlaySettings.overlayURL
                return
            }
            FileHandle.standardError.write(
                Data("No monitor matched selector '\(selector)'; showing main window.\n".utf8))
        }

        // Default: show the main window.
        mainWindow.show()
    }

    // Never auto-quit when the last window goes away — a disconnected overlay
    // has no window but must keep running. Quitting is explicit (Esc on the last
    // visible overlay, closing the main window, or the menu-bar Quit item).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Menu-bar status item: open the main window (Settings) or quit. Always
    /// available, even while the overlay is deployed and the main window hidden.
    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let glyph = NSImage(systemSymbolName: "display", accessibilityDescription: "Monitor Overlay")
        glyph?.isTemplate = true
        item.button?.image = glyph

        let menu = NSMenu()
        let settings = menu.addItem(withTitle: "Settings…",
                                    action: #selector(openSettings),
                                    keyEquivalent: ",")
        settings.target = self
        menu.addItem(.separator())
        // No ⌘Q here — quitting is deliberate (click), never a stray shortcut.
        let quit = menu.addItem(withTitle: "Quit Monitor Overlay",
                                action: #selector(quitFromMenu),
                                keyEquivalent: "")
        quit.target = self
        item.menu = menu
        statusItem = item
    }

    @objc private func openSettings() {
        MainWindowCoordinator.shared.showMainWindow()
    }

    /// The only path that actually terminates the app.
    @objc private func quitFromMenu() {
        userRequestedQuit = true
        WebWindowManager.shared.prepareForQuit()
        NSApp.terminate(nil)
    }

    /// ⌘Q (or any `terminate:`) must not kill the process — only the menu-bar
    /// Quit item may. For every other quit attempt, close the focused window
    /// instead and keep running.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if userRequestedQuit { return .terminateNow }
        NSApp.keyWindow?.performClose(nil)
        return .terminateCancel
    }

    // Flush pending UserDefaults writes to disk before the process exits —
    // otherwise cfprefsd may not have committed the last session's changes.
    func applicationWillTerminate(_ notification: Notification) {
        Persistence.defaults.synchronize()
    }
}
