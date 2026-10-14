import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DisplaySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: SettingsTab? = .layout
    @State private var isChoosingCustomEditor = false

    @AppStorage(DisplayPreferences.sectionTitleFontSizeKey)
    private var sectionTitleFontSize = DisplayPreferences.defaultSectionTitleFontSize
    @AppStorage(DisplayPreferences.titleFontSizeKey)
    private var titleFontSize = DisplayPreferences.defaultTitleFontSize
    @AppStorage(DisplayPreferences.descriptionFontSizeKey)
    private var descriptionFontSize = DisplayPreferences.defaultDescriptionFontSize
    @AppStorage(DisplayPreferences.noteFontSizeKey)
    private var noteFontSize = DisplayPreferences.defaultNoteFontSize
    @AppStorage(DisplayPreferences.payloadFontSizeKey)
    private var payloadFontSize = DisplayPreferences.defaultPayloadFontSize
    @AppStorage(DisplayPreferences.popoverWidthFractionKey)
    private var popoverWidthFraction = DisplayPreferences.defaultPopoverWidthFraction
    @AppStorage(DisplayPreferences.textFontFamilyKey)
    private var textFontFamily = ""
    @AppStorage(DisplayPreferences.codeFontFamilyKey)
    private var codeFontFamily = ""
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
            case .text:
                text
            case .editor:
                editor
            case .shortcuts:
                shortcuts
            }

            Spacer(minLength: 0)

            Divider()

            HStack {
                if selectedTab != .shortcuts {
                    Button("Reset to Defaults") {
                        resetSelectedTab()
                    }
                    .disabled(selectedTabIsUsingDefaults)
                }

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

    private var text: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Text")
                .font(.title2.bold())

            Text("Adjust the text shown in the list. Changes are applied immediately.")
                .foregroundStyle(.secondary)

            ScrollView(.vertical) {
                VStack(spacing: 14) {
                    FontFamilyPicker(
                        title: "Text Font",
                        families: EntryFonts.installedFamilies,
                        selection: $textFontFamily
                    )
                    FontFamilyPicker(
                        title: "Code Font",
                        families: EntryFonts.installedMonospacedFamilies,
                        selection: $codeFontFamily
                    )

                    Divider()

                    textSizes
                }
                .padding(.trailing, 12)
            }
        }
    }

    private var textSizes: some View {
        VStack(spacing: 14) {
            FontSizeControl(
                title: "Section Title",
                value: $sectionTitleFontSize,
                range: DisplayPreferences.sectionTitleFontSizeRange
            )
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
                title: "Note",
                value: $noteFontSize,
                range: DisplayPreferences.noteFontSizeRange
            )
            FontSizeControl(
                title: "Payload",
                value: $payloadFontSize,
                range: DisplayPreferences.payloadFontSizeRange
            )
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

    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Shortcuts")
                .font(.title2.bold())

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(ShortcutGroup.all) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.title)
                                .font(.headline)

                            ForEach(group.shortcuts) { shortcut in
                                HStack(alignment: .firstTextBaseline) {
                                    Text(shortcut.title)
                                    Spacer()
                                    ShortcutKeys(alternatives: shortcut.keys)
                                }
                            }
                        }
                    }
                }
                .padding(.trailing, 12)
            }
        }
    }

    private var selectedTabIsUsingDefaults: Bool {
        switch selectedTab ?? .layout {
        case .layout:
            popoverWidthFraction == DisplayPreferences.defaultPopoverWidthFraction
        case .text:
            textFontFamily.isEmpty
                && codeFontFamily.isEmpty
                && sectionTitleFontSize == DisplayPreferences.defaultSectionTitleFontSize
                && titleFontSize == DisplayPreferences.defaultTitleFontSize
                && descriptionFontSize == DisplayPreferences.defaultDescriptionFontSize
                && noteFontSize == DisplayPreferences.defaultNoteFontSize
                && payloadFontSize == DisplayPreferences.defaultPayloadFontSize
        case .editor:
            selectedEditor == EditorPreferences.defaultEditor.rawValue
                && customEditorPath.isEmpty
        case .shortcuts:
            true
        }
    }

    private func resetSelectedTab() {
        switch selectedTab ?? .layout {
        case .layout:
            popoverWidthFraction = DisplayPreferences.defaultPopoverWidthFraction
        case .text:
            textFontFamily = ""
            codeFontFamily = ""
            sectionTitleFontSize = DisplayPreferences.defaultSectionTitleFontSize
            titleFontSize = DisplayPreferences.defaultTitleFontSize
            descriptionFontSize = DisplayPreferences.defaultDescriptionFontSize
            noteFontSize = DisplayPreferences.defaultNoteFontSize
            payloadFontSize = DisplayPreferences.defaultPayloadFontSize
        case .editor:
            selectedEditor = EditorPreferences.defaultEditor.rawValue
            customEditorPath = ""
        case .shortcuts:
            break
        }
    }

}

private enum SettingsTab: String, CaseIterable, Identifiable {
    case layout
    case text
    case editor
    case shortcuts

    var id: Self { self }

    var title: String {
        switch self {
        case .layout: "Layout"
        case .text: "Text"
        case .editor: "Editor"
        case .shortcuts: "Shortcuts"
        }
    }

    var systemImage: String {
        switch self {
        case .layout: "rectangle.expand.horizontal"
        case .text: "textformat.size"
        case .editor: "square.and.pencil"
        case .shortcuts: "keyboard"
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

private struct Shortcut: Identifiable {
    let title: String
    /// Each element is one way to trigger the shortcut, e.g. `["↑", "↓"]`.
    let keys: [[String]]

    var id: String { title }
}

private struct ShortcutGroup: Identifiable {
    let title: String
    let shortcuts: [Shortcut]

    var id: String { title }

    static let all = [
        ShortcutGroup(title: "Anywhere", shortcuts: [
            Shortcut(title: "Show or hide DittoBar", keys: [["⌥", "Space"]])
        ]),
        ShortcutGroup(title: "Navigation", shortcuts: [
            Shortcut(title: "Next entry or section", keys: [["↓"], ["Tab"]]),
            Shortcut(title: "Previous entry or section", keys: [["↑"], ["⇧", "Tab"]]),
            Shortcut(title: "Previous or next sheet", keys: [["⌘", "⌥", "←"], ["⌘", "⌥", "→"]]),
            Shortcut(title: "Go to sheet 1–9", keys: [["⌘", "1–9"]]),
            Shortcut(title: "Search", keys: [["⌘", "F"]]),
            Shortcut(title: "Close", keys: [["Esc"]])
        ]),
        ShortcutGroup(title: "Entries", shortcuts: [
            Shortcut(title: "Copy, or fill in variables first", keys: [["↩"]]),
            Shortcut(title: "Copy with the current variable values", keys: [["⌘", "↩"]]),
            Shortcut(title: "Show copy options", keys: [["⌥", "↩"]])
        ]),
        ShortcutGroup(title: "Sections", shortcuts: [
            Shortcut(title: "Show section actions", keys: [["↩"]])
        ]),
        ShortcutGroup(title: "Variable Form", shortcuts: [
            Shortcut(title: "Next or previous field", keys: [["Tab"], ["⇧", "Tab"]]),
            Shortcut(title: "Copy or open", keys: [["↩"], ["⌘", "↩"]]),
            Shortcut(title: "Cancel", keys: [["Esc"]])
        ]),
        ShortcutGroup(title: "Cheat Sheets", shortcuts: [
            Shortcut(title: "Edit current sheet", keys: [["⌘", "E"]]),
            Shortcut(title: "New sheet", keys: [["⌘", "⇧", "N"]]),
            Shortcut(title: "More options", keys: [["⌘", "⇧", "M"]]),
            Shortcut(title: "Settings", keys: [["⌘", ","]])
        ])
    ]
}

/// Draws each key as a keycap, with alternatives separated by "or".
private struct ShortcutKeys: View {
    let alternatives: [[String]]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(alternatives.enumerated()), id: \.offset) { index, keys in
                if index > 0 {
                    Text("or")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                HStack(spacing: 3) {
                    ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                        Text(key)
                            .font(.system(.callout, design: .rounded).weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .frame(minWidth: 22)
                            .background(
                                Color(nsColor: .controlBackgroundColor),
                                in: RoundedRectangle(cornerRadius: 5)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .strokeBorder(Color(nsColor: .separatorColor))
                            )
                    }
                }
            }
        }
    }
}

/// Lists installed families, with an empty selection meaning the system font.
private struct FontFamilyPicker: View {
    let title: String
    let families: [String]
    @Binding var selection: String

    var body: some View {
        Picker(title, selection: $selection) {
            Text("System").tag("")
            if !selection.isEmpty, !families.contains(selection) {
                Text("\(selection) (not installed)").tag(selection)
            }
            Divider()
            ForEach(families, id: \.self) { family in
                Text(family).tag(family)
            }
        }
    }
}
