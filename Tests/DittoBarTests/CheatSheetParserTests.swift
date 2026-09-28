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
        #expect(command.detail == "Displays the working tree status.")
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
        #expect(note.detail == "Read the release notes before upgrading.")
        #expect(note.copyTemplate == note.detail)
    }

    @Test func parsesFileWithoutTitle() {
        let source = ""

        let sheet = CheatSheetParser.parse(
            source,
            fileURL: URL(fileURLWithPath: "/tmp/git_commands.md")
        )

        #expect(sheet.title == "Git Commands")
    }
}
