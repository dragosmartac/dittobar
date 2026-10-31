import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct LayoutSettingsView: View {
    @AppStorage(DisplayPreferences.panelWidthFractionKey)
    private var panelWidthFraction = DisplayPreferences.defaultPanelWidthFraction

    var body: some View {
        SettingsPane(isUsingDefaults: isUsingDefaults, reset: reset) {
            layout
        }
    }

    private var layout: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Layout")
                .font(.title2.bold())

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
    }

    private func reset() {
        panelWidthFraction = DisplayPreferences.defaultPanelWidthFraction
    }
}
