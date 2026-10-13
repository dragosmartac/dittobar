import Testing
@testable import DittoBar

struct MarkdownTextTests {
    @Test func parsesTableBlocks() {
        let source = """
        Intro **text**.

        | Shape | Example |
        | --- | --- |
        | Bare name | `mysql.server` |
        | Full target | `//mysql/server:server` |
        """

        #expect(MarkdownText.blocks(in: source) == [
            .text("Intro **text**."),
            .table(
                MarkdownText.Table(
                    header: ["Shape", "Example"],
                    rows: [
                        ["Bare name", "`mysql.server`"],
                        ["Full target", "`//mysql/server:server`"]
                    ]
                )
            )
        ])
    }

    @Test func stripsTableMarkdownAsTabSeparatedText() {
        let source = """
        | **Shape** | Example |
        | --- | --- |
        | Bare name | `mysql.server` |
        """

        #expect(MarkdownText.stripped(source) == "Shape\tExample\nBare name\tmysql.server")
    }

    @Test func parsesAndStripsBlockQuotes() {
        let source = """
        Before.

        > Quote with **emphasis** and {{service=api}}.
        > A second line with `code`.

        After.
        """

        #expect(MarkdownText.blocks(in: source) == [
            .text("Before."),
            .quote("Quote with **emphasis** and {{service=api}}.\nA second line with `code`."),
            .text("After.")
        ])
        #expect(
            MarkdownText.stripped(
                TextVariables.resolve(source, values: ["service": "payments"])
            ) == "Before.\nQuote with emphasis and payments.\nA second line with code.\nAfter."
        )
    }

    @Test func allowsPipesInsideCodeAndEscapedPipes() {
        let source = """
        | Kind | Value |
        | --- | --- |
        | Code | `left|right` |
        | Text | left\\|right |
        """

        guard case .table(let table) = MarkdownText.blocks(in: source).first else {
            Issue.record("Expected a table block")
            return
        }
        #expect(table.rows == [
            ["Code", "`left|right`"],
            ["Text", "left\\|right"]
        ])
    }

    @Test func resolvesVariablesInsideTableCells() {
        let source = """
        | Shape | Example |
        | --- | --- |
        | Full target | `{{target=//mysql/server:server}}` |
        """

        guard case .table(let table) = MarkdownText.blocks(in: source).first else {
            Issue.record("Expected a table block")
            return
        }

        let cell = table.rows[0][1]
        let segments = TextVariables.segments(
            of: cell,
            values: ["target": "//mysql/other:server"]
        )

        #expect(segments.map(\.text).joined() == "`//mysql/other:server`")
        #expect(segments.contains { $0.isVariable && $0.text == "//mysql/other:server" })
        #expect(
            MarkdownText.stripped(TextVariables.resolve(source, values: [
                "target": "//mysql/other:server"
            ])) == "Shape\tExample\nFull target\t//mysql/other:server"
        )
    }

    @Test func parsesBulletOrderedAndTaskLists() {
        let source = """
        Steps:
        - First **bold**
        * Second
        + [ ] Open task
        - [x] Done task

        1. One
        1. Two
        7) Three
        """

        #expect(MarkdownText.blocks(in: source) == [
            .text("Steps:"),
            .list([
                .init(text: "First **bold**"),
                .init(text: "Second"),
                .init(task: .open, text: "Open task"),
                .init(task: .done, text: "Done task"),
                .init(marker: .ordered(1), text: "One"),
                .init(marker: .ordered(2), text: "Two"),
                .init(marker: .ordered(3), text: "Three")
            ])
        ])
    }

    @Test func orderedListsStartAtTheFirstNumber() {
        #expect(MarkdownText.blocks(in: "3. a\n9. b") == [
            .list([
                .init(marker: .ordered(3), text: "a"),
                .init(marker: .ordered(4), text: "b")
            ])
        ])
    }

    @Test func nestsListItemsByIndentation() {
        let source = """
        - Parent
          - Child
            1. Grandchild
            2. Grandchild two
          - Child two
        - Parent two
        """

        #expect(MarkdownText.blocks(in: source) == [
            .list([
                .init(text: "Parent"),
                .init(depth: 1, text: "Child"),
                .init(depth: 2, marker: .ordered(1), text: "Grandchild"),
                .init(depth: 2, marker: .ordered(2), text: "Grandchild two"),
                .init(depth: 1, text: "Child two"),
                .init(text: "Parent two")
            ])
        ])
    }

    @Test func indentedLinesContinueTheItemAndOthersEndTheList() {
        let source = """
        - Item
          continued here

          new paragraph
        - Next

        After the list.
        Not an item.
        """

        #expect(MarkdownText.blocks(in: source) == [
            .list([
                .init(text: "Item\ncontinued here\n\nnew paragraph"),
                .init(text: "Next")
            ]),
            .text("After the list.\nNot an item.")
        ])
        #expect(MarkdownText.blocks(in: "- Item\nUnindented") == [
            .list([.init(text: "Item")]),
            .text("Unindented")
        ])
    }

    @Test func leavesNonListLinesAsText() {
        let source = """
        Released in
        2024. Then more.
        -not an item
        ---
        * * *
        -
        """

        #expect(MarkdownText.blocks(in: source) == [.text(source)])
    }

    @Test func stripsListsWithNormalizedMarkers() {
        let source = """
        - **Bold** item
          - [ ] Open {{service=api}}
            wrapped
        3. Ordered `code`
        4. [x] Done
        """

        #expect(
            MarkdownText.stripped(
                TextVariables.resolve(source, values: ["service": "payments"])
            ) == "• Bold item\n\t☐ Open payments\n\t\twrapped\n3. Ordered code\n4. ☑ Done"
        )
    }
}
