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
        var index = 0

        while index < lines.count {
            let line = lines[index]

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
                        commands.append(
                            CheatCommand(
                                id: identifier,
                                title: title,
                                detail: descriptionLines
                                    .joined(separator: " ")
                                    .trimmingCharacters(in: .whitespacesAndNewlines),
                                command: command,
                                language: language
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
