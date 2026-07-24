import AppKit
import Combine
import WebKit

// MARK: - Stable display identity

/// A physical display's UUID stays the same across disconnect/reconnect, whereas
/// its `CGDirectDisplayID` can be reassigned. We pin overlays by UUID.
enum DisplayIdentity {
    static func uuid(for id: CGDirectDisplayID) -> String? {
        guard let ref = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, ref) as String
    }
}

extension NSScreen {
    /// Stable UUID for the physical display backing this screen.
    var displayUUID: String? { DisplayIdentity.uuid(for: displayID) }
}

// MARK: - Settings

/// User-tunable overlay behavior, bound to the controls on the main window.
final class OverlaySettings: ObservableObject {
    static let shared = OverlaySettings()

    static let defaultURL = URL(string: "https://www.google.com")!

    /// The address opened in new overlays (raw text as typed / passed on the CLI).
    @Published var overlayURLString: String {
        didSet { Persistence.defaults.set(overlayURLString, forKey: Persistence.Key.overlayURL) }
    }

    /// Page zoom applied inside the overlay web view (1.0 = 100%).
    @Published var webZoom: Double {
        didSet { Persistence.defaults.set(webZoom, forKey: Persistence.Key.webZoom) }
    }

    /// Selectable zoom levels shown in the settings segmented control (5 segments).
    static let zoomLevels: [Double] = [0.5, 0.75, 1.0, 1.5, 2.0]

    /// The parsed, scheme-normalized URL to open (falls back to the default).
    var overlayURL: URL {
        OverlaySettings.normalizedURL(from: overlayURLString) ?? OverlaySettings.defaultURL
    }

    /// Accept bare hosts like "apple.com" by defaulting the scheme to https.
    static func normalizedURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), url.scheme != nil { return url }
        return URL(string: "https://" + trimmed)
    }

    private init() {
        let defaults = Persistence.defaults
        overlayURLString = defaults.string(forKey: Persistence.Key.overlayURL)
            ?? OverlaySettings.defaultURL.absoluteString
        let savedZoom = defaults.object(forKey: Persistence.Key.webZoom) as? Double
        webZoom = savedZoom ?? 1.0
    }
}

// MARK: - Borderless window

/// A borderless window that can still become key (borderless windows normally
/// refuse key/main status, which would leave the web view unable to take input).
final class BorderlessWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// Escape closes the overlay.
    override func cancelOperation(_ sender: Any?) { close() }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            close()
        } else {
            super.keyDown(with: event)
        }
    }
}

// MARK: - Overlay window controller

/// A borderless, edge-to-edge web window pinned to one physical display (by UUID).
final class WebWindowController: NSWindowController, NSWindowDelegate {
    /// Stable identity of the display this overlay is pinned to.
    let displayUUID: String
    private let webView: WKWebView

    init(screen: NSScreen, displayUUID: String, url: URL) {
        self.displayUUID = displayUUID

        let webView = WKWebView(frame: screen.frame)
        webView.autoresizingMask = [.width, .height]
        webView.pageZoom = OverlaySettings.shared.webZoom
        self.webView = webView

        let window = BorderlessWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        // Cover the ENTIRE display: menu bar and Dock included.
        window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        window.collectionBehavior = [.fullScreenNone, .canJoinAllSpaces, .stationary]
        window.isOpaque = true
        window.hasShadow = false
        window.contentView = webView
        window.setFrame(screen.frame, display: true)

        super.init(window: window)
        window.delegate = self

        webView.load(URLRequest(url: url))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Re-pin the window to a display's current frame (after reconnect / rearrange).
    func reposition(to screen: NSScreen) {
        window?.setFrame(screen.frame, display: true)
    }

    /// Navigate the overlay's web view to a new address.
    func load(_ url: URL) {
        webView.load(URLRequest(url: url))
    }

    /// Set the page zoom (1.0 = 100%).
    func setZoom(_ zoom: Double) {
        webView.pageZoom = zoom
    }

    /// Show the borderless window edge-to-edge on its target display.
    func present() {
        guard let window else { return }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Hide without destroying — used when the display disconnects but we intend
    /// to restore the overlay when it comes back.
    func hide() {
        window?.orderOut(nil)
    }

    // Route every close through the manager, which decides whether it's a user
    // close (forget) or a disconnect-driven close (keep for later restore).
    func windowWillClose(_ notification: Notification) {
        WebWindowManager.shared.windowClosed(uuid: displayUUID)
    }
}

// MARK: - Manager (Option C: CG reconfiguration callback + screen-params notification)

/// One overlay intent per pinned physical display.
private final class OverlayIntent {
    let uuid: String
    var url: URL
    /// nil while the display is gone (the window may have been torn down by the OS).
    var controller: WebWindowController?
    /// Last known live display ID for this UUID (for fast removeFlag matching).
    var currentDisplayID: CGDirectDisplayID
    /// True when the display is gone and we're waiting to restore the overlay.
    var hidden: Bool = false

    init(uuid: String, url: URL, controller: WebWindowController, displayID: CGDirectDisplayID) {
        self.uuid = uuid
        self.url = url
        self.controller = controller
        self.currentDisplayID = displayID
    }
}

/// C-compatible reconfiguration callback (no captured context → valid function pointer).
private let reconfigurationCallback: CGDisplayReconfigurationCallBack = { displayID, flags, _ in
    DispatchQueue.main.async {
        WebWindowManager.shared.handleReconfiguration(display: displayID, flags: flags)
    }
}

final class WebWindowManager: ObservableObject {
    static let shared = WebWindowManager()

    /// UUIDs of displays that currently have a deployed overlay (visible or
    /// hidden-while-disconnected). Drives the main window's UI.
    @Published private(set) var overlayUUIDs: Set<String> = []

    private var intents: [String: OverlayIntent] = [:] // keyed by stable display UUID
    private var wired = false
    /// Set during app termination so window teardown doesn't clear the persisted
    /// selection (closing overlays on quit must NOT count as user "un-deploying").
    private var isQuitting = false

    /// User's persisted selection of displays that should have an overlay. Only
    /// changed by explicit user actions (open/destroy/close) — NOT by disconnects
    /// — so a monitor that's off at launch stays remembered for next time.
    private var desiredUUIDs: Set<String> {
        didSet {
            Persistence.defaults.set(Array(desiredUUIDs), forKey: Persistence.Key.desiredUUIDs)
        }
    }

    private init() {
        desiredUUIDs = Set(Persistence.defaults.stringArray(forKey: Persistence.Key.desiredUUIDs) ?? [])
    }

    /// Is an overlay deployed on this monitor's physical display?
    func hasOverlay(on monitor: MonitorInfo) -> Bool {
        guard let uuid = DisplayIdentity.uuid(for: monitor.id) else { return false }
        return intents[uuid] != nil
    }

    /// Re-deploy overlays that were active in a previous run, for any of those
    /// displays currently connected. Call once at launch after enumerating.
    func restorePersisted(using monitors: [MonitorInfo]) {
        guard !desiredUUIDs.isEmpty else { return }
        for monitor in monitors {
            if let uuid = DisplayIdentity.uuid(for: monitor.id), desiredUUIDs.contains(uuid) {
                open(on: monitor)
            }
        }
    }

    /// Call right before terminating so the persisted selection is preserved
    /// through window teardown.
    func prepareForQuit() {
        isQuitting = true
    }

    private func publish() {
        overlayUUIDs = Set(intents.keys)
    }

    /// Open (or focus) a borderless full-screen web window pinned to the given
    /// monitor. Passing nil uses the URL currently set in `OverlaySettings`.
    func open(on monitor: MonitorInfo, url: URL? = nil) {
        wireIfNeeded()

        guard let uuid = DisplayIdentity.uuid(for: monitor.id),
              let screen = NSScreen.screen(for: monitor.id) else {
            NSSound.beep()
            return
        }

        // Already tracking this physical display? Show/recreate it.
        if let intent = intents[uuid] {
            reinstate(intent, on: screen)
            return
        }

        let targetURL = url ?? OverlaySettings.shared.overlayURL
        let controller = WebWindowController(screen: screen, displayUUID: uuid, url: targetURL)
        intents[uuid] = OverlayIntent(uuid: uuid, url: targetURL, controller: controller, displayID: monitor.id)
        desiredUUIDs.insert(uuid)
        publish()
        controller.present()
    }

    /// Destroy the overlay on this monitor from the main window (no lifecycle
    /// hand-off — the main window is already in front). Removing the intent first
    /// makes the ensuing `windowClosed` a no-op.
    func destroy(on monitor: MonitorInfo) {
        guard let uuid = DisplayIdentity.uuid(for: monitor.id),
              let intent = intents.removeValue(forKey: uuid) else { return }
        desiredUUIDs.remove(uuid)
        publish()
        intent.controller?.close()
    }

    /// Apply a page-zoom level to every deployed overlay live.
    func applyZoom(_ zoom: Double) {
        for intent in intents.values {
            intent.controller?.setZoom(zoom)
        }
    }

    /// Point every deployed overlay at a new URL and reload it live.
    func reload(url: URL) {
        for intent in intents.values {
            intent.url = url          // so a recreate-on-reconnect uses the new URL
            intent.controller?.load(url)
        }
    }

    /// A window closed. If its display is still present (and we hadn't already
    /// hidden it for a disconnect), it's a genuine user close → forget it.
    /// Otherwise the display went away → keep the intent so we can restore it.
    func windowClosed(uuid: String) {
        // During quit, windows close as part of teardown — don't touch the
        // persisted selection or trigger lifecycle transitions.
        guard !isQuitting else { return }
        guard let intent = intents[uuid] else { return }
        let displayGone = NSScreen.screen(forUUID: uuid) == nil

        if intent.hidden || displayGone {
            // Disconnect-driven teardown: keep the intent, drop the dead window.
            intent.controller = nil
            intent.hidden = true
            return
        }

        // Genuine user close (Esc): forget it, and stop remembering the selection.
        intents[uuid] = nil
        desiredUUIDs.remove(uuid)
        publish()
        if intents.isEmpty {
            MainWindowCoordinator.shared.overlaysDidFinish()
        }
    }

    // MARK: Wiring

    private func wireIfNeeded() {
        guard !wired else { return }
        wired = true

        // Precise, early per-display notifications.
        CGDisplayRegisterReconfigurationCallback(reconfigurationCallback, nil)

        // Reliable NSScreen re-query (frames are updated by the time this fires).
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reconcile()
        }
    }

    // MARK: CG callback

    /// Fast path: hide/close immediately when our display is pulled, before the
    /// OS visibly migrates the window to another screen.
    func handleReconfiguration(display: CGDirectDisplayID, flags: CGDisplayChangeSummaryFlags) {
        guard flags.contains(.removeFlag) else { return }
        if let intent = intents.values.first(where: { $0.currentDisplayID == display && !$0.hidden }) {
            handleDisappear(intent)
        }
    }

    // MARK: Notification-driven reconciliation

    /// Diff current screens against tracked intents: restore returning displays,
    /// hide/close vanished ones, and keep frames fresh on rearrange.
    private func reconcile() {
        var screensByUUID: [String: NSScreen] = [:]
        for screen in NSScreen.screens {
            if let uuid = screen.displayUUID { screensByUUID[uuid] = screen }
        }

        for intent in intents.values {
            if let screen = screensByUUID[intent.uuid] {
                if intent.hidden {
                    // Its display is back — restore the overlay on it.
                    reinstate(intent, on: screen)
                } else {
                    // Resolution / arrangement may have changed — re-pin the frame.
                    intent.currentDisplayID = screen.displayID
                    intent.controller?.reposition(to: screen)
                }
            } else if !intent.hidden {
                // Fallback in case the CG callback didn't catch the removal.
                handleDisappear(intent)
            }
        }
    }

    /// A disconnect never destroys the intent — it only hides the window. The OS
    /// may still tear the window down (routed through `windowClosed`), which is
    /// fine: the intent survives and is recreated on reconnect.
    private func handleDisappear(_ intent: OverlayIntent) {
        intent.hidden = true
        intent.controller?.hide()
    }

    /// Show the overlay on `screen`, recreating the window if the OS destroyed it.
    private func reinstate(_ intent: OverlayIntent, on screen: NSScreen) {
        intent.hidden = false
        intent.currentDisplayID = screen.displayID

        if let controller = intent.controller {
            controller.reposition(to: screen)
            controller.present()
        } else {
            let controller = WebWindowController(screen: screen, displayUUID: intent.uuid, url: intent.url)
            intent.controller = controller
            controller.present()
        }
    }
}

// MARK: - NSScreen lookup

extension NSScreen {
    /// Find the live NSScreen backing a given display ID.
    static func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { $0.displayID == displayID }
    }

    /// Find the live NSScreen for a stable display UUID.
    static func screen(forUUID uuid: String) -> NSScreen? {
        NSScreen.screens.first { $0.displayUUID == uuid }
    }
}
