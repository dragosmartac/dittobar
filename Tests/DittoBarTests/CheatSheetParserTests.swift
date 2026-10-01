import Foundation
import Testing
@testable import DittoBar

struct CheatSheetParserTests {
    @Test func parsesCommandEntry() throws {
        let source = """
        # Git
        ## Basics
        ### Show status
        Displays the working tree status.
        ```sh
        git status
        ```
        """

        let sheet = CheatSheetParser.parse(
            source,
            fileURL: URL(fileURLWithPath: "/tmp/git_tools.md")
        )

        #expect(sheet.title == "Git")
        #expect(sheet.entries.count == 1)

        let entry = try #require(sheet.entries.first)
        guard case .command(let command) = entry else {
            Issue.record("Expected a command entry")
            return
        }
        #expect(command.metadata.id == "git_tools.md:0:Show status")
        #expect(command.metadata.storageKey == "git_tools.md#Show status")
        #expect(command.metadata.title == "Show status")
        #expect(command.metadata.sectionTitle == "Basics")
        #expect(command.rawDescription == "Displays the working tree status.")
        #expect(command.rawCommand == "git status")
        #expect(command.language == "sh")
        #expect(entry.actions == EntryActions(
            primary: .copyCommand,
            secondary: [
                .copyTitle,
                .copyDescription(.markdownStripped),
                .copyDescription(.resolved)
            ]
        ))
    }

    @Test func parsesURLAndNoteEntries() {
        let source = """
        # Resources
        ### Documentation
        Opens the selected documentation page.
        ```URL
        https://example.com/{{topic=swift}}
        ```
        ### Reminder
        Read the **release notes** before upgrading.
        """

        let sheet = CheatSheetParser.parse(
            source,
            fileURL: URL(fileURLWithPath: "/tmp/resources.md")
        )

        #expect(sheet.entries.count == 2)

        guard case .url(let url) = sheet.entries[0] else {
            Issue.record("Expected a URL entry")
            return
        }
        #expect(url.rawDescription == "Opens the selected documentation page.")
        #expect(url.rawURL == "https://example.com/{{topic=swift}}")
        #expect(url.variables == [EntryVariable(name: "topic", defaultValue: "swift")])
        #expect(sheet.entries[0].actions == EntryActions(
            primary: .copyURL,
            secondary: [
                .openURL,
                .copyTitle,
                .copyDescription(.markdownStripped),
                .copyDescription(.resolved)
            ]
        ))

        guard case .note(let note) = sheet.entries[1] else {
            Issue.record("Expected a note entry")
            return
        }
        #expect(note.rawContent == "Read the **release notes** before upgrading.")
        #expect(sheet.entries[1].actions == EntryActions(
            primary: .copyNoteContent(.markdownStripped),
            secondary: [.copyTitle, .copyNoteContent(.resolved)]
        ))
    }

    @Test func parsesFileWithoutTitle() {
        let sheet = CheatSheetParser.parse(
            "",
            fileURL: URL(fileURLWithPath: "/tmp/git_commands.md")
        )

        #expect(sheet.title == "Git Commands")
    }

    @Test func parsesSectionsAndAssignsEntries() {
        let source = """
        # Resources

        ## Section 1

        ### Reminder
        Read the release notes before upgrading.

        <!-- Comment Divider
        -->
        ## Section 2

        ### Documentation
        Entry description.
        ```url
        https://example.com/docs
        ```

        ### Support
        ```url
        https://example.com/support
        ```
        """
        let sheet = CheatSheetParser.parse(
            source,
            fileURL: URL(fileURLWithPath: "/tmp/resources.md")
        )

        #expect(sheet.entries.count == 3)
        #expect(sheet.sections.map(\.title) == ["Section 1", "Section 2"])
        #expect(sheet.sections.map(\.entryOffset) == [0, 1])
        #expect(sheet.entries.map(\.title) == ["Reminder", "Documentation", "Support"])
        #expect(sheet.entries.map(\.sectionTitle) == ["Section 1", "Section 2", "Section 2"])

        guard case .note(let note) = sheet.entries[0],
              case .url(let documentation) = sheet.entries[1],
              case .url(let support) = sheet.entries[2] else {
            Issue.record("Expected one note followed by two URL entries")
            return
        }
        #expect(note.rawContent == "Read the release notes before upgrading.")
        #expect(documentation.rawDescription == "Entry description.")
        #expect(documentation.rawURL == "https://example.com/docs")
        #expect(support.rawDescription == nil)
        #expect(support.rawURL == "https://example.com/support")
        #expect(sheet.entries[2].actions == EntryActions(
            primary: .copyURL,
            secondary: [.openURL, .copyTitle]
        ))
    }

    @Test func parsesVariablesInMarkdownOrder() throws {
        let source = """
        # Deployment

        ### Deploy service
        Deploy {{service=payments}} from {{region=eu-west-1}}.

        ```sh
        deploy {{service=checkout}} --region {{region=us-east-1}} --tag {{tag=latest stable}}
        ```
        """

        let sheet = CheatSheetParser.parse(
            source,
            fileURL: URL(fileURLWithPath: "/tmp/deployment.md")
        )

        let entry = try #require(sheet.entries.first)
        guard case .command(let command) = entry else {
            Issue.record("Expected a command entry")
            return
        }
        #expect(command.variables == [
            EntryVariable(name: "service", defaultValue: "payments"),
            EntryVariable(name: "region", defaultValue: "eu-west-1"),
            EntryVariable(name: "tag", defaultValue: "latest stable")
        ])
    }

    @Test func usesNilForMissingCommandLanguageAndDescription() throws {
        let source = """
        ### Run
        ```
        run
        ```
        """

        let sheet = CheatSheetParser.parse(
            source,
            fileURL: URL(fileURLWithPath: "/tmp/run.md")
        )

        let entry = try #require(sheet.entries.first)
        guard case .command(let command) = entry else {
            Issue.record("Expected a command entry")
            return
        }
        #expect(command.rawDescription == nil)
        #expect(command.language == nil)
        #expect(entry.actions == EntryActions(
            primary: .copyCommand,
            secondary: [.copyTitle]
        ))
    }

    @Test func treatsEmptyFenceWithProseAsNoteAndIgnoresEmptyEntry() {
        let source = """
        ### Note
        Keep this.
        ```sh
        ```

        ### Empty
        ```url
        ```
        """

        let sheet = CheatSheetParser.parse(
            source,
            fileURL: URL(fileURLWithPath: "/tmp/empty.md")
        )

        #expect(sheet.entries.count == 1)
        guard case .note(let note) = sheet.entries[0] else {
            Issue.record("Expected the prose entry to become a note")
            return
        }
        #expect(note.rawContent == "Keep this.")
    }
}
