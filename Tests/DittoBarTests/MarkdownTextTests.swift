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
}
