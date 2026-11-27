import Foundation

struct EntryDraft: Equatable {
    enum Kind: String {
        case note, command, url, file, directory
    }

    var kind: Kind
    var title: String
    /// Note body, command, URL, or path, according to the selected kind.
    var rawContent: String
    var rawDescription = ""
    var language = "sh"

    var variables: [EntryVariable] {
        let raw = kind == .note ? rawContent : rawDescription + "\n" + rawContent
        return TextVariables.variables(in: raw)
    }

    enum ValidationError: LocalizedError {
        case missingTitle, missingContent, multilineTitle, invalidLanguage
        case structuralLineInProse, fenceInContent

        var errorDescription: String? {
            switch self {
            case .missingTitle: "Enter a title."
            case .missingContent: "Enter content for this entry."
            case .multilineTitle: "Keep the title on one line."
            case .invalidLanguage: "Use a single-line command language other than url, file, or directory."
            case .structuralLineInProse: "Sheet headings, code fences, and HTML comment blocks cannot appear in a note or description."
            case .fenceInContent: "A line starting with three backticks would close the entry’s code block."
            }
        }
    }

    func validatedTitle() throws -> String {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw ValidationError.missingTitle }
        guard !title.contains(where: \.isNewline) else { throw ValidationError.multilineTitle }
        return title
    }

    func markdown() throws -> String {
        let title = try validatedTitle()
        guard !rawContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError.missingContent
        }

        // Emit LF even when a multiline field was pasted from a CRLF file.
        let prose = kind == .note ? rawContent : rawDescription
        let proseLines = prose.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        for line in proseLines {
            if CheatSheetParser.startsHeading(line)
                || line.hasPrefix("```") || line.drop(while: { $0.isWhitespace }).hasPrefix("<!--") {
                throw ValidationError.structuralLineInProse
            }
        }

        var blocks = ["### \(title)"]
        if !prose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            blocks.append(proseLines.joined(separator: "\n"))
        }
        guard kind != .note else { return blocks.joined(separator: "\n\n") }

        let content = rawContent.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        guard !content.contains(where: { $0.hasPrefix("```") }) else {
            throw ValidationError.fenceInContent
        }
        var fenceLabel = kind.rawValue
        if kind == .command {
            fenceLabel = language.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !fenceLabel.contains(where: \.isNewline),
                  !["url", "file", "directory"].contains(fenceLabel.lowercased()) else {
                throw ValidationError.invalidLanguage
            }
        }
        blocks.append("```" + fenceLabel + "\n" + content.joined(separator: "\n") + "\n```")
        return blocks.joined(separator: "\n\n")
    }
}

extension EntryDraft {
    init(entry: CheatSheetEntry) {
        switch entry {
        case .note(let note):
            self.init(kind: .note, title: entry.title, rawContent: note.rawContent)
        case .command(let command):
            self.init(kind: .command, title: entry.title, rawContent: command.rawCommand,
                      rawDescription: command.rawDescription ?? "", language: command.language ?? "")
        case .url(let url):
            self.init(kind: .url, title: entry.title, rawContent: url.rawURL, rawDescription: url.rawDescription ?? "")
        case .file(let path), .directory(let path):
            self.init(kind: entry.kind, title: entry.title, rawContent: path.rawPath, rawDescription: path.rawDescription ?? "")
        }
    }
}
