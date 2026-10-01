import Foundation

enum CheatSheetParser {
    static func parse(_ source: String, fileURL: URL) -> CheatSheet {
        let fileName = fileURL.lastPathComponent
        let lines = source.components(separatedBy: .newlines)
        let fallbackTitle = Self.fallbackTitle(for: fileURL)

        var sheetTitle = fallbackTitle
        var entryTitle: String?
        var groupTitle: String?
        var descriptionLines: [String] = []
        var commands: [CheatCommand] = []
        var sections: [CheatSheetSection] = []
        var isInsideComment = false
        var index = 0

        func appendEntry(
            title: String,
            sectionTitle: String?,
            description: String,
            command: String,
            language: String
        ) {
            let identifier = "\(fileName):\(commands.count):\(title)"
            commands.append(
                CheatCommand(
                    id: identifier,
                    storageKey: "\(fileName)#\(title)",
                    title: title,
                    sectionTitle: sectionTitle,
                    description: description,
                    command: command,
                    language: language,
                    variables: CommandTemplate.variables(in: "\(description)\n\(command)")
                )
            )
        }

        func appendSection(title: String) {
            sections.append(
                CheatSheetSection(
                    id: "\(fileName):section:\(sections.count):\(title)",
                    title: title,
                    commandOffset: commands.count
                )
            )
        }

        func finishDescriptionOnlyEntry() {
            defer {
                entryTitle = nil
                descriptionLines = []
            }

            guard let title = entryTitle else { return }
            let description = descriptionLines
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !description.isEmpty else { return }
            appendEntry(
                title: title,
                sectionTitle: groupTitle,
                description: description,
                command: "",
                language: ""
            )
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
                finishDescriptionOnlyEntry()
                groupTitle = nil
                sheetTitle = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                index += 1
                continue
            }

            if line.hasPrefix("## ") {
                finishDescriptionOnlyEntry()
                let title = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                appendSection(title: title)
                groupTitle = title
                descriptionLines = []
                index += 1
                continue
            }

            if line.hasPrefix("### ") {
                finishDescriptionOnlyEntry()
                entryTitle = String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces)
                descriptionLines = []
                index += 1
                continue
            }

            if line.hasPrefix("```") {
                let language = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                index += 1

                while index < lines.count, !lines[index].hasPrefix("```") {
                    codeLines.append(lines[index])
                    index += 1
                }

                if let title = entryTitle {
                    let command = codeLines.joined(separator: "\n")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !command.isEmpty {
                        let description = descriptionLines
                            .joined(separator: " ")
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        appendEntry(
                            title: title,
                            sectionTitle: groupTitle,
                            description: description,
                            command: command,
                            language: language
                        )
                    } else {
                        finishDescriptionOnlyEntry()
                    }
                }

                entryTitle = nil
                descriptionLines = []
                index += 1
                continue
            }

            if entryTitle != nil, !line.trimmingCharacters(in: .whitespaces).isEmpty {
                descriptionLines.append(line.trimmingCharacters(in: .whitespaces))
            }
            index += 1
        }

        finishDescriptionOnlyEntry()

        return CheatSheet(
            id: fileName,
            title: sheetTitle,
            commands: commands,
            sections: sections,
            sourceURL: fileURL
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
