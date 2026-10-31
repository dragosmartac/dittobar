import Foundation
import Testing
@testable import DittoBar

struct SectionMarkdownExporterTests {
    @Test func exportResolvesValuesAndPreservesEntryFormats() throws {
        let sheet = CheatSheetParser.parse("""
        # Example
        ## Deploy
        ### Note
        Use **{{env=prod}}**.
        ### Command
        Run this:
        ```sh
        echo {{env=prod}}
        ```
        ### Link
        ```url
        https://example.com/{{env=prod}}
        ```
        ### File
        ```file
        plans/{{env=prod}}.md
        ```
        """, fileURL: URL(fileURLWithPath: "/tmp/example.md"))
        let section = try #require(sheet.items.compactMap(\.section).first)
        let output = SectionMarkdownExporter.markdown(
            for: section,
            entries: sheet.items.compactMap(\.entry),
            values: { _ in ["env": "staging"] }
        )
        #expect(output == """
        ## Deploy

        ### Note

        Use **staging**.

        ### Command

        Run this:

        ```sh
        echo staging
        ```

        ### Link

        https://example.com/staging

        ### File

        ```file
        plans/staging.md
        ```
        """)
    }

    @Test func exportUsesFencesLongerThanEmbeddedBackticks() {
        let entry = CheatSheetEntry.command(CommandEntry(
            metadata: EntryMetadata(id: "cmd", storageKey: "cmd", title: "Command"),
            rawDescription: nil,
            rawCommand: "echo hello\n```",
            language: "sh",
            variables: []
        ))
        #expect(SectionMarkdownExporter.markdown(
            for: CheatSheetSection(id: "s", title: "Section"),
            entries: [entry],
            values: { _ in [:] }
        ) == "## Section\n\n### Command\n\n````sh\necho hello\n```\n````")
    }

    @Test func emptySectionExportsItsHeading() {
        #expect(SectionMarkdownExporter.markdown(
            for: CheatSheetSection(id: "empty", title: "Empty"),
            entries: [],
            values: { _ in [:] }
        ) == "## Empty")
    }
}
