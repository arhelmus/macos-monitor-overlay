import SwiftUI

@main
struct MonitorEnumeratorApp: App {
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        installStatusItem()

        let options = CLIOptions.parse(Array(CommandLine.arguments.dropFirst()))
        if options.showHelp {
            print(CLIOptions.helpText)
            exit(0)
        }

        // Apply --auto-restore / --no-auto-restore before anything can disconnect.
        if let autoRestore = options.autoRestore {
            OverlaySettings.shared.autoRestoreOnReconnect = autoRestore
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

    /// A menu-bar status item whose only action is Quit — the always-available
    /// way to quit even while the overlay is hidden (monitor off).
    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "display",
            accessibilityDescription: "Monitor Overlay")

        let menu = NSMenu()
        menu.addItem(withTitle: "Quit Monitor Overlay",
                     action: #selector(NSApplication.terminate(_:)),
                     keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }
}
