import AppKit
import Testing
@testable import DittoBar

struct SyntaxHighlighterTests {
    /// Each token as its kind and the text it covers.
    private func tokens(_ text: String, _ language: String?) -> [(SyntaxHighlighter.TokenKind, String)] {
        SyntaxHighlighter.tokens(in: text, language: language).map { token in
            (token.kind, (text as NSString).substring(with: token.range))
        }
    }

    private func expectTokens(
        _ text: String,
        _ language: String,
        _ expected: [(SyntaxHighlighter.TokenKind, String)]
    ) {
        let actual = tokens(text, language)
        #expect(actual.map(\.0) == expected.map(\.0))
        #expect(actual.map(\.1) == expected.map(\.1))
    }

    @Test func unknownOrMissingLanguageHasNoTokens() {
        #expect(tokens("select 1", nil).isEmpty)
        #expect(tokens("select 1", "cobol").isEmpty)
    }

    @Test func languageNamesIgnoreCaseAndAcceptAliases() {
        #expect(!tokens("SELECT 1", "SQL").isEmpty)
        #expect(!tokens("import os", "py").isEmpty)
        #expect(!tokens("if true", "zsh").isEmpty)
    }

    @Test func highlightsPython() {
        expectTokens(
            "def f(x=3.14): return 'a#b'  # done",
            "python",
            [(.keyword, "def"), (.number, "3.14"), (.keyword, "return"), (.string, "'a#b'"), (.comment, "# done")]
        )
    }

    @Test func pythonTripleQuotedStringsSpanLines() {
        expectTokens(
            "x = \"\"\"one\ntwo\"\"\"\nTrue",
            "python",
            [(.string, "\"\"\"one\ntwo\"\"\""), (.keyword, "True")]
        )
    }

    @Test func pythonKeywordsAreCaseSensitive() {
        #expect(tokens("true IF", "python").isEmpty)
    }

    @Test func highlightsSQLIgnoringKeywordCase() {
        expectTokens(
            "SELECT name FROM users WHERE id = 42 -- one\n/* note */ and n = 'it''s'",
            "sql",
            [
                (.keyword, "SELECT"), (.keyword, "FROM"), (.keyword, "WHERE"), (.number, "42"),
                (.comment, "-- one"), (.comment, "/* note */"), (.keyword, "and"),
                (.string, "'it'"), (.string, "'s'")
            ]
        )
    }

    @Test func highlightsShellVariablesInsideDoubleQuotes() {
        expectTokens(
            "echo \"$HOME/${dir}\" '$x' $1",
            "sh",
            [
                (.string, "\"$HOME/${dir}\""), (.variable, "$HOME"), (.variable, "${dir}"),
                (.string, "'$x'"), (.variable, "$1")
            ]
        )
    }

    @Test func shellCommentsOnlyStartWords() {
        expectTokens(
            "curl https://x.dev/a#b # fetch",
            "bash",
            [(.comment, "# fetch")]
        )
    }

    @Test func shellKeywordsInsideWordsAreIgnored() {
        expectTokens(
            "git checkout fix/for-real && for f in *; do echo; done",
            "sh",
            [(.keyword, "for"), (.keyword, "in"), (.keyword, "do"), (.keyword, "done")]
        )
    }

    @Test func shellNumbersFollowedByWordCharactersAreWords() {
        expectTokens("brew pin 1.2.3-beta 2>&1", "sh", [(.number, "2"), (.number, "1")])
    }

    @Test func escapedQuoteDoesNotStartString() {
        #expect(tokens(#"echo \"hi"#, "sh").isEmpty)
    }

    @Test func unterminatedSingleLineStringStopsAtLineEnd() {
        expectTokens("x = 'open\nimport os", "python", [(.string, "'open"), (.keyword, "import")])
    }

    @Test func rangesCountUTF16Units() {
        let tokens = SyntaxHighlighter.tokens(in: "'🙂' if", language: "python")
        #expect(tokens.map(\.range) == [NSRange(location: 0, length: 4), NSRange(location: 5, length: 2)])
    }
}
