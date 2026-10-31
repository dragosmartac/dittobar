import Foundation
import Testing
@testable import DittoBar

@MainActor
struct SheetsDirectoryTests {
    @Test func switchingFoldersReloadsPersistsAndResetsSelection() throws {
        try withStore { store, defaults, root in
            let custom = root.appendingPathComponent("Custom")
            try FileManager.default.createDirectory(at: custom, withIntermediateDirectories: true)
            try "# Custom\n\n### Example\nHello".write(
                to: custom.appendingPathComponent("example.md"), atomically: true, encoding: .utf8
            )
            let originalFiles = try FileManager.default.contentsOfDirectory(atPath: store.folderURL.path)
            store.query = "no matches"
            store.selectedItemIndex = 42

            try store.setSheetsDirectory(custom)

            #expect(store.folderURL == custom.standardizedFileURL)
            #expect(store.selectedEntry?.title == "Example")
            #expect(store.query.isEmpty)
            #expect(defaults.string(forKey: CheatSheetStore.sheetsDirectoryPathKey) == custom.path)
            #expect(try FileManager.default.contentsOfDirectory(atPath: store.defaultFolderURL.path) == originalFiles)

            let reopened = CheatSheetStore(defaults: defaults)
            #expect(reopened.folderURL.path == custom.path)
            #expect(reopened.selectedEntry?.title == "Example")

            try store.resetSheetsDirectory()
            #expect(store.folderURL == store.defaultFolderURL.standardizedFileURL)
            #expect(defaults.object(forKey: CheatSheetStore.sheetsDirectoryPathKey) == nil)
            #expect(!store.sheets.isEmpty)
        }
    }

    @Test func emptyCustomFolderStaysEmptyIncludingAfterRelaunch() throws {
        try withStore { store, defaults, root in
            let custom = root.appendingPathComponent("Empty")
            try FileManager.default.createDirectory(at: custom, withIntermediateDirectories: true)
            try store.setSheetsDirectory(custom)
            #expect(store.sheets.isEmpty)
            let reopened = CheatSheetStore(defaults: defaults)
            #expect(reopened.sheets.isEmpty)
            #expect(try FileManager.default.contentsOfDirectory(atPath: custom.path).isEmpty)
        }
    }

    @Test func invalidFolderDoesNotChangeActiveFolderOrPreference() throws {
        try withStore { store, defaults, root in
            let original = store.folderURL
            let saved = store.savedFolderURLs
            #expect(throws: (any Error).self) {
                try store.setSheetsDirectory(root.appendingPathComponent("Missing"))
            }
            #expect(store.folderURL == original)
            #expect(store.savedFolderURLs == saved)
            #expect(defaults.object(forKey: CheatSheetStore.sheetsDirectoryPathKey) == nil)
            #expect(!store.sheets.isEmpty)
        }
    }

    @Test func savedFoldersPersistWithoutDuplicatesAndSurviveReset() throws {
        try withStore { store, defaults, root in
            let original = store.folderURL.standardizedFileURL
            #expect(store.savedFolderURLs == [original])
            let custom = root.appendingPathComponent("Custom", isDirectory: true)
            try FileManager.default.createDirectory(at: custom, withIntermediateDirectories: true)
            try store.setSheetsDirectory(custom)
            try store.setSheetsDirectory(custom.appendingPathComponent(".", isDirectory: true))
            #expect(store.savedFolderURLs == [original, custom.standardizedFileURL])

            let reopened = CheatSheetStore(defaults: defaults)
            #expect(reopened.savedFolderURLs == store.savedFolderURLs)
            try store.resetSheetsDirectory()
            #expect(store.savedFolderURLs == [original, custom.standardizedFileURL])
        }
    }

    @Test func removingActiveSavedFolderPreservesFilesAndStaysRemovedAfterRelaunch() throws {
        try withStore { store, defaults, root in
            let custom = root.appendingPathComponent("Custom", isDirectory: true)
            try FileManager.default.createDirectory(at: custom, withIntermediateDirectories: true)
            let file = custom.appendingPathComponent("example.md")
            try "# Example".write(to: file, atomically: true, encoding: .utf8)
            try store.setSheetsDirectory(custom)
            for url in store.savedFolderURLs {
                store.removeSavedFolder(url)
            }
            #expect(store.savedFolderURLs.isEmpty)
            #expect(store.folderURL == custom.standardizedFileURL)
            #expect(try String(contentsOf: file, encoding: .utf8) == "# Example")

            let reopened = CheatSheetStore(defaults: defaults)
            #expect(reopened.savedFolderURLs.isEmpty)
            #expect(reopened.folderURL == custom.standardizedFileURL)
            try reopened.setSheetsDirectory(custom)
            #expect(reopened.savedFolderURLs == [custom.standardizedFileURL])
        }
    }

    @Test func existingActiveFolderSeedsSavedFolders() throws {
        try withStore { _, defaults, root in
            let custom = root.appendingPathComponent("Existing", isDirectory: true)
            try FileManager.default.createDirectory(at: custom, withIntermediateDirectories: true)
            defaults.set(custom.path, forKey: CheatSheetStore.sheetsDirectoryPathKey)
            defaults.removeObject(forKey: CheatSheetStore.savedSheetsDirectoryPathsKey)

            let reopened = CheatSheetStore(defaults: defaults)
            #expect(reopened.savedFolderURLs == [custom.standardizedFileURL])
            #expect(defaults.stringArray(forKey: CheatSheetStore.savedSheetsDirectoryPathsKey) == [custom.path])
        }
    }

    private func withStore(_ body: (CheatSheetStore, UserDefaults, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suiteName = "SheetsDirectoryTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }
        let store = CheatSheetStore(fileManager: DirectoryTestFileManager(root: root), defaults: defaults)
        try body(store, defaults, root)
    }
}

private final class DirectoryTestFileManager: FileManager, @unchecked Sendable {
    let root: URL

    init(root: URL) {
        self.root = root
        super.init()
    }

    override func urls(for directory: FileManager.SearchPathDirectory, in domainMask: FileManager.SearchPathDomainMask) -> [URL] {
        [root]
    }
}
