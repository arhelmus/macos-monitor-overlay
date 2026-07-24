import AppKit

/// The app (Dock) icon: the `display` SF Symbol rendered white on a rounded
/// gradient tile, matching the menu-bar glyph.
enum AppIcon {
    static func dockImage() -> NSImage {
        let size = NSSize(width: 512, height: 512)
        let image = NSImage(size: size)
        image.lockFocus()

        let rect = NSRect(origin: .zero, size: size).insetBy(dx: 40, dy: 40)
        let path = NSBezierPath(roundedRect: rect, xRadius: 110, yRadius: 110)
        NSGradient(colors: [
            NSColor(calibratedRed: 0.29, green: 0.56, blue: 0.89, alpha: 1),
            NSColor(calibratedRed: 0.13, green: 0.33, blue: 0.78, alpha: 1),
        ])?.draw(in: path, angle: -90)

        if let symbol = NSImage(systemSymbolName: "display", accessibilityDescription: nil) {
            let cfg = NSImage.SymbolConfiguration(pointSize: 240, weight: .regular)
                .applying(.init(paletteColors: [.white]))
            if let glyph = symbol.withSymbolConfiguration(cfg) {
                let gs = glyph.size
                glyph.draw(in: NSRect(x: (size.width - gs.width) / 2,
                                      y: (size.height - gs.height) / 2,
                                      width: gs.width, height: gs.height))
            }
        }

        image.unlockFocus()
        return image
    }
}
