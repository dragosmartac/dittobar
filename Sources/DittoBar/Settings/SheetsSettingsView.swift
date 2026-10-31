import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SheetsSettingsView: View {
    @ObservedObject var store: CheatSheetStore
    @AppStorage(EditorPreferences.includeInstructionsKey)
    private var includeInstructions = EditorPreferences.defaultIncludeInstructions
    @State private var isChoosingSheetsDirectory = false
    @State private var directoryError: String?
    @State private var selectedFolderURL: URL?

    var body: some View {
        SettingsPane(isUsingDefaults: isUsingDefaults, reset: reset) {
            sheets
        }
        .onAppear {
            let active = store.folderURL.standardizedFileURL
            selectedFolderURL = store.savedFolderURLs.contains(active) ? active : nil
        }
        .fileImporter(
            isPresented: $isChoosingSheetsDirectory,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            do {
                if let url = try result.get().first {
                    try store.setSheetsDirectory(url)
                    selectedFolderURL = store.folderURL
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

    private var sheets: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Sheets")
                .font(.title2.bold())

            VStack(alignment: .leading, spacing: 8) {
                Text("Saved Folders")
                    .font(.headline)
                Text("Select a folder to show its sheets. Removing it from this list keeps its files.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !store.savedFolderURLs.contains(store.folderURL.standardizedFileURL) {
                Text("Active: \(store.folderURL.path)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(store.folderURL.path)
            }

            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 6) {
                        if store.savedFolderURLs.isEmpty {
                            Text("Add folders here for quick switching.")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                        }
                        ForEach(store.savedFolderURLs, id: \.path) { url in
                            folderRow(url)
                        }
                    }
                    .padding(6)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                HStack(spacing: 12) {
                    Spacer()
                    Button {
                        isChoosingSheetsDirectory = true
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    Button {
                        guard let selectedFolderURL else { return }
                        store.removeSavedFolder(selectedFolderURL)
                        self.selectedFolderURL = nil
                    } label: {
                        Label("Remove", systemImage: "minus")
                    }
                    .disabled(selectedFolderURL == nil)
                    .help("Remove the selected folder from this list; its files are kept")
                }
                .padding(10)
                .background(Color(nsColor: .controlBackgroundColor))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                    .allowsHitTesting(false)
            }

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Include top-level instructions")
                    Text("Added when creating a new sheet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Include top-level instructions with new sheets", isOn: $includeInstructions)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        }
    }

    private func folderRow(_ url: URL) -> some View {
        let isActive = url == store.folderURL.standardizedFileURL
        return HStack(spacing: 8) {
            Button {
                selectedFolderURL = url
                do {
                    try store.setSheetsDirectory(url)
                } catch {
                    directoryError = error.localizedDescription
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "folder")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent)
                            .lineLimit(1)
                        Text(url.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 0)
                    if isActive {
                        Text("Active")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.dittoAccent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.dittoAccent.opacity(0.15), in: Capsule())
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(url.path)
            .accessibilityLabel("\(url.path)\(isActive ? ", active" : "")")

        }
        .padding(10)
        .background(
            selectedFolderURL == url ? Color.dittoAccent.opacity(0.1) : Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 8)
        )
    }

    private var isUsingDefaults: Bool {
        store.folderURL.standardizedFileURL == store.defaultFolderURL.standardizedFileURL
            && includeInstructions == EditorPreferences.defaultIncludeInstructions
    }

    private func reset() {
        includeInstructions = EditorPreferences.defaultIncludeInstructions
        do {
            try store.resetSheetsDirectory()
            selectedFolderURL = store.folderURL
        } catch {
            directoryError = error.localizedDescription
        }
    }
}
