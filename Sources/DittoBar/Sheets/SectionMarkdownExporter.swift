import Foundation

enum SectionMarkdownExporter {
    /// The section and its visible entries in cheat-sheet Markdown, with
    /// each text resolved. URLs become bare lines, which most Markdown
    /// renderers turn into links, rather than `url` fences. Paths keep
    /// their `file` fences, since no renderer would link a bare path.
    static func markdown(
        for section: CheatSheetSection,
        entries: [CheatSheetEntry],
        values: (CheatSheetEntry) -> [String: String]
    ) -> String {
        let blocks = entries.map { entry -> String in
            var parts = ["### \(entry.title)"]
            switch entry {
            case .note(let note):
                parts.append(TextVariables.resolve(note.rawContent, values: values(entry)))
            case .command(let command):
                if let rawDescription = command.rawDescription {
                    parts.append(TextVariables.resolve(rawDescription, values: values(entry)))
                }
                parts.append(Self.fenced(
                    TextVariables.resolve(command.rawCommand, values: values(entry)),
                    language: command.language
                ))
            case .url(let url):
                if let rawDescription = url.rawDescription {
                    parts.append(TextVariables.resolve(rawDescription, values: values(entry)))
                }
                parts.append(TextVariables.resolve(url.rawURL, values: values(entry)))
            case .file(let file):
                if let rawDescription = file.rawDescription {
                    parts.append(TextVariables.resolve(rawDescription, values: values(entry)))
                }
                parts.append(Self.fenced(
                    TextVariables.resolve(file.rawPath, values: values(entry)),
                    language: "file"
                ))
            }
            return parts
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .joined(separator: "\n\n")
        }
        return (["## \(section.title)"] + blocks).joined(separator: "\n\n")
    }

    /// Uses a fence longer than any backtick run in the code.
    private static func fenced(_ code: String, language: String?) -> String {
        var fence = "```"
        while code.contains(fence) {
            fence += "`"
        }
        let trimmed = code.trimmingCharacters(in: .newlines)
        return "\(fence)\(language ?? "")\n\(trimmed)\n\(fence)"
    }
}
