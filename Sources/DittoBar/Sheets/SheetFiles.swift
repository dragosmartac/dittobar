import Foundation

/// File operations only; the store owns folder selection and published state.
enum SheetFiles {
    enum CreationError: LocalizedError {
        case emptyName
        case invalidName
        case alreadyExists(String)
        case writeFailed(Error)

        var errorDescription: String? {
            switch self {
            case .emptyName: "Enter a name for the new cheat sheet."
            case .invalidName: "Cheat sheet names cannot contain a slash (/)."
            case .alreadyExists(let name): "A cheat sheet named \"\(name)\" already exists."
            case .writeFailed(let error): "The new cheat sheet could not be created: \(error.localizedDescription)"
            }
        }
    }

    static func load(from folderURL: URL, fileManager: FileManager = .default) -> [CheatSheet] {
        let urls = (try? fileManager.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        return urls
            .filter { $0.pathExtension.lowercased() == "md" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .compactMap { url in
                guard let source = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                return CheatSheetParser.parse(source, fileURL: url)
            }

    }

    static func create(
        named proposedName: String,
        in folderURL: URL,
        includeInstructions: Bool,
        fileManager: FileManager = .default
    ) throws -> URL {
        var name = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.lowercased().hasSuffix(".md") {
            name = String(name.dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !name.isEmpty else { throw CreationError.emptyName }
        guard !name.contains("/") else { throw CreationError.invalidName }
        let fileURL = folderURL.appendingPathComponent(name).appendingPathExtension("md")
        guard !fileManager.fileExists(atPath: fileURL.path) else {
            throw CreationError.alreadyExists(name)
        }
        let template = StarterContent.newSheet(named: name, includeInstructions: includeInstructions)
        do {
            try template.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            throw CreationError.writeFailed(error)
        }
        return fileURL
    }

    static func createInitialFilesIfNeeded(in folderURL: URL, fileManager: FileManager = .default) {
        try? fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let hasMarkdown = ((try? fileManager.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: nil
        )) ?? []).contains { $0.pathExtension.lowercased() == "md" }

        guard !hasMarkdown else { return }

        try? StarterContent.vimSheet.write(
            to: folderURL.appendingPathComponent("vim.md"),
            atomically: true,
            encoding: .utf8
        )

        try? StarterContent.gitSheet.write(
            to: folderURL.appendingPathComponent("git.md"),
            atomically: true,
            encoding: .utf8
        )
    }
}
