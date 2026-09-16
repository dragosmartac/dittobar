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
                sheetTitle = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                index += 1
                continue
            }

            if line.hasPrefix("## ") {
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
                        let identifier = "\(fileName):\(commands.count):\(title)"
                        let detail = descriptionLines
                            .joined(separator: " ")
                            .trimmingCharacters(in: .whitespacesAndNewlines)

                        commands.append(
                            CheatCommand(
                                id: identifier,
                                storageKey: "\(fileName)#\(title)",
                                title: title,
                                detail: detail,
                                command: command,
                                language: language,
                                // Descriptions take variables too, sharing a
                                // field with the command when the name matches.
                                // Command first, so the form focuses a field
                                // that actually affects what gets copied.
                                variables: CommandTemplate.variables(in: "\(command)\n\(detail)")
                            )
                        )
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

        return CheatSheet(
            id: fileName,
            title: sheetTitle,
            commands: commands,
            sourceURL: fileURL
        )
    }
}
