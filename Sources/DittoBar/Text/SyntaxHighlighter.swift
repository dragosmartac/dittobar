import Foundation

/// Finds the parts of a command to color, using the language named on its
/// code fence. Each grammar is a small scanner rather than a full parser: it
/// recognises comments, strings, numbers, keywords, and shell variables,
/// which is enough for the short commands a cheat sheet holds.
enum SyntaxHighlighter {
    enum TokenKind: Equatable {
        case keyword
        case string
        case comment
        case number
        case variable
    }

    /// `range` counts UTF-16 units, so it applies directly to an
    /// `NSAttributedString` of the same text.
    struct Token: Equatable {
        let kind: TokenKind
        let range: NSRange
    }

    /// Tokens are in source order, except that variables interpolated into a
    /// string follow the string token that contains them.
    static func tokens(in text: String, language: String?) -> [Token] {
        guard let language, let grammar = grammar(named: language) else { return [] }
        var scanner = Scanner(units: Array(text.utf16), grammar: grammar)
        return scanner.scan()
    }

    static func grammar(named language: String) -> Grammar? {
        switch language.lowercased() {
        case "python", "py", "python3":
            return .python
        case "sql", "mysql", "postgres", "postgresql", "psql", "sqlite":
            return .sql
        case "sh", "bash", "zsh", "shell":
            return .shell
        case "javascript", "js", "jsx", "typescript", "ts", "tsx", "node":
            return .javaScript
        case "json":
            return .json
        default:
            return nil
        }
    }

    struct StringDelimiter {
        let open: String
        let close: String
        /// A backslash escapes the next character.
        let escapes: Bool
        let spansLines: Bool
        /// `$name` inside the string is a shell variable.
        let interpolates: Bool

        init(
            _ delimiter: String,
            escapes: Bool = true,
            spansLines: Bool = false,
            interpolates: Bool = false
        ) {
            open = delimiter
            close = delimiter
            self.escapes = escapes
            self.spansLines = spansLines
            self.interpolates = interpolates
        }
    }

    struct Grammar {
        let lineComments: [String]
        let blockComment: (open: String, close: String)?
        /// Checked in order, so longer delimiters that share a prefix go first.
        let strings: [StringDelimiter]
        let keywords: Set<String>
        /// Keywords are stored lowercased and words compared lowercased.
        let ignoresKeywordCase: Bool
        /// A line comment only starts at the beginning of a word, as in shell,
        /// where `a#b` is one word.
        let commentsStartWords: Bool
        let hasShellVariables: Bool
        /// Characters besides letters, digits, and `_` that belong to a word, so
        /// that a keyword inside `fix/for-real` is not highlighted.
        let extraWordCharacters: String

        static let python = Grammar(
            lineComments: ["#"],
            blockComment: nil,
            strings: [
                StringDelimiter(#"""""#, spansLines: true),
                StringDelimiter("'''", spansLines: true),
                StringDelimiter(#"""#),
                StringDelimiter("'")
            ],
            keywords: [
                "False", "None", "True", "and", "as", "assert", "async", "await", "break",
                "class", "continue", "def", "del", "elif", "else", "except", "finally",
                "for", "from", "global", "if", "import", "in", "is", "lambda", "nonlocal",
                "not", "or", "pass", "raise", "return", "try", "while", "with", "yield"
            ],
            ignoresKeywordCase: false,
            commentsStartWords: false,
            hasShellVariables: false,
            extraWordCharacters: ""
        )

        static let sql = Grammar(
            lineComments: ["--"],
            blockComment: ("/*", "*/"),
            strings: [StringDelimiter("'", escapes: false, spansLines: true)],
            keywords: [
                "add", "all", "alter", "analyze", "and", "as", "asc", "begin", "between",
                "by", "case", "column", "commit", "create", "cross", "database", "default",
                "delete", "desc", "distinct", "drop", "else", "end", "exists", "explain",
                "false", "foreign", "from", "full", "grant", "group", "having", "if", "in",
                "index", "inner", "insert", "into", "is", "join", "key", "left", "like",
                "limit", "not", "null", "offset", "on", "or", "order", "outer", "primary",
                "references", "returning", "revoke", "right", "rollback", "schema", "select",
                "set", "table", "then", "transaction", "true", "truncate", "union", "unique",
                "update", "using", "values", "view", "when", "where", "with"
            ],
            ignoresKeywordCase: true,
            commentsStartWords: false,
            hasShellVariables: false,
            extraWordCharacters: ""
        )

        static let shell = Grammar(
            lineComments: ["#"],
            blockComment: nil,
            strings: [
                StringDelimiter(#"""#, spansLines: true, interpolates: true),
                StringDelimiter("'", escapes: false, spansLines: true)
            ],
            keywords: [
                "case", "declare", "do", "done", "elif", "else", "esac", "export", "fi",
                "for", "function", "if", "in", "local", "readonly", "return", "select",
                "then", "unset", "until", "while"
            ],
            ignoresKeywordCase: false,
            commentsStartWords: true,
            hasShellVariables: true,
            extraWordCharacters: "-./:@%+,=~"
        )

        static let javaScript = Grammar(
            lineComments: ["//"],
            blockComment: ("/*", "*/"),
            strings: [
                StringDelimiter(#"""#),
                StringDelimiter("'"),
                StringDelimiter("`", spansLines: true)
            ],
            keywords: [
                "as", "async", "await", "break", "case", "catch", "class", "const",
                "continue", "default", "delete", "do", "else", "enum", "export", "extends",
                "false", "finally", "for", "function", "if", "implements", "import", "in",
                "instanceof", "interface", "let", "new", "null", "of", "private", "public",
                "readonly", "return", "static", "super", "switch", "this", "throw", "true",
                "try", "type", "typeof", "undefined", "var", "void", "while", "yield"
            ],
            ignoresKeywordCase: false,
            commentsStartWords: false,
            hasShellVariables: false,
            extraWordCharacters: "$"
        )

        static let json = Grammar(
            lineComments: [],
            blockComment: nil,
            strings: [StringDelimiter(#"""#)],
            keywords: ["false", "null", "true"],
            ignoresKeywordCase: false,
            commentsStartWords: false,
            hasShellVariables: false,
            extraWordCharacters: ""
        )
    }

    private struct Scanner {
        let units: [UInt16]
        let grammar: Grammar
        private let lineComments: [[UInt16]]
        private let blockComment: (open: [UInt16], close: [UInt16])?
        private let strings: [(open: [UInt16], close: [UInt16], delimiter: StringDelimiter)]
        private let extraWordCharacters: Set<UInt16>
        private var tokens: [Token] = []

        private static let backslash = UInt16(ascii: "\\")
        private static let newline = UInt16(ascii: "\n")
        private static let dollar = UInt16(ascii: "$")

        init(units: [UInt16], grammar: Grammar) {
            self.units = units
            self.grammar = grammar
            lineComments = grammar.lineComments.map { Array($0.utf16) }
            blockComment = grammar.blockComment.map { (Array($0.open.utf16), Array($0.close.utf16)) }
            strings = grammar.strings.map { (Array($0.open.utf16), Array($0.close.utf16), $0) }
            extraWordCharacters = Set(grammar.extraWordCharacters.utf16)
        }

        mutating func scan() -> [Token] {
            var index = 0
            while index < units.count {
                if let end = commentEnd(at: index) {
                    append(.comment, index..<end)
                    index = end
                } else if let string = strings.first(where: { hasPrefix($0.open, at: index) }) {
                    index = scanString(from: index, open: string.open, close: string.close, delimiter: string.delimiter)
                } else if grammar.hasShellVariables, let end = variableEnd(at: index) {
                    append(.variable, index..<end)
                    index = end
                } else if units[index] == Self.backslash {
                    // An escaped character, such as `\"` in shell, never starts a token.
                    index += 2
                } else if isWordCharacter(units[index]) {
                    index = scanWord(from: index)
                } else {
                    index += 1
                }
            }
            return tokens
        }

        private func commentEnd(at index: Int) -> Int? {
            if let blockComment, hasPrefix(blockComment.open, at: index) {
                var end = index + blockComment.open.count
                while end < units.count, !hasPrefix(blockComment.close, at: end) {
                    end += 1
                }
                return min(end + blockComment.close.count, units.count)
            }

            guard lineComments.contains(where: { hasPrefix($0, at: index) }) else { return nil }
            if grammar.commentsStartWords, index > 0, !isWhitespace(units[index - 1]) {
                return nil
            }
            var end = index
            while end < units.count, units[end] != Self.newline {
                end += 1
            }
            return end
        }

        /// Unterminated strings run to the end of the line, or of the text when
        /// the delimiter spans lines.
        private mutating func scanString(
            from start: Int,
            open: [UInt16],
            close: [UInt16],
            delimiter: StringDelimiter
        ) -> Int {
            var interpolated: [Token] = []
            var index = start + open.count

            while index < units.count {
                if delimiter.escapes, units[index] == Self.backslash {
                    index += 2
                } else if !delimiter.spansLines, units[index] == Self.newline {
                    break
                } else if hasPrefix(close, at: index) {
                    index += close.count
                    break
                } else if delimiter.interpolates, let end = variableEnd(at: index) {
                    interpolated.append(Token(kind: .variable, range: NSRange(index..<end)))
                    index = end
                } else {
                    index += 1
                }
            }

            let end = min(index, units.count)
            append(.string, start..<end)
            tokens.append(contentsOf: interpolated)
            return end
        }

        /// `$name`, `${name}`, and the special parameters such as `$1` and `$?`.
        private func variableEnd(at index: Int) -> Int? {
            guard units[index] == Self.dollar, index + 1 < units.count else { return nil }
            let next = units[index + 1]

            if next == UInt16(ascii: "{") {
                guard let close = units[(index + 2)...].firstIndex(of: UInt16(ascii: "}")) else {
                    return nil
                }
                return close + 1
            }
            if isLetter(next) || next == UInt16(ascii: "_") {
                var end = index + 2
                while end < units.count, isLetter(units[end]) || isDigit(units[end]) || units[end] == UInt16(ascii: "_") {
                    end += 1
                }
                return end
            }
            if isDigit(next) || "?#@*!$-".utf16.contains(next) {
                return index + 2
            }
            return nil
        }

        /// A word starting with a digit is a number, covering forms such as
        /// `3.14`, `0x1F`, and `1_000`, unless other word characters follow, as
        /// in the shell word `1.2.3-beta`.
        private mutating func scanWord(from start: Int) -> Int {
            var index = start

            if isDigit(units[start]) {
                while index < units.count,
                      isLetter(units[index]) || isDigit(units[index])
                        || units[index] == UInt16(ascii: "_") || units[index] == UInt16(ascii: ".") {
                    index += 1
                }
                if index == units.count || !isWordCharacter(units[index]) {
                    append(.number, start..<index)
                    return index
                }
            }

            while index < units.count, isWordCharacter(units[index]) {
                index += 1
            }

            let word = String(utf16CodeUnits: Array(units[start..<index]), count: index - start)
            if grammar.keywords.contains(grammar.ignoresKeywordCase ? word.lowercased() : word) {
                append(.keyword, start..<index)
            }
            return index
        }

        private mutating func append(_ kind: TokenKind, _ range: Range<Int>) {
            tokens.append(Token(kind: kind, range: NSRange(range)))
        }

        private func hasPrefix(_ prefix: [UInt16], at index: Int) -> Bool {
            guard index + prefix.count <= units.count else { return false }
            return units[index..<(index + prefix.count)].elementsEqual(prefix)
        }

        /// Non-ASCII units count as word characters so that a keyword is never
        /// found in the middle of a word such as `éselect`.
        private func isWordCharacter(_ unit: UInt16) -> Bool {
            isLetter(unit) || isDigit(unit) || unit == UInt16(ascii: "_")
                || unit >= 0x80 || extraWordCharacters.contains(unit)
        }

        private func isLetter(_ unit: UInt16) -> Bool {
            (UInt16(ascii: "a")...UInt16(ascii: "z")).contains(unit)
                || (UInt16(ascii: "A")...UInt16(ascii: "Z")).contains(unit)
        }

        private func isDigit(_ unit: UInt16) -> Bool {
            (UInt16(ascii: "0")...UInt16(ascii: "9")).contains(unit)
        }

        private func isWhitespace(_ unit: UInt16) -> Bool {
            unit == UInt16(ascii: " ") || unit == UInt16(ascii: "\t") || unit == Self.newline
        }
    }
}

private extension UInt16 {
    init(ascii scalar: Unicode.Scalar) {
        self = UInt16(scalar.value)
    }
}
