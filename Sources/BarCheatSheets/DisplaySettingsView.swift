import AppKit
import SwiftUI

struct DisplaySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: SettingsTab? = .textSizes

    @AppStorage(DisplayPreferences.titleFontSizeKey)
    private var titleFontSize = DisplayPreferences.defaultTitleFontSize
    @AppStorage(DisplayPreferences.descriptionFontSizeKey)
    private var descriptionFontSize = DisplayPreferences.defaultDescriptionFontSize
    @AppStorage(DisplayPreferences.commandFontSizeKey)
    private var commandFontSize = DisplayPreferences.defaultCommandFontSize

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            detail
        }
        .frame(width: 680, height: 410)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Settings")
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 10)

            List(SettingsTab.allCases, selection: $selectedTab) { tab in
                Label(tab.title, systemImage: tab.systemImage)
                    .tag(tab)
            }
            .listStyle(.sidebar)
        }
        .frame(width: 185)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 18) {
            switch selectedTab ?? .textSizes {
            case .textSizes:
                textSizes
            }

            Spacer(minLength: 0)

            Divider()

            HStack {
                Button("Reset to Defaults") {
                    titleFontSize = DisplayPreferences.defaultTitleFontSize
                    descriptionFontSize = DisplayPreferences.defaultDescriptionFontSize
                    commandFontSize = DisplayPreferences.defaultCommandFontSize
                }
                .disabled(isUsingDefaults)

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var textSizes: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Text Sizes")
                .font(.title2.bold())

            Text("Adjust the text shown in each command row. Changes are applied immediately.")
                .foregroundStyle(.secondary)

            VStack(spacing: 14) {
                FontSizeControl(
                    title: "Title",
                    value: $titleFontSize,
                    range: DisplayPreferences.titleFontSizeRange
                )
                FontSizeControl(
                    title: "Description",
                    value: $descriptionFontSize,
                    range: DisplayPreferences.descriptionFontSizeRange
                )
                FontSizeControl(
                    title: "Command",
                    value: $commandFontSize,
                    range: DisplayPreferences.commandFontSizeRange
                )
            }
        }
    }

    private var isUsingDefaults: Bool {
        titleFontSize == DisplayPreferences.defaultTitleFontSize
            && descriptionFontSize == DisplayPreferences.defaultDescriptionFontSize
            && commandFontSize == DisplayPreferences.defaultCommandFontSize
    }
}

private enum SettingsTab: String, CaseIterable, Identifiable {
    case textSizes

    var id: Self { self }

    var title: String {
        switch self {
        case .textSizes: "Text Sizes"
        }
    }

    var systemImage: String {
        switch self {
        case .textSizes: "textformat.size"
        }
    }
}

private struct FontSizeControl: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value)) pt")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Slider(value: $value, in: range, step: 1)
                .accessibilityLabel("\(title) text size")
                .accessibilityValue("\(Int(value)) points")
        }
    }
}
