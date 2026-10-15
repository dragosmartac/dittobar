import Foundation

enum CheatSheetParser {
    private struct EntryDraft {
        let title: String
        let rawDescription: String
        let rawFencedContent: String?
        let fenceLanguage: String?
    }

    static func parse(_ source: String, fileURL: URL) -> CheatSheet {
        let fileName = fileURL.lastPathComponent
        // Split as `TodoWriter` does, so todo line indexes match the file.
        let lines = source.components(separatedBy: "\n").map { line in
            line.hasSuffix("\r") ? String(line.dropLast()) : line
        }
        let fallbackTitle = Self.fallbackTitle(for: fileURL)

        var sheetTitle = fallbackTitle
        var hasParsedSheetTitle = false
        var entryTitle: String?
        var descriptionLines: [String] = []
        var items: [CheatSheetItem] = []
        var todos: [TodoEntry] = []
        var sectionTitle: String?
        var entryCount = 0
        var sectionCount = 0
        var isInsideComment = false
        var index = 0

        func appendEntry(rawFencedContent: String? = nil, fenceLanguage: String? = nil) {
            defer {
                entryTitle = nil
                descriptionLines = []
            }

            guard let title = entryTitle else { return }
            let draft = EntryDraft(
                title: title,
                rawDescription: descriptionLines.joined(separator: "\n"),
                rawFencedContent: rawFencedContent,
                fenceLanguage: fenceLanguage
            )
            if let entry = makeEntry(from: draft, fileName: fileName, entryIndex: entryCount) {
                items.append(.entry(entry))
                entryCount += 1
            }
        }

        func appendTodo(_ parsed: TodoLine.Parsed, lineIndex: Int) {
            let todo = makeTodo(
                from: parsed,
                source: TodoSource(fileURL: fileURL, lineIndex: lineIndex, line: lines[lineIndex]),
                context: [sheetTitle, sectionTitle, entryTitle].compactMap { $0 },
                // The ID the entry is about to be given in `appendEntry`.
                containingEntryID: entryTitle.map { "\(fileName):\(entryCount):\($0)" }
            )
            todos.append(todo)
            if !todo.isInsideEntry {
                items.append(.entry(.todo(todo)))
            }
        }

        func appendSection(title: String) {
            items.append(
                .section(
                    CheatSheetSection(
                        id: "\(fileName):section:\(sectionCount):\(title)",
                        title: title
                    )
                )
            )
            sectionCount += 1
        }

        while index < lines.count {
            let line = lines[index]

            // `<!-- ... -->` regions are ignored entirely, so a file can carry
            // instructions that themselves contain headings and code fences.
            // Fenced code blocks are consumed below, so their contents are safe.
            if isInsideComment {
                if line.contains("-->") {
                    isInsideComment = false
                }
                index += 1
                continue
            }

            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if trimmedLine.hasPrefix("<!--") {
                isInsideComment = !trimmedLine.dropFirst(4).contains("-->")
                index += 1
                continue
            }

            if line.hasPrefix("# ") {
                appendEntry()
                if !hasParsedSheetTitle, items.allSatisfy({ $0.todo != nil }) {
                    sheetTitle = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                    hasParsedSheetTitle = true
                }
                index += 1
                continue
            }

            if line.hasPrefix("## ") {
                appendEntry()
                let title = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                appendSection(title: title)
                sectionTitle = title
                descriptionLines = []
                index += 1
                continue
            }

            if line.hasPrefix("### ") {
                appendEntry()
                entryTitle = String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces)
                descriptionLines = []
                index += 1
                continue
            }

            if line.hasPrefix("```") {
                let language = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var contentLines: [String] = []
                index += 1

                while index < lines.count, !lines[index].hasPrefix("```") {
                    contentLines.append(lines[index])
                    index += 1
                }

                appendEntry(
                    rawFencedContent: contentLines.joined(separator: "\n"),
                    fenceLanguage: language
                )
                index += 1
                continue
            }

            // Outside an entry, todos stand on their own and the shorthand
            // forms are accepted. Inside one, they stay part of its text.
            if let todo = TodoLine.parse(line, allowsShorthand: entryTitle == nil) {
                appendTodo(todo, lineIndex: index)
            }

            if entryTitle != nil {
                // Leading whitespace nests list items, so only trim the end.
                descriptionLines.append(String(line.reversed().drop(while: { $0 == " " || $0 == "\t" }).reversed()))
            }
            index += 1
        }

        appendEntry()

        return CheatSheet(
            id: fileName,
            title: sheetTitle,
            items: items,
            sourceURL: fileURL,
            todos: todos
        )
    }

    private static func makeTodo(
        from parsed: TodoLine.Parsed,
        source: TodoSource,
        context: [String],
        containingEntryID: String?
    ) -> TodoEntry {
        let fileName = source.fileURL.lastPathComponent
        let tokens = TodoTokens.parse(parsed.rawItemText)
        return TodoEntry(
            metadata: EntryMetadata(
                id: "\(fileName):todo:\(source.lineIndex)",
                storageKey: "\(fileName)#todo:\(tokens.rawText)",
                title: MarkdownText.stripped(tokens.rawText)
            ),
            isDone: parsed.isDone,
            rawItemText: parsed.rawItemText,
            rawText: tokens.rawText,
            priority: tokens.priority,
            tags: tokens.tags,
            dueDate: tokens.dueDate,
            doneDate: tokens.doneDate,
            variables: TextVariables.variables(in: tokens.rawText),
            source: source,
            context: context,
            containingEntryID: containingEntryID
        )
    }

    private static func makeEntry(
        from draft: EntryDraft,
        fileName: String,
        entryIndex: Int
    ) -> CheatSheetEntry? {
        let rawDescription = draft.rawDescription
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let rawFencedContent = draft.rawFencedContent?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let metadata = EntryMetadata(
            id: "\(fileName):\(entryIndex):\(draft.title)",
            storageKey: "\(fileName)#\(draft.title)",
            title: draft.title
        )

        if let rawFencedContent, !rawFencedContent.isEmpty {
            let description = rawDescription.isEmpty ? nil : rawDescription
            let variableSource = [description, rawFencedContent]
                .compactMap { $0 }
                .joined(separator: "\n")
            let variables = TextVariables.variables(in: variableSource)

            if draft.fenceLanguage?.caseInsensitiveCompare("url") == .orderedSame {
                return .url(
                    URLEntry(
                        metadata: metadata,
                        rawDescription: description,
                        rawURL: rawFencedContent,
                        variables: variables
                    )
                )
            }

            let language = draft.fenceLanguage?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return .command(
                CommandEntry(
                    metadata: metadata,
                    rawDescription: description,
                    rawCommand: rawFencedContent,
                    language: language?.isEmpty == true ? nil : language,
                    variables: variables
                )
            )
        }

        guard !rawDescription.isEmpty else { return nil }
        return .note(
            NoteEntry(
                metadata: metadata,
                rawContent: rawDescription,
                variables: TextVariables.variables(in: rawDescription)
            )
        )
    }

    private static func fallbackTitle(for fileURL: URL) -> String {
        /* Computes a fallback title for the case in which one is
         not defined in the md file */
        return fileURL
            .deletingPathExtension()
            .lastPathComponent
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }
}
