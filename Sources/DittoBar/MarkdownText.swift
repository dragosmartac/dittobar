import Foundation

enum MarkdownText {
    enum Block: Equatable {
        case text(String)
        case table(Table)
    }

    struct Table: Equatable {
        let header: [String]
        let rows: [[String]]

        var columnCount: Int { header.count }
    }

    /// Returns the text a user sees after Markdown formatting is removed.
    static func stripped(_ source: String) -> String {
        blocks(in: source).map { block in
            switch block {
            case .text(let text):
                return strippedInline(text)
            case .table(let table):
                return ([table.header] + table.rows)
                    .map { $0.map(strippedInline).joined(separator: "\t") }
                    .joined(separator: "\n")
            }
        }.joined(separator: "\n")
    }

    static func blocks(in source: String) -> [Block] {
        let lines = source.components(separatedBy: .newlines)
        var result: [Block] = []
        var textLines: [String] = []
        var index = 0

        func appendText() {
            let text = textLines.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                result.append(.text(text))
            }
            textLines = []
        }

        while index < lines.count {
            if index + 1 < lines.count,
               let header = tableCells(in: lines[index]),
               isTableSeparator(lines[index + 1], columnCount: header.count) {
                appendText()
                index += 2
                var rows: [[String]] = []

                while index < lines.count,
                      let row = tableCells(in: lines[index]) {
                    rows.append(normalized(row, columnCount: header.count))
                    index += 1
                }

                result.append(.table(Table(header: header, rows: rows)))
                continue
            }

            textLines.append(lines[index])
            index += 1
        }

        appendText()
        return result
    }

    private static func strippedInline(_ source: String) -> String {
        guard let parsed = try? AttributedString(
            markdown: source,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) else {
            return source
        }
        return String(parsed.characters)
    }

    private static func tableCells(in line: String) -> [String]? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|") else { return nil }

        var cells: [String] = []
        var current = ""
        var isEscaped = false
        var isInsideCode = false

        for character in trimmed {
            if isEscaped {
                current.append(character)
                isEscaped = false
                continue
            }
            if character == "\\" {
                current.append(character)
                isEscaped = true
                continue
            }
            if character == "`" {
                isInsideCode.toggle()
                current.append(character)
                continue
            }
            if character == "|", !isInsideCode {
                cells.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(character)
            }
        }
        cells.append(current.trimmingCharacters(in: .whitespaces))

        if trimmed.hasPrefix("|") {
            cells.removeFirst()
        }
        if trimmed.hasSuffix("|"), cells.last?.isEmpty == true {
            cells.removeLast()
        }
        return cells.isEmpty ? nil : cells
    }

    private static func isTableSeparator(_ line: String, columnCount: Int) -> Bool {
        guard let cells = tableCells(in: line), cells.count == columnCount else {
            return false
        }
        return cells.allSatisfy { cell in
            var marker = cell.trimmingCharacters(in: .whitespaces)
            if marker.hasPrefix(":"), marker.hasSuffix(":"), marker.count >= 2 {
                marker.removeFirst()
                marker.removeLast()
            } else if marker.hasPrefix(":") {
                marker.removeFirst()
            } else if marker.hasSuffix(":") {
                marker.removeLast()
            }
            return marker.count >= 3 && marker.allSatisfy { $0 == "-" }
        }
    }

    private static func normalized(_ cells: [String], columnCount: Int) -> [String] {
        if cells.count >= columnCount {
            return Array(cells.prefix(columnCount))
        }
        return cells + Array(repeating: "", count: columnCount - cells.count)
    }
}
