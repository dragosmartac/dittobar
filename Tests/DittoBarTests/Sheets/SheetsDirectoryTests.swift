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
            #expect(throws: (any Error).self) {
                try store.setSheetsDirectory(root.appendingPathComponent("Missing"))
            }
            #expect(store.folderURL == original)
            #expect(defaults.object(forKey: CheatSheetStore.sheetsDirectoryPathKey) == nil)
            #expect(!store.sheets.isEmpty)
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
