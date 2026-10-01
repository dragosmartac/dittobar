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
        #expect(sheet.commands.count == 1)

        let command = try #require(sheet.commands.first)
        #expect(command.id == "git_tools.md:0:Show status")
        #expect(command.storageKey == "git_tools.md#Show status")
        #expect(command.title == "Show status")
        #expect(command.sectionTitle == "Basics")
        #expect(command.description == "Displays the working tree status.")
        #expect(command.command == "git status")
        #expect(command.language == "sh")
        #expect(!command.isDescriptionOnly)
        #expect(!command.isLink)
    }

    @Test func parsesLinkAndDescriptionOnlyEntries() {
        let source = """
        # Resources
        ### Documentation
        Opens the selected documentation page.
        ```url
        https://example.com/{{topic=swift}}
        ```
        ### Reminder
        Read the release notes before upgrading.
        """

        let sheet = CheatSheetParser.parse(
            source,
            fileURL: URL(fileURLWithPath: "/tmp/resources.md")
        )

        #expect(sheet.commands.count == 2)

        let link = sheet.commands[0]
        #expect(link.isLink)
        #expect(link.command == "https://example.com/{{topic=swift}}")
        #expect(link.variables == [CommandVariable(name: "topic", defaultValue: "swift")])

        let note = sheet.commands[1]
        #expect(note.isDescriptionOnly)
        #expect(note.description == "Read the release notes before upgrading.")
        #expect(note.copyTemplate == note.description)
    }

    @Test func parsesFileWithoutTitle() {
        let source = ""

        let sheet = CheatSheetParser.parse(
            source,
            fileURL: URL(fileURLWithPath: "/tmp/git_commands.md")
        )

        #expect(sheet.title == "Git Commands")
    }

    @Test func parsesSectionsAndAssignsEntries() throws {
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

        try #require(sheet.commands.count == 3)
        #expect(sheet.sections.map(\.title) == ["Section 1", "Section 2"])
        #expect(sheet.sections.map(\.commandOffset) == [0, 1])
        #expect(sheet.commands.map(\.title) == ["Reminder", "Documentation", "Support"])
        #expect(sheet.commands.map(\.sectionTitle) == ["Section 1", "Section 2", "Section 2"])
        #expect(sheet.commands.map(\.isDescriptionOnly) == [true, false, false])
        #expect(sheet.commands.map(\.isLink) == [false, true, true])
        #expect(sheet.commands[0].description == "Read the release notes before upgrading.")
        #expect(sheet.commands[1].description == "Entry description.")
        #expect(sheet.commands.map(\.command) == [
            "",
            "https://example.com/docs",
            "https://example.com/support"
        ])
    }

    @Test func parsesVariablesInMarkdownOrder() {
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

        #expect(sheet.commands[0].title == "Deploy service")
        #expect(sheet.commands[0].hasVariables)
        #expect(sheet.commands[0].variables.count == 3)
        #expect(sheet.commands[0].variables[0].name == "service")
        #expect(sheet.commands[0].variables[0].defaultValue == "payments")
        #expect(sheet.commands[0].variables[1].name == "region")
        #expect(sheet.commands[0].variables[1].defaultValue == "eu-west-1")
        #expect(sheet.commands[0].variables[2].name == "tag")
        #expect(sheet.commands[0].variables[2].defaultValue == "latest stable")
    }
}
