import Foundation
import Testing
@testable import DittoBar

struct EntryDraftTests {
    private func parse(_ draft: EntryDraft) throws -> CheatSheetEntry {
        let sheet = CheatSheetParser.parse(
            try draft.markdown(),
            fileURL: URL(fileURLWithPath: "/tmp/draft.md")
        )
        #expect(sheet.items.count == 1)
        let entry = try #require(sheet.items.first?.entry)
        #expect(entry.title == draft.title)
        return entry
    }

    @Test func variablesFollowTheFieldsShownForTheCurrentType() {
        var draft = EntryDraft(kind: .command, title: "Example", rawContent: "{{branch")
        #expect(draft.variables.isEmpty)
        draft.rawContent = "{{branch=main}} {{path}}"
        draft.rawDescription = "Check {{branch}} on {{host=local}}."
        #expect(draft.variables == [
            EntryVariable(name: "branch", defaultValue: "main"),
            EntryVariable(name: "host", defaultValue: "local"),
            EntryVariable(name: "path", defaultValue: "")
        ])
        draft.kind = .note
        #expect(draft.variables.map(\.name) == ["branch", "path"])
        draft.rawContent = "Plain text"
        #expect(draft.variables.isEmpty)
    }

    @Test func noteKeepsRawMarkdown() throws {
        let draft = EntryDraft(kind: .note, title: "Review", rawContent: "Review **changes**.\n\n- Check tests")
        guard case .note(let note) = try parse(draft) else {
            Issue.record("Expected a note")
            return
        }
        #expect(note.rawContent == draft.rawContent)
    }

    @Test func commandKeepsMultipleLinesAndVariables() throws {
        let draft = EntryDraft(
            kind: .command, title: "Diff",
            rawContent: "git fetch\r\n# Compare branches\r\ngit diff {{branch=main}}",
            rawDescription: "Compare against **{{branch=main}}**."
        )
        guard case .command(let command) = try parse(draft) else {
            Issue.record("Expected a command")
            return
        }
        #expect(command.rawCommand == "git fetch\n# Compare branches\ngit diff {{branch=main}}")
        #expect(command.rawDescription == draft.rawDescription)
        #expect(command.language == "sh")
        #expect(command.variables == [EntryVariable(name: "branch", defaultValue: "main")])
    }

    @Test func unlabeledFenceIsACommand() throws {
        let draft = EntryDraft(kind: .command, title: "Status", rawContent: "git status", language: "")
        guard case .command(let command) = try parse(draft) else {
            Issue.record("Expected a command")
            return
        }
        #expect(command.language == nil)
        #expect(command.rawDescription == nil)
    }

    @Test func editingACommandPreservesIndentationAndBlankLines() throws {
        let draft = EntryDraft(kind: .command, title: "Indented snippet", rawContent: "\n    run()\n    finish()  \n")
        let entry = try parse(draft)
        #expect(EntryDraft(entry: entry) == draft)
    }

    @Test func urlKeepsRawAddress() throws {
        let draft = EntryDraft(kind: .url, title: "Docs", rawContent: "https://{{host}}/docs")
        guard case .url(let entry) = try parse(draft) else {
            Issue.record("Expected a URL")
            return
        }
        #expect(entry.rawURL == draft.rawContent)
        #expect(entry.rawDescription == nil)
    }

    @Test func fileKeepsRelativePathAndDescription() throws {
        let draft = EntryDraft(
            kind: .file, title: "Notes", rawContent: "{{project}}/notes.md", rawDescription: "Project notes"
        )
        guard case .file(let entry) = try parse(draft) else {
            Issue.record("Expected a file")
            return
        }
        #expect(entry.rawPath == draft.rawContent)
        #expect(entry.rawDescription == draft.rawDescription)
    }

    @Test func directoryRoundTripsWithItsPathDescriptionAndVariables() throws {
        let draft = EntryDraft(kind: .directory, title: "Documents", rawContent: "~/{{project=Work}}",
                               rawDescription: "Documents for **{{project}}**")
        let entry = try parse(draft)
        #expect(entry.kind == .directory)
        #expect(EntryDraft(entry: entry) == draft)
        #expect(entry.variables == [EntryVariable(name: "project", defaultValue: "Work")])
        #expect(entry.actions == EntryActions(primary: .openDirectory, secondary: [
            .copyPath, .copyTitle, .copyDescription(.markdownStripped), .copyDescription(.resolved)
        ]))
    }

    @Test func rejectsDraftsTheSheetCannotRepresent() {
        let cases: [(EntryDraft, EntryDraft.ValidationError)] = [
            (.init(kind: .note, title: " ", rawContent: "Text"), .missingTitle),
            (.init(kind: .url, title: "Docs", rawContent: "\n ", rawDescription: "Site"), .missingContent),
            (.init(kind: .file, title: "First\nSecond", rawContent: "/tmp"), .multilineTitle),
            (.init(kind: .note, title: "Note", rawContent: "Before\n### Another entry"), .structuralLineInProse),
            (.init(kind: .url, title: "Site", rawContent: "url", rawDescription: "<!-- hidden"), .structuralLineInProse),
            (.init(kind: .command, title: "Run", rawContent: "a\n```\nb"), .fenceInContent)
        ]
        for (draft, error) in cases {
            #expect(throws: error) { try draft.markdown() }
        }
        for language in ["URL", "File", "Directory", "sh\nbody"] {
            let draft = EntryDraft(kind: .command, title: "Run", rawContent: "ls", language: language)
            #expect(throws: EntryDraft.ValidationError.invalidLanguage) { try draft.markdown() }
        }
    }
}
