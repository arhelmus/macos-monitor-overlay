# macos-monitor-overlay

A tiny native macOS app that opens a borderless, edge-to-edge web view on a specific
physical monitor — covering the menu bar and Dock — and keeps it pinned there.

**Why:** for kiosks, dashboards, signage, and status screens you want a full-bleed web
page locked to one display that survives the monitor being turned off. Overlays are
pinned by the display's stable UUID, so if a monitor disconnects the overlay hides and
**auto-restores on the same physical display** when it reconnects (the process stays
alive the whole time).

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
      --auto-restore <val>   on|off|true|false|yes|no  (default: on)
      --no-auto-restore      Shorthand for --auto-restore off
  -u, --url <url>            Overlay URL (default: https://www.google.com)
  -h, --help                 Show help and exit
```

When `--monitor` resolves to a real display, the main window never appears.

```bash
# Open apple.com full screen on display id 1 (scheme auto-added for bare hosts)
swift run "Monitor Overlay" --monitor id:1 --url apple.com

# Open on the second listed monitor, don't auto-restore on reconnect
swift run "Monitor Overlay" -m 2 --no-auto-restore

# Just launch the picker window
swift run "Monitor Overlay"
```

## Development

Requires macOS 13+ and a Swift 5.9+ toolchain (Xcode command-line tools).

```bash
swift build                           # build
swift run "Monitor Overlay" [options] # build & run
swift build -c release                # release binary in .build/release/
```