import Foundation
import Testing
@testable import DittoBar

struct TodoLineTests {
    @Test func parsesCanonicalAndShorthandForms() {
        #expect(TodoLine.parse("- [ ] Cancel gym", allowsShorthand: true)
            == .init(indent: "", marker: "-", isDone: false, rawItemText: "Cancel gym"))
        #expect(TodoLine.parse("  * [x] Done", allowsShorthand: true)
            == .init(indent: "  ", marker: "*", isDone: true, rawItemText: "Done"))
        #expect(TodoLine.parse("2) [X] Second", allowsShorthand: true)
            == .init(indent: "", marker: "2)", isDone: true, rawItemText: "Second"))
        #expect(TodoLine.parse("[] Cancel gym", allowsShorthand: true)
            == .init(indent: "", marker: nil, isDone: false, rawItemText: "Cancel gym"))
        #expect(TodoLine.parse("- [] Cancel gym", allowsShorthand: true)
            == .init(indent: "", marker: "-", isDone: false, rawItemText: "Cancel gym"))
    }

    @Test func shorthandIsOnlyAcceptedWhenAllowed() {
        #expect(TodoLine.parse("[ ] Cancel gym", allowsShorthand: false) == nil)
        #expect(TodoLine.parse("- [] Cancel gym", allowsShorthand: false) == nil)
        #expect(TodoLine.parse("- [ ] Cancel gym", allowsShorthand: false) != nil)
    }

    @Test func rejectsLinesThatAreNotTodos() {
        for line in ["- [ ]", "- [ ]   ", "- plain item", "[link](x) text", "-[ ] no space", "[x]no space"] {
            #expect(TodoLine.parse(line, allowsShorthand: true) == nil, "\(line)")
        }
    }

    @Test func checkingOffWritesCanonicalFormWithDoneDate() {
        #expect(TodoLine.settingDone(true, in: "[] Cancel gym #home", today: "2026-10-15")
            == "- [x] Cancel gym #home done:2026-10-15")
        #expect(TodoLine.settingDone(true, in: "  1. [ ] Step", today: "2026-10-15")
            == "  1. [x] Step done:2026-10-15")
    }

    @Test func uncheckingRemovesDoneDate() {
        #expect(TodoLine.settingDone(false, in: "- [x] Draft plan !2 done:2026-10-14 #work", today: "2026-10-15")
            == "- [ ] Draft plan !2 #work")
    }
}

struct TodoTokensTests {
    @Test func extractsTokensAndKeepsText() {
        let parsed = TodoTokens.parse("Write migration !1 for **refunds** #payments due:2026-10-17 #db/core")
        #expect(parsed.rawText == "Write migration for **refunds**")
        #expect(parsed.priority == 1)
        #expect(parsed.tags == ["payments", "db/core"])
        #expect(parsed.dueDate == "2026-10-17")
        #expect(parsed.doneDate == nil)
    }

    @Test func leavesLookalikesAlone() {
        let parsed = TodoTokens.parse("Fix issue #12 in C# !4 due:2026-13-01 see https://x.com/#frag")
        #expect(parsed.rawText == "Fix issue #12 in C# !4 due:2026-13-01 see https://x.com/#frag")
        #expect(parsed.priority == nil)
        #expect(parsed.tags.isEmpty)
        #expect(parsed.dueDate == nil)
    }

    @Test func ignoresTokensInsideInlineCode() {
        let parsed = TodoTokens.parse("Add `#include <x> !1` to header #cpp")
        #expect(parsed.rawText == "Add `#include <x> !1` to header")
        #expect(parsed.tags == ["cpp"])
        #expect(parsed.priority == nil)
    }
}

struct TodoParserTests {
    @Test func looseTodosBecomeEntriesWithContext() throws {
        let source = """
        # Personal

        [] Cancel gym subscription #home
        - [ ] Renew passport !1 due:2026-11-01

        ## Money
        - [x] Move savings done:2026-10-15
        """
        let sheet = CheatSheetParser.parse(source, fileURL: URL(fileURLWithPath: "/tmp/personal.md"))

        #expect(sheet.title == "Personal")
        let todos = sheet.items.compactMap(\.todo)
        #expect(todos.map(\.rawText) == ["Cancel gym subscription", "Renew passport", "Move savings"])
        #expect(todos.map(\.isDone) == [false, false, true])
        #expect(todos.map(\.context) == [["Personal"], ["Personal"], ["Personal", "Money"]])
        #expect(todos.map(\.source.lineIndex) == [2, 3, 6])
        #expect(todos[0].source.line == "[] Cancel gym subscription #home")
        #expect(todos[0].tags == ["home"])
        #expect(todos[1].priority == 1)
        #expect(todos[2].doneDate == "2026-10-15")
        #expect(sheet.todos == todos)
        #expect(sheet.items.map(\.section?.title) == [nil, nil, "Money", nil])
    }

    @Test func todosInsideEntriesStayPartOfTheirText() throws {
        let source = """
        ### Release checklist
        - [ ] Tag the release
        - [ ] Announce it #team
        [] Not a todo inside an entry

        ```sh
        make release
        ```
        - [ ] Loose again after the fence
        """
        let sheet = CheatSheetParser.parse(source, fileURL: URL(fileURLWithPath: "/tmp/release.md"))

        let entries = sheet.items.compactMap(\.entry)
        #expect(entries.count == 2)
        guard case .command(let command) = entries[0] else {
            Issue.record("Expected a command entry")
            return
        }
        #expect(command.rawDescription?.contains("- [ ] Tag the release") == true)
        #expect(entries[1].title == "Loose again after the fence")

        #expect(sheet.todos.map(\.rawText) == [
            "Tag the release", "Announce it", "Loose again after the fence"
        ])
        #expect(sheet.todos.map(\.containingEntryID) == [
            command.metadata.id, command.metadata.id, nil
        ])
    }

    @Test func lineIndexesMatchCRLFFiles() {
        let source = "# T\r\n\r\n- [ ] One\r\n- [ ] Two\r\n"
        let sheet = CheatSheetParser.parse(source, fileURL: URL(fileURLWithPath: "/tmp/crlf.md"))
        #expect(sheet.todos.map(\.source.lineIndex) == [2, 3])
        #expect(sheet.todos.map(\.source.line) == ["- [ ] One", "- [ ] Two"])
    }
}

@MainActor
struct TodoStoreTests {
    private static let today = "2026-10-15"

    @Test func todosTabGroupsBySchedule() throws {
        let source = """
        # Work
        - [ ] Someday
        - [ ] Urgent !1
        - [ ] Late due:2026-10-01
        - [ ] Due today due:2026-10-15 !2
        - [ ] Next week due:2026-10-22
        - [x] Finished today done:2026-10-15
        - [x] Finished earlier done:2026-10-01

        ### Runbook
        - [ ] Untagged step
        - [ ] Tagged step #ops
        """
        try withStore(files: ["work.md": source]) { store in
            #expect(store.sheets.map(\.title) == ["Todos", "Work"])
            #expect(store.hasTodosTab)
            #expect(store.shortcutNumber(forSheetAt: 0) == 0)
            #expect(store.shortcutNumber(forSheetAt: 1) == 1)

            store.selectSheet(at: 0)
            #expect(descriptions(store.visibleItems) == [
                "section:Overdue", "Late",
                "section:Today", "Due today",
                "section:Open", "Urgent", "Next week", "Someday", "Tagged step",
                "section:Done Today", "Finished today"
            ])

            store.query = "#ops"
            #expect(descriptions(store.visibleItems) == ["section:Open", "Tagged step"])
        }
    }

    @Test func noTodosMeansNoTodosTab() throws {
        try withStore(files: ["git.md": "# Git\n### Status\n```sh\ngit status\n```\n"]) { store in
            #expect(!store.hasTodosTab)
            #expect(store.shortcutNumber(forSheetAt: 0) == 1)
        }
    }

    @Test func checkingOffRewritesOnlyThatLine() throws {
        let source = "# Personal\r\n\r\n[] Cancel gym #home\r\n- [ ] Keep me\r\n"
        try withStore(files: ["personal.md": source]) { store in
            let url = store.folderURL.appendingPathComponent("personal.md")
            let todo = try #require(store.sheets.last?.todos.first)

            store.setDone(true, for: todo)
            #expect(try String(contentsOf: url, encoding: .utf8)
                == "# Personal\r\n\r\n- [x] Cancel gym #home done:2026-10-15\r\n- [ ] Keep me\r\n")
            #expect(store.editorErrorMessage == nil)

            let checked = try #require(store.sheets.last?.todos.first)
            #expect(checked.isDone)
            store.setDone(false, for: checked)
            #expect(try String(contentsOf: url, encoding: .utf8)
                == "# Personal\r\n\r\n- [ ] Cancel gym #home\r\n- [ ] Keep me\r\n")
        }
    }

    @Test func refusesToRewriteALineThatChanged() throws {
        try withStore(files: ["personal.md": "- [ ] Original\n"]) { store in
            let url = store.folderURL.appendingPathComponent("personal.md")
            let todo = try #require(store.sheets.last?.todos.first)
            try "- [ ] Edited elsewhere\n".write(to: url, atomically: true, encoding: .utf8)

            store.setDone(true, for: todo)
            #expect(try String(contentsOf: url, encoding: .utf8) == "- [ ] Edited elsewhere\n")
            #expect(store.editorErrorMessage != nil)
        }
    }

    @Test func showInSheetSelectsTheTodoOrItsEntry() throws {
        let source = """
        # Work
        - [ ] Loose
        ### Runbook
        - [ ] Tagged step #ops
        """
        try withStore(files: ["work.md": source]) { store in
            store.selectSheet(at: 0)
            let tagged = try #require(store.visibleItems.compactMap(\.entry).last)
            #expect(store.actions(for: tagged).secondary.contains(.showTodoInSheet))

            store.perform(.showTodoInSheet, for: tagged)
            #expect(store.selectedSheet?.title == "Work")
            #expect(store.selectedEntry?.title == "Runbook")
            #expect(!store.actions(for: tagged).secondary.contains(.showTodoInSheet))
        }
    }

    private func descriptions(_ items: [CheatSheetItem]) -> [String] {
        items.map { item in
            if let section = item.section {
                return "section:\(section.title)"
            }
            return item.entry?.title ?? ""
        }
    }

    private func withStore(
        files: [String: String],
        _ assertions: (CheatSheetStore) throws -> Void
    ) throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("DittoBarTodoTests-\(UUID().uuidString)", isDirectory: true)
        let cheatSheetsURL = rootURL
            .appendingPathComponent("DittoBar", isDirectory: true)
            .appendingPathComponent("CheatSheets", isDirectory: true)
        try FileManager.default.createDirectory(at: cheatSheetsURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        for (name, source) in files {
            try source.write(
                to: cheatSheetsURL.appendingPathComponent(name),
                atomically: true,
                encoding: .utf8
            )
        }

        let fileManager = TodoTestFileManager(applicationSupportURL: rootURL)
        let now = try #require(DateComponents(
            calendar: Calendar(identifier: .gregorian),
            year: 2026, month: 10, day: 15, hour: 12
        ).date)
        let store = CheatSheetStore(fileManager: fileManager, now: { now })
        #expect(store.today == Self.today)
        try assertions(store)
    }
}

private final class TodoTestFileManager: FileManager, @unchecked Sendable {
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
