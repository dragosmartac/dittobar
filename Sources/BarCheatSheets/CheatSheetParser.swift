import Foundation

enum CheatSheetParser {
    static func parse(_ source: String, fileURL: URL) -> CheatSheet {
        let fileName = fileURL.lastPathComponent
        let lines = source.components(separatedBy: .newlines)
        let fallbackTitle = URL(fileURLWithPath: fileName)
            .deletingPathExtension()
            .lastPathComponent
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .capitalized

        var sheetTitle = fallbackTitle
        var sectionTitle: String?
        var descriptionLines: [String] = []
        var commands: [CheatCommand] = []
        var isInsideComment = false
        var index = 0

        func appendEntry(title: String, detail: String, command: String, language: String) {
            let identifier = "\(fileName):\(commands.count):\(title)"
            commands.append(
                CheatCommand(
                    id: identifier,
                    storageKey: "\(fileName)#\(title)",
                    title: title,
                    detail: detail,
                    command: command,
                    language: language,
                    // Command first, so forms focus a field that affects the
                    // normal copied value before description-only variables.
                    variables: CommandTemplate.variables(in: "\(command)\n\(detail)")
                )
            )
        }

        func finishDescriptionOnlySection() {
            defer {
                sectionTitle = nil
                descriptionLines = []
            }

            guard let title = sectionTitle else { return }
            let detail = descriptionLines
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !detail.isEmpty else { return }
            appendEntry(title: title, detail: detail, command: "", language: "")
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
                finishDescriptionOnlySection()
                sheetTitle = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                index += 1
                continue
            }

            if line.hasPrefix("## ") {
                finishDescriptionOnlySection()
                sectionTitle = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
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

                if let title = sectionTitle {
                    let command = codeLines.joined(separator: "\n")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !command.isEmpty {
                        let detail = descriptionLines
                            .joined(separator: " ")
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        appendEntry(
                            title: title,
                            detail: detail,
                            command: command,
                            language: language
                        )
                    } else {
                        finishDescriptionOnlySection()
                    }
                }

                sectionTitle = nil
                descriptionLines = []
                index += 1
                continue
            }

            if sectionTitle != nil, !line.trimmingCharacters(in: .whitespaces).isEmpty {
                descriptionLines.append(line.trimmingCharacters(in: .whitespaces))
            }
            index += 1
        }

        finishDescriptionOnlySection()

        return CheatSheet(
            id: fileName,
            title: sheetTitle,
            commands: commands,
            sourceURL: fileURL
        )
    }
}
