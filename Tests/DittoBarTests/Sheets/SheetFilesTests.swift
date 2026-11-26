import Foundation
import Testing
@testable import DittoBar

struct SheetFilesTests {
    @Test func loadingFiltersAndNaturallySortsMarkdownFiles() throws {
        try withFolder { folder in
            for name in ["10.md", "2.MD", ".hidden.md", "notes.txt", "INSTRUCTIONS.MD"] {
                try "# \(name)\n\n### Note\nHello".write(
                    to: folder.appendingPathComponent(name), atomically: true, encoding: .utf8
                )
            }
            #expect(SheetFiles.load(from: folder).map(\.sourceURL.lastPathComponent) == ["2.MD", "10.md"])
        }
    }

    @Test func instructionsCreationPreservesExistingContentAndStaysOutOfSheets() throws {
        try withFolder { folder in
            let url = try SheetFiles.createInstructionsIfNeeded(in: folder)
            #expect(url.lastPathComponent == "instructions.md")
            #expect(try String(contentsOf: url, encoding: .utf8).contains("# DittoBar sheet instructions"))
            #expect(SheetFiles.load(from: folder).isEmpty)

            let customInstructions = "# My instructions\n\n### Keep this\nUser content"
            try customInstructions.write(to: url, atomically: true, encoding: .utf8)
            try SheetFiles.createInstructionsIfNeeded(in: folder)
            #expect(try String(contentsOf: url, encoding: .utf8) == customInstructions)
            #expect(SheetFiles.load(from: folder).isEmpty)
        }
    }

    @Test func instructionsCreationReportsMissingFolder() throws {
        try withFolder { folder in
            #expect(throws: (any Error).self) {
                try SheetFiles.createInstructionsIfNeeded(in: folder.appendingPathComponent("Missing"))
            }
        }
    }

    @Test func creationNormalizesNameAndNeverOverwritesExistingSheet() throws {
        try withFolder { folder in
            let url = try SheetFiles.create(named: " Notes.MD \n", in: folder, includeInstructions: false)
            #expect(url.lastPathComponent == "Notes.md")
            let original = try String(contentsOf: url, encoding: .utf8)
            #expect(original == StarterContent.newSheet(named: "Notes", includeInstructions: false))
            #expect(throws: SheetFiles.CreationError.self) {
                try SheetFiles.create(named: "Notes", in: folder, includeInstructions: true)
            }
            #expect(try String(contentsOf: url, encoding: .utf8) == original)
        }
    }

    @Test func invalidNamesDoNotCreateFiles() throws {
        try withFolder { folder in
            for name in [" ", ".md", "nested/name", "Instructions.MD"] {
                #expect(throws: SheetFiles.CreationError.self) {
                    try SheetFiles.create(named: name, in: folder, includeInstructions: false)
                }
            }
            let contents = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            #expect(contents.isEmpty)
        }
    }

    @Test func starterFilesDoNotPopulateAnExistingMarkdownFolder() throws {
        try withFolder { folder in
            let url = folder.appendingPathComponent("existing.MD")
            try "# Existing".write(to: url, atomically: true, encoding: .utf8)
            SheetFiles.createInitialFilesIfNeeded(in: folder)
            #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["existing.MD"])
        }
    }

    private let draft = NewEntryDraft(kind: .note, title: "Reminder", rawContent: "Check {{branch=main}}.")

    @Test func insertsIntoSelectedOccurrenceAndPreservesExternalEdits() throws {
        try withFolder { folder in
            let url = folder.appendingPathComponent("work.md")
            let prefix = "# Work\n## Git\n### One\nFirst note.\n## Git\n"
            let suffix = "## Git\n### Last\nKeep trailing spaces.  "
            try (prefix + suffix).write(to: url, atomically: true, encoding: .utf8)
            let sheet = try #require(SheetFiles.load(from: folder).first)
            let destination = try #require(sheet.items.compactMap(\.section).dropFirst().first)

            // These edits happen after the destination picker was populated.
            let externalEdit = "### Command\n```sh\n## Git\n```\n<!--\n## Git\n-->\n"
            try (prefix + externalEdit + suffix).write(to: url, atomically: true, encoding: .utf8)
            try SheetFiles.insert(draft, into: url, section: .existing(destination))

            let block = try draft.markdown()
            #expect(try String(contentsOf: url, encoding: .utf8) == prefix + externalEdit + "\n" + block + "\n\n" + suffix)
            let entries = try #require(SheetFiles.load(from: folder).first).items.compactMap(\.entry)
            #expect(entries.map(\.title) == ["One", "Command", "Reminder", "Last"])
        }
    }

    @Test func insertsUnsectionedBeforeFirstSectionPreservingBOMAndCRLF() throws {
        try withFolder { folder in
            let url = folder.appendingPathComponent("notes.md")
            let prefix = "\u{FEFF}# Café\r\n### 👋\r\nFirst.\r\n\r\n"
            let suffix = "## Other\r\n"
            try Data((prefix + suffix).utf8).write(to: url)
            try SheetFiles.insert(draft, into: url, section: .unsectioned)
            let block = try draft.markdown().replacingOccurrences(of: "\n", with: "\r\n")
            #expect(try Data(contentsOf: url) == Data((prefix + block + "\r\n\r\n" + suffix).utf8))
        }
    }

    @Test func appendsAtEndOfEmptyUnsectionedAndFinalSections() throws {
        try withFolder { folder in
            let url = folder.appendingPathComponent("notes.md")
            let block = try draft.markdown()
            for (source, expected) in [
                ("", block + "\n"),
                ("### Previous\nText", "### Previous\nText\n\n" + block),
                ("## Last\n", "## Last\n\n" + block + "\n")
            ] {
                try source.write(to: url, atomically: true, encoding: .utf8)
                let section = CheatSheetParser.parse(source, fileURL: url).items.compactMap(\.section).last
                try SheetFiles.insert(draft, into: url, section: EntrySectionChoice(section))
                #expect(try String(contentsOf: url, encoding: .utf8) == expected)
            }
        }
    }

    @Test func insertsThroughASymlinkKeepingTheLinkAndSectionIdentity() throws {
        try withFolder { folder in
            let target = folder.appendingPathComponent("source.txt")
            let link = folder.appendingPathComponent("notes.md")
            try "## Notes".write(to: target, atomically: true, encoding: .utf8)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
            let sheet = try #require(SheetFiles.load(from: folder).first)
            let section = try #require(sheet.items.first?.section)
            try SheetFiles.insert(draft, into: link, section: EntrySectionChoice(section))
            #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == target.path)
            let expected = try "## Notes\n\n" + draft.markdown()
            #expect(try String(contentsOf: target, encoding: .utf8) == expected)
        }
    }

    @Test func unavailableDestinationsLeaveFilesIntact() throws {
        try withFolder { folder in
            let url = folder.appendingPathComponent("work.md")
            let old = CheatSheetParser.parse("## Git", fileURL: url)
            let section = try #require(old.items.first?.section)
            let current = "## SQL\n"
            try current.write(to: url, atomically: true, encoding: .utf8)
            #expect(throws: SheetFiles.InsertionError.missingSection) {
                try SheetFiles.insert(draft, into: url, section: EntrySectionChoice(section))
            }
            #expect(try String(contentsOf: url, encoding: .utf8) == current)

            let missing = folder.appendingPathComponent("missing.md")
            #expect(throws: (any Error).self) { try SheetFiles.insert(draft, into: missing, section: .unsectioned) }
            #expect(!FileManager.default.fileExists(atPath: missing.path))
        }
    }

    @Test func refusesInsertionInsideUnclosedMarkdownBlocks() throws {
        try withFolder { folder in
            let url = folder.appendingPathComponent("work.md")
            for source in ["### Command\n```sh\npwd\n", "<!--\n## Ignored\n"] {
                try source.write(to: url, atomically: true, encoding: .utf8)
                #expect(throws: SheetFiles.InsertionError.unclosedBlock) {
                    try SheetFiles.insert(draft, into: url, section: .unsectioned)
                }
                #expect(try String(contentsOf: url, encoding: .utf8) == source)
            }
        }
    }

    private func withFolder(_ body: (URL) throws -> Void) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try body(folder)
    }
}
