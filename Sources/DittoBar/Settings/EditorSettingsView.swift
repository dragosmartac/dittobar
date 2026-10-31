import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct EditorSettingsView: View {
    @AppStorage(EditorPreferences.selectedEditorKey)
    private var selectedEditor = EditorPreferences.defaultEditor.rawValue
    @AppStorage(EditorPreferences.customEditorPathKey)
    private var customEditorPath = ""
    @AppStorage(EditorPreferences.includeInstructionsKey)
    private var includeInstructions = EditorPreferences.defaultIncludeInstructions
    @State private var isChoosingCustomEditor = false

    var body: some View {
        SettingsPane(isUsingDefaults: isUsingDefaults, reset: reset) {
            editor
        }
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

    private var editor: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Editor")
                .font(.title2.bold())

            VStack(alignment: .leading, spacing: 6) {
                Picker("Editor", selection: $selectedEditor) {
                    ForEach(EditorOption.allCases) { editor in
                        Text(editor.title).tag(editor.rawValue)
                    }
                }
                .pickerStyle(.radioGroup)

                Text("Application used to open new and existing sheets.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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

    private var isUsingDefaults: Bool {
        selectedEditor == EditorPreferences.defaultEditor.rawValue
            && customEditorPath.isEmpty
            && includeInstructions == EditorPreferences.defaultIncludeInstructions
    }

    private func reset() {
        selectedEditor = EditorPreferences.defaultEditor.rawValue
        customEditorPath = ""
        includeInstructions = EditorPreferences.defaultIncludeInstructions
    }
}
