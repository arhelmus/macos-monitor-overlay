# macos-monitor-overlay

![Monitor Overlay](https://github.com/arhelmus/macos-monitor-overlay/blob/main/assets/example.png?raw=true)

A tiny native macOS app that opens a borderless, edge-to-edge web view on a specific
physical monitor — covering the menu bar and Dock — and keeps it pinned there.

**Why:** for kiosks, dashboards, signage, and status screens you want a full-bleed web
page locked to one display that survives the monitor being turned off. Overlays are
pinned by the display's stable UUID, so if a monitor disconnects the overlay hides and
**restores on the same physical display** when it reconnects (the process stays
alive the whole time). This is the **Persist overlay** setting.

On launch it enumerates every connected display (name, resolution, scale, refresh,
position). Click a monitor — or pass `--monitor` — to open the overlay there. Press
**Esc** to close an overlay; quit anytime from the menu-bar icon.

## CLI

```
macos-monitor-overlay [options]

  -m, --monitor <selector>   Auto-open an overlay on a monitor at launch:
                               <n>          1-based index in the printed list
                               main         the current main display
                               id:<id>      a CGDirectDisplayID
                               uuid:<uuid>  a stable display UUID
  -u, --url <url>            Overlay URL (default: https://www.google.com)
      --restart              Terminate a running instance and take over
  -h, --help                 Show help and exit
```

When `--monitor` resolves to a real display, the main window never appears.

```bash
# Open apple.com full screen on display id 1 (scheme auto-added for bare hosts)
swift run MonitorOverlay --monitor id:1 --url apple.com

# Replace a running instance
swift run MonitorOverlay --restart

# Just launch the picker window
swift run MonitorOverlay
```

## Development

Requires macOS 13+ and a Swift 5.9+ toolchain (Xcode command-line tools).

```bash
swift build                           # build
swift run MonitorOverlay [options] # build & run
swift build -c release                # release binary in .build/release/
```