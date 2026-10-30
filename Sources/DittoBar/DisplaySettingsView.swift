import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DisplaySettingsView: View {
    @ObservedObject var store: CheatSheetStore
    @State private var isChoosingSheetsDirectory = false
    @State private var directoryError: String?
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
    @AppStorage(EditorPreferences.includeInstructionsKey)
    private var includeInstructions = EditorPreferences.defaultIncludeInstructions

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
        .fileImporter(
            isPresented: $isChoosingSheetsDirectory,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            do {
                if let url = try result.get().first {
                    try store.setSheetsDirectory(url)
                }
            } catch {
                directoryError = error.localizedDescription
            }
        }
        .alert("Could Not Open Sheets Folder", isPresented: Binding(
            get: { directoryError != nil },
            set: { if !$0 { directoryError = nil } }
        )) {
            Button("OK", role: .cancel) { directoryError = nil }
        } message: {
            Text(directoryError ?? "")
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
                HStack(spacing: 10) {
                    Image(systemName: tab.systemImage)
                        .frame(width: 20)
                        .accessibilityHidden(true)
                    Text(tab.title)
                }
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
            case .sheets:
                sheets
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

    private var sheets: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Sheets")
                .font(.title2.bold())

            Text("Choose the folder containing your Markdown cheat sheets.")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Sheets Folder")
                    .font(.headline)
                Text(store.folderURL.path)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button("Choose Folder…") {
                isChoosingSheetsDirectory = true
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

            Divider()

            HStack {
                Text("Include top-level instructions when creating a new sheet")
                    .lineLimit(1)
                Spacer()
                Toggle("Include top-level instructions with new sheets", isOn: $includeInstructions)
                    .labelsHidden()
                    .toggleStyle(.switch)
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
        case .sheets:
            store.folderURL.standardizedFileURL == store.defaultFolderURL.standardizedFileURL
        case .editor:
            selectedEditor == EditorPreferences.defaultEditor.rawValue
                && customEditorPath.isEmpty
                && includeInstructions == EditorPreferences.defaultIncludeInstructions
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
        case .sheets:
            do {
                try store.resetSheetsDirectory()
            } catch {
                directoryError = error.localizedDescription
            }
        case .editor:
            selectedEditor = EditorPreferences.defaultEditor.rawValue
            customEditorPath = ""
            includeInstructions = EditorPreferences.defaultIncludeInstructions
        case .shortcuts:
            break
        }
    }

}

private enum SettingsTab: String, CaseIterable, Identifiable {
    case layout
    case text
    case editor
    case sheets
    case shortcuts

    var id: Self { self }

    var title: String {
        switch self {
        case .layout: "Layout"
        case .text: "Text"
        case .sheets: "Sheets"
        case .editor: "Editor"
        case .shortcuts: "Shortcuts"
        }
    }

    var systemImage: String {
        switch self {
        case .layout: "rectangle.split.2x1"
        case .text: "textformat.size"
        case .sheets: "folder"
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
            Shortcut(title: "Copy or open, or fill in variables first", keys: [["↩"]]),
            Shortcut(title: "Copy or open with the current variable values", keys: [["⌘", "↩"]]),
            Shortcut(title: "Show all actions", keys: [["⌥", "↩"]])
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
