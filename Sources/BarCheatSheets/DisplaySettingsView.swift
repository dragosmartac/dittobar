import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DisplaySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: SettingsTab? = .layout
    @State private var isChoosingCustomEditor = false

    @AppStorage(DisplayPreferences.titleFontSizeKey)
    private var titleFontSize = DisplayPreferences.defaultTitleFontSize
    @AppStorage(DisplayPreferences.descriptionFontSizeKey)
    private var descriptionFontSize = DisplayPreferences.defaultDescriptionFontSize
    @AppStorage(DisplayPreferences.commandFontSizeKey)
    private var commandFontSize = DisplayPreferences.defaultCommandFontSize
    @AppStorage(DisplayPreferences.popoverWidthFractionKey)
    private var popoverWidthFraction = DisplayPreferences.defaultPopoverWidthFraction
    @AppStorage(EditorPreferences.selectedEditorKey)
    private var selectedEditor = EditorPreferences.defaultEditor.rawValue
    @AppStorage(EditorPreferences.customEditorPathKey)
    private var customEditorPath = ""

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            detail
        }
        .frame(width: 680, height: 410)
        .fileImporter(
            isPresented: $isChoosingCustomEditor,
            allowedContentTypes: [.applicationBundle],
            allowsMultipleSelection: false
        ) { result in
            guard case let .success(urls) = result, let applicationURL = urls.first else {
                return
            }
            customEditorPath = applicationURL.path
            selectedEditor = EditorOption.custom.rawValue
        }
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
            switch selectedTab ?? .layout {
            case .layout:
                layout
            case .textSizes:
                textSizes
            case .editor:
                editor
            }

            Spacer(minLength: 0)

            Divider()

            HStack {
                Button("Reset to Defaults") {
                    resetSelectedTab()
                }
                .disabled(selectedTabIsUsingDefaults)

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

    private var layout: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Layout")
                .font(.title2.bold())

            Text("Choose how far the dropdown expands horizontally.")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Popover Width")
                    Spacer()
                    Text("\(Int((popoverWidthFraction * 100).rounded()))%")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Slider(
                    value: $popoverWidthFraction,
                    in: DisplayPreferences.popoverWidthFractionRange,
                    step: 0.05
                )
                .accessibilityLabel("Popover width")
                .accessibilityValue(
                    "\(Int((popoverWidthFraction * 100).rounded())) percent of the screen"
                )
            }
        }
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

    private var editor: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Editor")
                .font(.title2.bold())

            Text("Choose the application used to open new and existing cheat sheets.")
                .foregroundStyle(.secondary)

            Picker("Editor", selection: $selectedEditor) {
                ForEach(EditorOption.allCases) { editor in
                    Text(editor.title).tag(editor.rawValue)
                }
            }
            .pickerStyle(.radioGroup)

            if selectedEditor == EditorOption.custom.rawValue {
                HStack {
                    Text(customEditorPath.isEmpty
                        ? "No application selected"
                        : URL(fileURLWithPath: customEditorPath).lastPathComponent)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer()

                    Button(customEditorPath.isEmpty ? "Choose Application…" : "Change Application…") {
                        isChoosingCustomEditor = true
                    }
                }
            }
        }
    }

    private var selectedTabIsUsingDefaults: Bool {
        switch selectedTab ?? .layout {
        case .layout:
            popoverWidthFraction == DisplayPreferences.defaultPopoverWidthFraction
        case .textSizes:
            titleFontSize == DisplayPreferences.defaultTitleFontSize
                && descriptionFontSize == DisplayPreferences.defaultDescriptionFontSize
                && commandFontSize == DisplayPreferences.defaultCommandFontSize
        case .editor:
            selectedEditor == EditorPreferences.defaultEditor.rawValue
                && customEditorPath.isEmpty
        }
    }

    private func resetSelectedTab() {
        switch selectedTab ?? .layout {
        case .layout:
            popoverWidthFraction = DisplayPreferences.defaultPopoverWidthFraction
        case .textSizes:
            titleFontSize = DisplayPreferences.defaultTitleFontSize
            descriptionFontSize = DisplayPreferences.defaultDescriptionFontSize
            commandFontSize = DisplayPreferences.defaultCommandFontSize
        case .editor:
            selectedEditor = EditorPreferences.defaultEditor.rawValue
            customEditorPath = ""
        }
    }

}

private enum SettingsTab: String, CaseIterable, Identifiable {
    case layout
    case textSizes
    case editor

    var id: Self { self }

    var title: String {
        switch self {
        case .layout: "Layout"
        case .textSizes: "Text Sizes"
        case .editor: "Editor"
        }
    }

    var systemImage: String {
        switch self {
        case .layout: "rectangle.expand.horizontal"
        case .textSizes: "textformat.size"
        case .editor: "square.and.pencil"
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
