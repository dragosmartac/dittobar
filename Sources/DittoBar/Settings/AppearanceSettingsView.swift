import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AppearanceSettingsView: View {
    @AppStorage(DisplayPreferences.panelWidthFractionKey)
    private var panelWidthFraction = DisplayPreferences.defaultPanelWidthFraction

    @AppStorage(DisplayPreferences.accentColorKey)
    private var accentColorValue = ""
    @StateObject private var colorPanel = AccentColorPanelController()

    var body: some View {
        SettingsPane(isUsingDefaults: isUsingDefaults, reset: reset) {
            appearance
        }
        .background {
            SettingsWindowAnchor(controller: colorPanel)
                .frame(width: 0, height: 0)
        }
        .onDisappear { colorPanel.close() }
        .onChange(of: accentColorValue) { _, value in
            colorPanel.updateColor(DisplayPreferences.accentColor(from: value))
        }
    }

    private var appearance: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Appearance")
                .font(.title2.bold())

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Accent Colour")
                    Text("Used for highlights, selections, and badges.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    accentColorValue = ""
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(accentColorValue.isEmpty)
                .help("Restore the default orange accent")
                .accessibilityLabel("Reset accent colour to default")

                Button {
                    colorPanel.show(color: DisplayPreferences.accentColor(from: accentColorValue)) { color in
                        accentColorValue = DisplayPreferences.encodeAccentColor(color)
                    }
                } label: {
                    Circle()
                        .fill(Color(nsColor: DisplayPreferences.accentColor(from: accentColorValue)))
                        .overlay {
                            Circle().strokeBorder(Color.primary.opacity(0.2), lineWidth: 1)
                        }
                        .frame(width: 26, height: 26)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Choose accent colour")
                .accessibilityLabel("Choose accent colour")
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Panel Width")
                    Spacer()
                    Text("\(Int((panelWidthFraction * 100).rounded()))%")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Text("Width of the dropdown as a percentage of the screen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Slider(
                    value: $panelWidthFraction,
                    in: DisplayPreferences.panelWidthFractionRange,
                    step: 0.05
                )
                .accessibilityLabel("Panel width")
                .accessibilityValue(
                    "\(Int((panelWidthFraction * 100).rounded())) percent of the screen"
                )
            }
        }
    }

    private var isUsingDefaults: Bool {
        panelWidthFraction == DisplayPreferences.defaultPanelWidthFraction
            && accentColorValue.isEmpty
    }

    private func reset() {
        accentColorValue = ""
        panelWidthFraction = DisplayPreferences.defaultPanelWidthFraction
    }
}

private struct SettingsWindowAnchor: NSViewRepresentable {
    let controller: AccentColorPanelController

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        controller.anchorView = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

@MainActor
private final class AccentColorPanelController: NSObject, ObservableObject {
    weak var anchorView: NSView?
    private var onChange: ((NSColor) -> Void)?
    private var originalLevel: NSWindow.Level?
    private var isUpdatingColor = false

    func show(color: NSColor, onChange: @escaping (NSColor) -> Void) {
        let panel = NSColorPanel.shared
        self.onChange = onChange
        if originalLevel == nil { originalLevel = panel.level }
        panel.showsAlpha = false
        panel.isContinuous = true
        panel.setTarget(self)
        panel.setAction(#selector(colorChanged(_:)))
        updateColor(color)
        // The app's nonactivating panel sits at status-bar level, above a normal colour panel.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        position(panel)
    }

    private func position(_ panel: NSColorPanel) {
        guard let window = anchorView?.window,
              let screen = window.screen else { return }
        let bounds = screen.visibleFrame
        let settings = window.frame
        let size = panel.frame.size
        let gap: CGFloat = 16
        let left = settings.minX - gap - size.width
        let right = settings.maxX + gap
        let preferredX: CGFloat
        if left >= bounds.minX {
            preferredX = left
        } else if right + size.width <= bounds.maxX {
            preferredX = right
        } else {
            preferredX = settings.minX - bounds.minX >= bounds.maxX - settings.maxX ? left : right
        }
        panel.setFrameOrigin(NSPoint(
            x: max(bounds.minX, min(preferredX, bounds.maxX - size.width)),
            y: max(bounds.minY, min(settings.maxY - size.height, bounds.maxY - size.height))
        ))
    }

    func updateColor(_ color: NSColor) {
        guard originalLevel != nil else { return }
        isUpdatingColor = true
        NSColorPanel.shared.color = color
        isUpdatingColor = false
    }

    func close() {
        guard let originalLevel else { return }
        let panel = NSColorPanel.shared
        panel.setTarget(nil)
        panel.setAction(nil)
        panel.close()
        panel.level = originalLevel
        self.originalLevel = nil
        onChange = nil
    }

    @objc private func colorChanged(_ sender: NSColorPanel) {
        guard !isUpdatingColor else { return }
        onChange?(sender.color)
    }
}
