import Foundation
import Testing
@testable import DittoBar

struct StarterContentTests {
    @Test func newSheetCanOmitInstructionsWithoutChangingContent() {
        let source = StarterContent.newSheet(named: "Notes", includeInstructions: false)
        #expect(source.hasPrefix("# Notes\n"))
        #expect(!source.contains("<!--"))
        #expect(StarterContent.newSheet(named: "Notes") == "\(StarterContent.instructions)\n\n\(source)")
    }

    @Test func instructionsPreferenceDefaultsToEnabledAndPersistsBothChoices() throws {
        let suiteName = "StarterContentTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(EditorPreferences.includeInstructions(defaults: defaults))
        defaults.set(false, forKey: EditorPreferences.includeInstructionsKey)
        #expect(!EditorPreferences.includeInstructions(defaults: defaults))
        defaults.set(true, forKey: EditorPreferences.includeInstructionsKey)
        #expect(EditorPreferences.includeInstructions(defaults: defaults))
    }

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
