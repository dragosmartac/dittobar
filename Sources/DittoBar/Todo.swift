import Foundation

/// Reads and rewrites the single Markdown line a todo is written on.
///
/// A todo line is a task list item, `- [ ] Text` or `- [x] Text`. Outside an
/// entry the list marker may be left out and the brackets left empty, so
/// `[] Text` and `- [] Text` also work. Rewriting a line always produces the
/// canonical form.
enum TodoLine {
    struct Parsed: Equatable {
        let indent: String
        /// `-`, `*`, `+`, `1.`, or `1)`, or nil when the line starts with the
        /// brackets.
        let marker: String?
        let isDone: Bool
        /// The text after the checkbox, tokens included.
        let rawItemText: String
    }

    static func parse(_ line: String, allowsShorthand: Bool) -> Parsed? {
        let indent = String(line.prefix { $0 == " " || $0 == "\t" })
        var rest = line.dropFirst(indent.count)

        var marker: String?
        if let first = rest.first, "-*+".contains(first),
           rest.dropFirst().first == " " {
            marker = String(first)
            rest = rest.dropFirst(2)
        } else {
            let digits = rest.prefix { $0.isASCII && $0.isNumber }
            let afterDigits = rest.dropFirst(digits.count)
            if (1...9).contains(digits.count),
               let delimiter = afterDigits.first, delimiter == "." || delimiter == ")",
               afterDigits.dropFirst().first == " " {
                marker = String(digits) + String(delimiter)
                rest = afterDigits.dropFirst(2)
            }
        }
        guard marker != nil || allowsShorthand else { return nil }
        rest = rest.drop { $0 == " " }

        let checkboxes: [(String, Bool)] = allowsShorthand
            ? [("[ ]", false), ("[]", false), ("[x]", true), ("[X]", true)]
            : [("[ ]", false), ("[x]", true), ("[X]", true)]
        guard let (checkbox, isDone) = checkboxes.first(where: { rest.hasPrefix($0.0) }) else {
            return nil
        }
        rest = rest.dropFirst(checkbox.count)
        guard rest.first == " " || rest.first == "\t" else { return nil }

        let text = rest.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return Parsed(indent: indent, marker: marker, isDone: isDone, rawItemText: text)
    }

    /// The line in canonical form with its checkbox set, and `done:` set to
    /// `today` when checked or removed when unchecked. Nil when the line is
    /// not a todo.
    static func settingDone(_ isDone: Bool, in line: String, today: String) -> String? {
        guard let parsed = parse(line, allowsShorthand: true) else { return nil }
        var words = TodoTokens.words(in: parsed.rawItemText)
            .filter { TodoTokens.doneDate(in: $0) == nil }
        if isDone {
            words.append("done:\(today)")
        }
        let checkbox = isDone ? "[x]" : "[ ]"
        let text = words.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return "\(parsed.indent)\(parsed.marker ?? "-") \(checkbox) \(text)"
    }
}

/// The metadata words in a todo's text: `!1`–`!3` for priority, `#tag`,
/// `due:YYYY-MM-DD`, and `done:YYYY-MM-DD`. A word only counts as a token on
/// its own and outside inline code.
enum TodoTokens {
    struct Parsed: Equatable {
        /// The text with the tokens removed.
        let rawText: String
        let priority: Int?
        let tags: [String]
        let dueDate: String?
        let doneDate: String?
    }

    static func parse(_ rawItemText: String) -> Parsed {
        var kept: [String] = []
        var priority: Int?
        var tags: [String] = []
        var dueDate: String?
        var doneDate: String?
        var isInsideCode = false

        for word in words(in: rawItemText) {
            if word.contains("`") {
                if word.filter({ $0 == "`" }).count % 2 == 1 {
                    isInsideCode.toggle()
                }
                kept.append(word)
                continue
            }
            guard !isInsideCode else {
                kept.append(word)
                continue
            }

            if let value = self.priority(in: word) {
                priority = priority.map { min($0, value) } ?? value
            } else if let tag = tag(in: word) {
                if !tags.contains(tag) {
                    tags.append(tag)
                }
            } else if let date = date(in: word, prefix: "due:") {
                dueDate = date
            } else if let date = Self.doneDate(in: word) {
                doneDate = date
            } else {
                kept.append(word)
            }
        }

        return Parsed(
            rawText: kept.joined(separator: " ").trimmingCharacters(in: .whitespaces),
            priority: priority,
            tags: tags,
            dueDate: dueDate,
            doneDate: doneDate
        )
    }

    /// Split on single spaces, so joining them back keeps any other spacing.
    static func words(in text: String) -> [String] {
        text.components(separatedBy: " ")
    }

    static func doneDate(in word: String) -> String? {
        date(in: word, prefix: "done:")
    }

    private static func priority(in word: String) -> Int? {
        guard word.count == 2, word.hasPrefix("!"),
              let value = Int(word.dropFirst()), (1...3).contains(value) else { return nil }
        return value
    }

    /// `#` followed by a letter, then letters, digits, `-`, `_`, or `/`, so
    /// `#1` and `C#` are left alone.
    private static func tag(in word: String) -> String? {
        guard word.hasPrefix("#") else { return nil }
        let name = word.dropFirst()
        guard let first = name.first, first.isLetter,
              name.allSatisfy({ $0.isLetter || $0.isNumber || "-_/".contains($0) }) else {
            return nil
        }
        return String(name)
    }

    private static func date(in word: String, prefix: String) -> String? {
        guard word.hasPrefix(prefix) else { return nil }
        let value = String(word.dropFirst(prefix.count))
        return TodoDate.isValid(value) ? value : nil
    }
}

/// Todo dates are `YYYY-MM-DD` strings in the local calendar, so they compare
/// in order as plain strings.
enum TodoDate {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }

    static func isValid(_ value: String) -> Bool {
        value.count == 10 && formatter.date(from: value).map(formatter.string(from:)) == value
    }

    /// `Oct 17`, or `Oct 17, 2027` outside the current year.
    static func displayString(for value: String, today: String) -> String {
        guard let date = formatter.date(from: value) else { return value }
        return value.prefix(4) == today.prefix(4)
            ? date.formatted(.dateTime.month(.abbreviated).day())
            : date.formatted(.dateTime.month(.abbreviated).day().year())
    }
}

/// Checks a todo off, or back on, in its Markdown file.
enum TodoWriter {
    enum Failure: LocalizedError {
        case lineChanged

        var errorDescription: String? {
            "The todo changed in its file since it was loaded. Try again."
        }
    }

    /// Rewrites only the todo's line, and only if it still reads as it did
    /// when the file was parsed, so edits made meanwhile in an editor are
    /// never overwritten.
    static func setDone(_ isDone: Bool, for todo: TodoEntry, today: String) throws {
        let source = todo.source
        let contents = try String(contentsOf: source.fileURL, encoding: .utf8)
        var lines = contents.components(separatedBy: "\n")
        guard lines.indices.contains(source.lineIndex) else { throw Failure.lineChanged }

        let original = lines[source.lineIndex]
        let lineEnding = original.hasSuffix("\r") ? "\r" : ""
        let line = String(original.dropLast(lineEnding.count))
        guard line == source.line,
              let rewritten = TodoLine.settingDone(isDone, in: line, today: today) else {
            throw Failure.lineChanged
        }

        lines[source.lineIndex] = rewritten + lineEnding
        try lines.joined(separator: "\n").write(to: source.fileURL, atomically: true, encoding: .utf8)
    }
}
