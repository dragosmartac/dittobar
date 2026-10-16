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
            store.selectFirstEntry()
            #expect(store.selectedEntry?.title == "Clone repository")

            store.moveSelection(by: 1)
            #expect(store.selectedEntry?.title == "Deploy service")

            store.moveSelection(by: 2)
            #expect(store.selectedItem?.section?.title == "Git tools")

            store.moveSelection(by: -1)
            #expect(store.selectedEntry?.title == "Formatted note")
        }
    }

    @Test func onlySectionsWithVisibleEntriesAreSelectable() throws {
        try withStore { store in
            #expect(itemDescriptions(store.selectableItems) == [
                "entry:Before sections",
                "section:Git tools",
                "entry:Clone repository",
                "entry:Deploy service",
                "entry:Formatted note"
            ])

            store.query = "first empty section"
            #expect(store.selectableItems.isEmpty)
        }
    }

    @Test func sectionEntriesStopAtTheNextSectionAndFollowSearch() throws {
        try withStore { store in
            let gitTools = try #require(section(titled: "Git tools", in: store))
            #expect(store.entries(in: gitTools).map(\.title) == [
                "Clone repository",
                "Deploy service",
                "Formatted note"
            ])
            #expect(store.actions(for: gitTools) == [.copyAllEntries, .copyAsMarkdown])

            let emptySection = try #require(section(titled: "First empty section", in: store))
            #expect(store.entries(in: emptySection).isEmpty)
            #expect(store.actions(for: emptySection).isEmpty)

            store.query = "deploy"
            #expect(store.entries(in: gitTools).map(\.title) == [
                "Deploy service",
                "Formatted note"
            ])
        }
    }

    @Test func sectionMarkdownResolvesVariablesAndKeepsFormatting() throws {
        try withStore { store in
            let gitTools = try #require(section(titled: "Git tools", in: store))
            #expect(store.markdown(for: gitTools) == """
            ## Git tools

            ### Clone repository

            Fetch a remote repository.

            ### Deploy service

            Run deploy-prod.

            ### Formatted note

            Deploy **now** safely.
            """)
        }
    }

    @Test func joinedEntryTextsUseBlankLinesOnlyForMultilineTexts() {
        #expect(CheatSheetStore.joinedEntryTexts(["git status", "git log\n"]) == "git status\ngit log")
        #expect(CheatSheetStore.joinedEntryTexts(["one\ntwo", "three"]) == "one\ntwo\n\nthree")
    }

    @Test func fileEntriesAreSearchedAndCopiedAsMarkdown() throws {
        let source = """
        # Research

        ## Notes
        ### Release plan
        The plan for the **next** release.

        ```file
        plans/{{name=release}}.md
        ```

        ### Retro
        ```file
        retro.md
        ```
        """
        try withStore(source: source) { store in
            store.query = "plans/release"

            let notes = try #require(section(titled: "Notes", in: store))
            #expect(store.entries(in: notes).map(\.title) == ["Release plan"])
            #expect(store.actions(for: notes) == [.openAllFiles, .copyAllEntries, .copyAsMarkdown])
            #expect(store.markdown(for: notes) == """
            ## Notes

            ### Release plan

            The plan for the **next** release.

            ```file
            plans/release.md
            ```
            """)
        }
    }

    @Test func filePathsResolveAgainstTheCheatSheetsFolder() {
        let folderURL = URL(fileURLWithPath: "/Users/example/CheatSheets", isDirectory: true)
        #expect(
            CheatSheetStore.fileURL(forPath: " notes/../plans/a b.md\n", relativeTo: folderURL).path
                == "/Users/example/CheatSheets/plans/a b.md"
        )
        #expect(
            CheatSheetStore.fileURL(forPath: "/tmp/notes.md", relativeTo: folderURL).path
                == "/tmp/notes.md"
        )
        #expect(
            CheatSheetStore.fileURL(forPath: "~/notes.md", relativeTo: folderURL).path
                == NSHomeDirectory() + "/notes.md"
        )
    }

    @Test func shellEscapedPathEscapesSpaces() {
        #expect(
            CheatSheetStore.shellEscapedPath(
                "/Users/example/Library/Application Support/DittoBar/Cheat Sheets"
            )
                == "/Users/example/Library/Application\\ Support/DittoBar/Cheat\\ Sheets"
        )
    }

    private func section(titled title: String, in store: CheatSheetStore) -> CheatSheetSection? {
        store.visibleItems.lazy.compactMap(\.section).first { $0.title == title }
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

    private func withStore(
        source: String = Self.source,
        _ assertions: (CheatSheetStore) throws -> Void
    ) throws {
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
        try source.write(to: sourceURL, atomically: true, encoding: .utf8)

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
