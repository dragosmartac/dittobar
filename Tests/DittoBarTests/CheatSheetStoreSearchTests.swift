import Foundation
import Testing
@testable import DittoBar

@MainActor
struct CheatSheetStoreSearchTests {
    @Test func emptyQueryPreservesEntryAndSectionOrder() throws {
        try withStore { store in
            #expect(itemDescriptions(store.visibleItems) == [
                "entry:Before sections",
                "section:First empty section",
                "section:Second empty section",
                "section:Git tools",
                "entry:Clone repository",
                "entry:Deploy service",
                "entry:Formatted note",
                "section:Trailing empty section"
            ])
            #expect(store.visibleEntries.map(\.title) == [
                "Before sections",
                "Clone repository",
                "Deploy service",
                "Formatted note"
            ])
        }
    }

    @Test func matchingEntryIncludesItsSection() throws {
        try withStore { store in
            store.query = "  cLoNe RePoSiToRy  "

            #expect(itemDescriptions(store.visibleItems) == [
                "section:Git tools",
                "entry:Clone repository"
            ])
            #expect(store.visibleEntries.map(\.title) == ["Clone repository"])
        }
    }

    @Test func matchingSectionIncludesAllItsEntries() throws {
        try withStore { store in
            store.query = "git tools"

            #expect(itemDescriptions(store.visibleItems) == [
                "section:Git tools",
                "entry:Clone repository",
                "entry:Deploy service",
                "entry:Formatted note"
            ])
            #expect(store.visibleEntries.map(\.title) == [
                "Clone repository",
                "Deploy service",
                "Formatted note"
            ])
        }
    }

    @Test func matchingEmptySectionKeepsTheSectionVisible() throws {
        try withStore { store in
            store.query = "first empty section"

            #expect(itemDescriptions(store.visibleItems) == ["section:First empty section"])
            #expect(store.visibleEntries.isEmpty)
        }
    }

    @Test func noMatchReturnsNoEntriesOrItems() throws {
        try withStore { store in
            store.query = "does not exist"

            #expect(store.visibleEntries.isEmpty)
            #expect(store.visibleItems.isEmpty)
        }
    }

    @Test func searchesRawResolvedAndMarkdownStrippedText() throws {
        try withStore { store in
            store.query = "{{env=prod}}"
            #expect(store.visibleEntries.map(\.title) == ["Deploy service"])

            store.query = "deploy-prod"
            #expect(store.visibleEntries.map(\.title) == ["Deploy service"])

            store.query = "Deploy now safely."
            #expect(store.visibleEntries.map(\.title) == ["Formatted note"])
        }
    }

    @Test func selectionMovesWithinFilteredEntryIndexesAndWraps() throws {
        try withStore { store in
            store.query = "git tools"
            store.selectedEntryIndex = 0

            store.moveSelection(by: 1)
            #expect(store.selectedEntry?.title == "Deploy service")

            store.moveSelection(by: 2)
            #expect(store.selectedEntry?.title == "Clone repository")

            store.moveSelection(by: -1)
            #expect(store.selectedEntry?.title == "Formatted note")
        }
    }

    private func itemDescriptions(_ items: [CheatSheetItem]) -> [String] {
        items.map { item in
            switch item {
            case .section(let section):
                return "section:\(section.title)"
            case .entry(let entry):
                return "entry:\(entry.title)"
            }
        }
    }

    private func withStore(_ assertions: (CheatSheetStore) throws -> Void) throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("DittoBarSearchTests-\(UUID().uuidString)", isDirectory: true)
        let cheatSheetsURL = rootURL
            .appendingPathComponent("DittoBar", isDirectory: true)
            .appendingPathComponent("CheatSheets", isDirectory: true)
        try FileManager.default.createDirectory(
            at: cheatSheetsURL,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let sourceURL = cheatSheetsURL.appendingPathComponent("search.md")
        try Self.source.write(to: sourceURL, atomically: true, encoding: .utf8)

        do {
            let fileManager = TestFileManager(applicationSupportURL: rootURL)
            let store = CheatSheetStore(fileManager: fileManager)
            try assertions(store)
        }
    }

    private static let source = """
    # Search Characterization

    ### Before sections
    This entry appears before every section.

    ## First empty section
    ## Second empty section

    ## Git tools
    ### Clone repository
    Fetch a remote repository.

    ### Deploy service
    Run deploy-{{env=prod}}.

    ### Formatted note
    Deploy **now** safely.

    ## Trailing empty section
    """
}

private final class TestFileManager: FileManager, @unchecked Sendable {
    private let applicationSupportURL: URL

    init(applicationSupportURL: URL) {
        self.applicationSupportURL = applicationSupportURL
        super.init()
    }

    override func urls(
        for directory: FileManager.SearchPathDirectory,
        in domainMask: FileManager.SearchPathDomainMask
    ) -> [URL] {
        [applicationSupportURL]
    }
}
