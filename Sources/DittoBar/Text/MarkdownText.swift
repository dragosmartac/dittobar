import Foundation

enum MarkdownText {
    enum Block: Equatable {
        case text(String)
        case quote(String)
        case table(Table)
        case list([ListItem])
    }

    /// One item of a list. Nested items follow their parent with a greater
    /// depth, so a list is flat and reads top to bottom.
    struct ListItem: Hashable {
        enum Marker: Hashable {
            case bullet
            /// The number shown, which follows the first item's number rather
            /// than the numbers written on later items, as in CommonMark.
            case ordered(Int)
        }

        enum Task: Hashable {
            case open
            case done
        }

        let depth: Int
        let marker: Marker
        let task: Task?
        let text: String

        init(depth: Int = 0, marker: Marker = .bullet, task: Task? = nil, text: String) {
            self.depth = depth
            self.marker = marker
            self.task = task
            self.text = text
        }

        static func bulletGlyph(depth: Int) -> String {
            ["•", "◦", "▪"][depth % 3]
        }

        /// The marker shown before the item text, e.g. `•`, `3.`, or `☐`.
        var displayMarker: String {
            let base: String
            switch marker {
            case .bullet:
                base = task == nil ? Self.bulletGlyph(depth: depth) : ""
            case .ordered(let number):
                base = "\(number)."
            }
            let checkbox: String
            switch task {
            case .open: checkbox = "☐"
            case .done: checkbox = "☑"
            case nil: checkbox = ""
            }
            return [base, checkbox].filter { !$0.isEmpty }.joined(separator: " ")
        }
    }

    private struct ListItemLine {
        let indent: Int
        let marker: ListItem.Marker
        let task: ListItem.Task?
        let text: String
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
            case .quote(let text):
                return strippedInline(text)
            case .table(let table):
                return ([table.header] + table.rows)
                    .map { $0.map(strippedInline).joined(separator: "\t") }
                    .joined(separator: "\n")
            case .list(let items):
                return items.map { item in
                    let indent = String(repeating: "\t", count: item.depth)
                    return indent + item.displayMarker + " " + strippedInline(item.text)
                        .replacingOccurrences(of: "\n", with: "\n" + indent + "\t")
                }.joined(separator: "\n")
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
            if let firstLine = quoteContent(in: lines[index]) {
                appendText()
                var quoteLines = [firstLine]
                index += 1

                while index < lines.count,
                      let line = quoteContent(in: lines[index]) {
                    quoteLines.append(line)
                    index += 1
                }

                let quote = quoteLines.joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !quote.isEmpty {
                    result.append(.quote(quote))
                }
                continue
            }

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

            let previousText = textLines.last?.trimmingCharacters(in: .whitespaces) ?? ""
            if let firstItem = listItemLine(in: lines[index]),
               previousText.isEmpty || canInterruptText(firstItem) {
                appendText()
                let (items, nextIndex) = list(in: lines, from: index)
                result.append(.list(items))
                index = nextIndex
                continue
            }

            // Leading whitespace only matters for nesting list items.
            textLines.append(lines[index].trimmingCharacters(in: .whitespaces))
            index += 1
        }

        appendText()
        return result
    }

    /// Consumes a list starting at `start`. A list ends at the first line that
    /// is neither an item nor indented under the previous item, and blank
    /// lines stay inside the list only when the list continues after them.
    private static func list(in lines: [String], from start: Int) -> ([ListItem], Int) {
        var items: [ListItem] = []
        /// Indents of the most recent item at each open depth.
        var openIndents: [Int] = []
        /// The number of the most recent item at each open depth, when ordered.
        var lastNumbers: [Int?] = []
        var index = start
        var pendingBlankLines = 0

        while index < lines.count {
            let line = lines[index]
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                pendingBlankLines += 1
                index += 1
                continue
            }

            if let item = listItemLine(in: line) {
                // The last level popped is the previous sibling, if any.
                var sibling: Int?
                while let last = openIndents.last, item.indent < last + nestingIndent {
                    openIndents.removeLast()
                    sibling = lastNumbers.removeLast()
                }
                let depth = openIndents.count

                var marker = item.marker
                var number: Int?
                if case .ordered(let written) = item.marker {
                    let shown = sibling.map { $0 + 1 } ?? written
                    marker = .ordered(shown)
                    number = shown
                }
                openIndents.append(item.indent)
                lastNumbers.append(number)

                items.append(ListItem(depth: depth, marker: marker, task: item.task, text: item.text))
                pendingBlankLines = 0
                index += 1
                continue
            }

            if let lastIndent = openIndents.last,
               let last = items.last,
               indentWidth(of: line) >= lastIndent + nestingIndent {
                let separator = pendingBlankLines > 0 ? "\n\n" : "\n"
                items[items.count - 1] = ListItem(
                    depth: last.depth,
                    marker: last.marker,
                    task: last.task,
                    text: last.text + separator + line.trimmingCharacters(in: .whitespaces)
                )
                pendingBlankLines = 0
                index += 1
                continue
            }

            break
        }

        // Trailing blank lines belong to whatever follows the list.
        return (items, index - pendingBlankLines)
    }

    /// Indenting an item at least this many columns past the previous item
    /// nests it, and indenting a line this far continues the previous item.
    private static let nestingIndent = 2

    /// Like CommonMark, an ordered list may only interrupt a paragraph when it
    /// starts at 1, so prose such as "Released in\n2024. Then…" stays text.
    private static func canInterruptText(_ item: ListItemLine) -> Bool {
        guard case .ordered(let number) = item.marker else { return true }
        return number == 1
    }

    private static func indentWidth(of line: String) -> Int {
        var width = 0
        for character in line {
            if character == " " {
                width += 1
            } else if character == "\t" {
                width += 4 - width % 4
            } else {
                break
            }
        }
        return width
    }

    private static func listItemLine(in line: String) -> ListItemLine? {
        let content = line.drop(while: { $0 == " " || $0 == "\t" })
        guard !isThematicBreak(content) else { return nil }

        let marker: ListItem.Marker
        var rest: Substring
        if let first = content.first, "-*+".contains(first) {
            marker = .bullet
            rest = content.dropFirst()
        } else {
            let digits = content.prefix(while: { $0.isASCII && $0.isNumber })
            guard (1...9).contains(digits.count),
                  let number = Int(digits) else { return nil }
            rest = content.dropFirst(digits.count)
            guard let delimiter = rest.first, delimiter == "." || delimiter == ")" else {
                return nil
            }
            marker = .ordered(number)
            rest = rest.dropFirst()
        }

        guard let separator = rest.first, separator == " " || separator == "\t" else {
            return nil
        }
        var text = rest.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }

        var task: ListItem.Task?
        for (prefix, state) in [("[ ] ", ListItem.Task.open), ("[x] ", .done), ("[X] ", .done)]
        where text.hasPrefix(prefix) {
            let remainder = text.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
            if !remainder.isEmpty {
                task = state
                text = remainder
            }
            break
        }

        return ListItemLine(indent: indentWidth(of: line), marker: marker, task: task, text: text)
    }

    /// `---`, `***`, and `* * *` are horizontal rules in Markdown, not items.
    private static func isThematicBreak(_ content: Substring) -> Bool {
        let marks = content.filter { $0 != " " && $0 != "\t" }
        guard marks.count >= 3, let first = marks.first, "-*_".contains(first) else {
            return false
        }
        return marks.allSatisfy { $0 == first }
    }

    private static func quoteContent(in line: String) -> String? {
        var content = line.drop(while: { $0 == " " || $0 == "\t" })
        guard content.first == ">" else { return nil }
        content.removeFirst()
        if content.first == " " {
            content.removeFirst()
        }
        return String(content)
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
