import Foundation
import Testing
@testable import DittoBar

struct SheetFilesTests {
    @Test func loadingFiltersAndNaturallySortsMarkdownFiles() throws {
        try withFolder { folder in
            for name in ["10.md", "2.MD", ".hidden.md", "notes.txt"] {
                try "# \(name)\n\n### Note\nHello".write(
                    to: folder.appendingPathComponent(name), atomically: true, encoding: .utf8
                )
            }
            #expect(SheetFiles.load(from: folder).map(\.sourceURL.lastPathComponent) == ["2.MD", "10.md"])
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
            for name in [" ", ".md", "nested/name"] {
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

    private func withFolder(_ body: (URL) throws -> Void) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try body(folder)
    }
}
