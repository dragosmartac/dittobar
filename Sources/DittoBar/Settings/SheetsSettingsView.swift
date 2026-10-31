import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SheetsSettingsView: View {
    @ObservedObject var store: CheatSheetStore
    @State private var isChoosingSheetsDirectory = false
    @State private var directoryError: String?

    var body: some View {
        SettingsPane(isUsingDefaults: isUsingDefaults, reset: reset) {
            sheets
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

    private var sheets: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Sheets")
                .font(.title2.bold())

            VStack(alignment: .leading, spacing: 8) {
                Text("Sheets Folder")
                    .font(.headline)
                Text("Folder containing your Markdown cheat sheets.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

    private var isUsingDefaults: Bool {
        store.folderURL.standardizedFileURL == store.defaultFolderURL.standardizedFileURL
    }

    private func reset() {
        do {
            try store.resetSheetsDirectory()
        } catch {
            directoryError = error.localizedDescription
        }
    }
}
