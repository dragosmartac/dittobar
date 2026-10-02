import Foundation
import Testing
@testable import DittoBar

struct StarterContentTests {
    @Test func starterSheetsParseIntoEntries() {
        let sheets = [
            ("vim.md", StarterContent.vimSheet, "Vim"),
            ("git.md", StarterContent.gitSheet, "Git"),
            ("notes.md", StarterContent.newSheet(named: "Notes"), "Notes")
        ]

        for (fileName, source, title) in sheets {
            let sheet = CheatSheetParser.parse(
                source,
                fileURL: URL(fileURLWithPath: "/tmp/\(fileName)")
            )

            // The instructions comment contains headings and fences; a matching
            // title shows the parser skipped it rather than reading it as content.
            #expect(sheet.title == title)
            #expect(sheet.items.contains { $0.entry != nil })
            #expect(source.hasPrefix(StarterContent.instructions))
        }
    }
}
