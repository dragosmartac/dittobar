import Foundation
import Testing
@testable import DittoBar

struct CheatSheetSearchTests {
    @Test func emptyQueryReturnsEveryItem() {
        let sheet = makeSheet()

        #expect(filteredItems(in: sheet, matching: "  \n") == sheet.items)
    }

    @Test func matchingEntryIncludesItsSection() {
        let items = filteredItems(in: makeSheet(), matching: "alpha entry")

        #expect(descriptions(of: items) == [
            "section:Tools",
            "entry:Alpha entry"
        ])
    }

    @Test func matchingSectionIncludesItsEntries() {
        let items = filteredItems(in: makeSheet(), matching: "tools")

        #expect(descriptions(of: items) == [
            "section:Tools",
            "entry:Alpha entry",
            "entry:Beta entry"
        ])
    }

    @Test func matchingEmptySectionRemainsIncluded() {
        let items = filteredItems(in: makeSheet(), matching: "empty section")

        #expect(descriptions(of: items) == ["section:Empty section"])
    }

    @Test func noMatchesReturnsAnEmptyArray() {
        #expect(filteredItems(in: makeSheet(), matching: "missing").isEmpty)
    }

    @Test func matchingResolvedTextUsesSuppliedEffectiveValues() {
        let sheet = makeSheet()
        let items = CheatSheetSearch.filteredItems(
            in: sheet,
            matching: "deploy-staging"
        ) { _ in
            ["env": "staging"]
        }

        #expect(descriptions(of: items) == [
            "section:Tools",
            "entry:Alpha entry"
        ])
    }

    private func filteredItems(
        in sheet: CheatSheet,
        matching query: String
    ) -> [CheatSheetItem] {
        CheatSheetSearch.filteredItems(in: sheet, matching: query) { entry in
            entry.defaultValues
        }
    }

    private func descriptions(of items: [CheatSheetItem]) -> [String] {
        items.map { item in
            switch item {
            case .section(let section):
                return "section:\(section.title)"
            case .entry(let entry):
                return "entry:\(entry.title)"
            }
        }
    }

    private func makeSheet() -> CheatSheet {
        CheatSheetParser.parse(
            """
            # Filtering

            ### Before sections
            Unsectioned content.

            ## Empty section

            ## Tools
            ### Alpha entry
            Run deploy-{{env=prod}}.

            ### Beta entry
            Beta content.

            ## Trailing section
            """,
            fileURL: URL(fileURLWithPath: "/tmp/filtering.md")
        )
    }
}
