import AppKit
import Testing
@testable import DittoBar

@MainActor
struct EntryActionExecutorTests {
    @Test func urlOpeningReportsValidationAndLaunchFailures() {
        var opened: [URL] = []
        let executor = EntryActionExecutor(open: { opened.append($0); return false })
        let folder = URL(fileURLWithPath: "/tmp")
        #expect(executor.execute(.openURL, output: " not a URL ", folderURL: folder)
            == .failed("\"not a URL\" is not a valid URL."))
        #expect(opened.isEmpty)
        #expect(executor.execute(.openURL, output: " https://example.com/path\n", folderURL: folder)
            == .failed("The URL could not be opened."))
        #expect(opened.map(\.absoluteString) == ["https://example.com/path"])
        let successful = EntryActionExecutor(open: { _ in true })
        #expect(successful.execute(.openURL, output: "https://example.com", folderURL: folder) == .opened)
    }

    @Test func fileActionsValidatePathsAndUseTheExpectedDestination() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("a b.txt")
        try "hello".write(to: file, atomically: true, encoding: .utf8)
        var opened: [URL] = []
        var revealed: [URL] = []
        let executor = EntryActionExecutor(
            open: { opened.append($0); return true },
            reveal: { revealed = $0 }
        )
        #expect(executor.execute(.openFile, output: "missing.txt", folderURL: folder)
            == .failed("\"\(folder.appendingPathComponent("missing.txt").path)\" does not exist."))
        #expect(executor.execute(.openFile, output: ".", folderURL: folder)
            == .failed("\"\(folder.path)\" is a folder. File entries can only open files."))
        #expect(opened.isEmpty)
        #expect(executor.execute(.openFile, output: "a b.txt", folderURL: folder) == .opened)
        #expect(opened == [file])
        #expect(executor.execute(.revealInFinder, output: "a b.txt", folderURL: folder) == .opened)
        #expect(revealed == [file])
        let failing = EntryActionExecutor(open: { _ in false })
        #expect(failing.execute(.openFile, output: "a b.txt", folderURL: folder)
            == .failed("No application could open \"\(file.path)\"."))
    }

    @Test func copyActionsWriteToTheSuppliedPasteboard() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let executor = EntryActionExecutor(pasteboard: pasteboard)
        let folder = URL(fileURLWithPath: "/tmp/cheat sheets")
        #expect(executor.execute(.copyCommand, output: "echo hello", folderURL: folder) == .copied)
        #expect(pasteboard.string(forType: .string) == "echo hello")
        #expect(executor.execute(.copyPath, output: "a b.md", folderURL: folder) == .copied)
        #expect(pasteboard.string(forType: .string) == "/tmp/cheat\\ sheets/a\\ b.md")
    }

    @Test func joinedEntryTextsUseBlankLinesOnlyForMultilineTexts() {
        #expect(EntryActionExecutor.joinedEntryTexts(["git status", "git log\n"]) == "git status\ngit log")
        #expect(EntryActionExecutor.joinedEntryTexts(["one\ntwo", "three"]) == "one\ntwo\n\nthree")
    }

    @Test func filePathsResolveAgainstTheCheatSheetsFolder() {
        let folderURL = URL(fileURLWithPath: "/Users/example/CheatSheets", isDirectory: true)
        #expect(
            EntryActionExecutor.fileURL(forPath: " notes/../plans/a b.md\n", relativeTo: folderURL).path
                == "/Users/example/CheatSheets/plans/a b.md"
        )
        #expect(
            EntryActionExecutor.fileURL(forPath: "/tmp/notes.md", relativeTo: folderURL).path
                == "/tmp/notes.md"
        )
        #expect(
            EntryActionExecutor.fileURL(forPath: "~/notes.md", relativeTo: folderURL).path
                == NSHomeDirectory() + "/notes.md"
        )
    }

    @Test func shellEscapedPathEscapesSpaces() {
        #expect(
            EntryActionExecutor.shellEscapedPath(
                "/Users/example/Library/Application Support/DittoBar/Cheat Sheets"
            )
                == "/Users/example/Library/Application\\ Support/DittoBar/Cheat\\ Sheets"
        )
    }
}
