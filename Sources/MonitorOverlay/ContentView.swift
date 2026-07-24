import SwiftUI

struct ContentView: View {
    @State private var monitors: [MonitorInfo] = MonitorInfo.all()
    @ObservedObject private var settings = OverlaySettings.shared
    @ObservedObject private var manager = WebWindowManager.shared
    @State private var urlApplyWorkItem: DispatchWorkItem?

    var body: some View {
        // The whole page scrolls as one; credits stay pinned to the bottom when
        // content is short, and scroll normally when it isn't.
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 12)

                    if monitors.isEmpty {
                        Text("No monitors detected.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(monitors) { monitor in
                                let deployed = manager.overlayUUIDs.contains(
                                    DisplayIdentity.uuid(for: monitor.id) ?? "")
                                Button {
                                    if deployed {
                                        WebWindowManager.shared.destroy(on: monitor)
                                    } else {
                                        WebWindowManager.shared.open(on: monitor)
                                    }
                                } label: {
                                    MonitorRow(monitor: monitor, isDeployed: deployed)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    }

                    optionsGroup
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)

                    Spacer(minLength: 0)

                    creditsGroup
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                }
                .frame(minHeight: proxy.size.height, alignment: .top)
                .background(
                    // Click on any empty area to dismiss text-field focus.
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { NSApp.keyWindow?.makeFirstResponder(nil) }
                )
            }
        }
        .onChange(of: settings.webZoom) { newValue in
            WebWindowManager.shared.applyZoom(newValue)
        }
        .onChange(of: settings.overlayURLString) { _ in
            scheduleURLApply()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didChangeScreenParametersNotification)
        ) { _ in
            monitors = MonitorInfo.all()
        }
    }

    private func applyURL() {
        urlApplyWorkItem?.cancel()
        WebWindowManager.shared.reload(url: settings.overlayURL)
    }

    /// Debounce live URL edits so we reload deployed overlays only after typing settles.
    private func scheduleURLApply() {
        urlApplyWorkItem?.cancel()
        let work = DispatchWorkItem {
            WebWindowManager.shared.reload(url: settings.overlayURL)
        }
        urlApplyWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
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
        }
    }

    private var optionsGroup: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(spacing: 0) {
                settingRow {
                    Text("Web Page")
                    // Push the field to the right, keeping it ~half the row width.
                    Spacer(minLength: 0)
                        .frame(maxWidth: .infinity)
                    TextField("https://example.com", text: $settings.overlayURLString)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled(true)
                        .onSubmit(applyURL)
                        .frame(width: 280)
                }

                rowDivider

                settingRow {
                    Text("Scaling")
                    Spacer()
                    Picker("Scaling", selection: $settings.webZoom) {
                        ForEach(OverlaySettings.zoomLevels, id: \.self) { level in
                            Text("\(Int(level * 100))%").tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 280)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.primary.opacity(0.1))
            )
        }
    }

    /// One card row: label-left / control-right, native padding.
    private func settingRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 12) {
            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    /// A divider inset on the leading edge (aligned to the label) but flush right,
    /// matching macOS grouped-list separators.
    private var rowDivider: some View {
        Divider().padding(.leading, 16)
    }

    private var creditsGroup: some View {
        Link(destination: URL(string: "https://github.com/arhelmus/macos-monitor-overlay")!) {
            Text("Made with ♥ by @arhelmus · github.com/arhelmus/macos-monitor-overlay")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .center)
        .onHover { inside in
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}

struct MonitorRow: View {
    let monitor: MonitorInfo
    let isDeployed: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isDeployed ? "checkmark.square.fill" : "square")
                .font(.title2)
                .foregroundStyle(isDeployed ? Color.green : Color.secondary)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(monitor.name)
                        .font(.title3.weight(.semibold))
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

                specColumn("Position", "(\(Int(monitor.frame.origin.x)), \(Int(monitor.frame.origin.y)))")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
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
            .padding(.horizontal, 8)
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
    ContentView()
}
