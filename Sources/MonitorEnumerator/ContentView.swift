import SwiftUI

struct ContentView: View {
    @State private var monitors: [MonitorInfo] = MonitorInfo.all()
    @ObservedObject private var settings = OverlaySettings.shared
    @ObservedObject private var manager = WebWindowManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            HStack(spacing: 8) {
                Image(systemName: "globe")
                    .foregroundStyle(.secondary)
                TextField("https://example.com", text: $settings.overlayURLString)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled(true)
                    .onSubmit(applyURL)
                Button("Apply", action: applyURL)
                    .disabled(manager.overlayUUIDs.isEmpty)
                    .help("Reload all deployed overlays with this URL")
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)

            Toggle(isOn: $settings.autoRestoreOnReconnect) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Auto-restore on reconnect")
                    Text(settings.autoRestoreOnReconnect
                         ? "On disconnect the overlay hides, then reappears automatically when the monitor comes back."
                         : "On disconnect the overlay hides and stays hidden until you reopen it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.checkbox)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            Divider()

            if monitors.isEmpty {
                Spacer()
                Text("No monitors detected.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(monitors) { monitor in
                            MonitorRow(
                                monitor: monitor,
                                isDeployed: manager.overlayUUIDs.contains(
                                    DisplayIdentity.uuid(for: monitor.id) ?? ""),
                                onOpen: {
                                    WebWindowManager.shared.open(on: monitor)
                                    MainWindowCoordinator.shared.hideForOverlay()
                                },
                                onClose: {
                                    WebWindowManager.shared.destroy(on: monitor)
                                }
                            )
                        }
                    }
                    .padding(16)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didChangeScreenParametersNotification)
        ) { _ in
            monitors = MonitorInfo.all()
        }
    }

    private func applyURL() {
        WebWindowManager.shared.reload(url: settings.overlayURL)
    }

    private var header: some View {
        HStack {
            Image(systemName: "display.2")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Connected Monitors")
                    .font(.headline)
                Text("\(monitors.count) display\(monitors.count == 1 ? "" : "s") detected")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                monitors = MonitorInfo.all()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
        .padding(16)
    }
}

struct MonitorRow: View {
    let monitor: MonitorInfo
    let isDeployed: Bool
    let onOpen: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(monitor.name)
                    .font(.title3.weight(.semibold))
                if monitor.isMain { badge("MAIN", tint: .accentColor) }
                if isDeployed { badge("DEPLOYED", tint: .green) }
                Spacer()
                Text("ID \(String(monitor.id))")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 24) {
                specColumn("Resolution", "\(Int(monitor.pixelSize.width)) × \(Int(monitor.pixelSize.height)) px")
                specColumn("Points", "\(Int(monitor.pointSize.width)) × \(Int(monitor.pointSize.height)) pt")
                specColumn("Scale", "\(monitor.scaleFactor)×")
                specColumn("Refresh", monitor.refreshRate.map { String(format: "%.0f Hz", $0) } ?? "—")
            }

            HStack {
                specColumn("Position", "(\(Int(monitor.frame.origin.x)), \(Int(monitor.frame.origin.y)))")
                Spacer()
                if isDeployed {
                    Button(role: .destructive, action: onClose) {
                        Label("Close overlay", systemImage: "xmark.circle.fill")
                    }
                } else {
                    Button(action: onOpen) {
                        Label("Open full screen", systemImage: "arrow.up.right.square")
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isDeployed ? Color.green.opacity(0.5) : Color.primary.opacity(0.08))
        )
    }

    private func badge(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.2))
            .foregroundStyle(tint)
            .clipShape(Capsule())
    }

    private func specColumn(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.monospacedDigit())
        }
    }
}

#Preview {
    ContentView(
    )
}
