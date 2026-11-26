import Foundation

/// File operations only; the store owns folder selection and published state.
enum SheetFiles {
    static let instructionsFileName = "instructions.md"

    enum CreationError: LocalizedError {
        case emptyName
        case invalidName
        case reservedName
        case alreadyExists(String)
        case writeFailed(Error)

        var errorDescription: String? {
            switch self {
            case .emptyName: "Enter a name for the new cheat sheet."
            case .invalidName: "Cheat sheet names cannot contain a slash (/)."
            case .reservedName: "The name \"instructions.md\" is reserved for folder instructions."
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
            .filter { isSheetFile($0) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .compactMap { url in
                guard let source = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                return CheatSheetParser.parse(source, fileURL: url)
            }

    }

    private static func isSheetFile(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "md"
            && url.lastPathComponent.lowercased() != instructionsFileName
    }

    enum InsertionError: LocalizedError {
        case invalidSheet, missingSection, invalidSectionName, unclosedBlock

        var errorDescription: String? {
            switch self {
            case .invalidSheet: "Choose a cheat sheet Markdown file."
            case .invalidSectionName: "Enter a section name on one line."
            case .missingSection: "The selected section has changed. Choose a destination again."
            case .unclosedBlock: "Close the unfinished code block or HTML comment at the end of the sheet before adding an entry."
            }
        }
    }

    /// Returns the new item's position in the saved sheet, including section headings.
    @discardableResult
    static func insert(
        _ draft: NewEntryDraft, into url: URL, section: EntrySectionChoice, newSectionName: String = ""
    ) throws -> Int {
        guard isSheetFile(url) else { throw InsertionError.invalidSheet }
        var markdown = try draft.markdown()
        if section == .newSection {
            let name = newSectionName.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !name.contains(where: \.isNewline) else { throw InsertionError.invalidSectionName }
            markdown = "## \(name)\n\n" + markdown
        }

        return try updateFile(at: url) { file in
            try insertMarkdown(markdown, into: file, sheetURL: url, section: section)
        }
    }

    enum RemovalError: LocalizedError {
        case sheetChanged

        var errorDescription: String? {
            "The sheet has changed. Select the entry again before removing it."
        }
    }

    static func remove(_ entry: CheatSheetEntry, from sheet: CheatSheet) throws {
        guard isSheetFile(sheet.sourceURL) else { throw RemovalError.sheetChanged }
        try updateFile(at: sheet.sourceURL) { file in
            var bytes = try Data(contentsOf: file)
            let bomSize = bytes.starts(with: [0xEF, 0xBB, 0xBF]) ? 3 : 0
            guard let source = String(bytes: bytes.dropFirst(bomSize), encoding: .utf8) else {
                throw CocoaError(.fileReadInapplicableStringEncoding)
            }
            let document = CheatSheetParser.parseDocument(source, fileURL: sheet.sourceURL, locating: entry)
            // Entry IDs include their position. An external edit could move an identically
            // titled entry into that position while the confirmation is open.
            guard document.sheet == sheet, !document.entrySourceRanges.isEmpty else { throw RemovalError.sheetChanged }
            for range in document.entrySourceRanges.reversed() {
                let start = source.utf8.distance(from: source.startIndex, to: range.lowerBound)
                let end = source.utf8.distance(from: source.startIndex, to: range.upperBound)
                bytes.removeSubrange((bomSize + start)..<(bomSize + end))
            }
            try bytes.write(to: file, options: .atomic)
        }
    }

    // Keep cooperating writers out between reading the latest file and replacing it.
    private static func updateFile<T>(at url: URL, _ update: (URL) throws -> T) throws -> T {
        var coordinationError: NSError?
        var result: Result<T, Error>?
        // Replace the target of a symlink while retaining the sheet name used for section IDs.
        let target = url.resolvingSymlinksInPath()
        NSFileCoordinator().coordinate(writingItemAt: target, options: .forMerging, error: &coordinationError) { file in
            result = Result { try update(file) }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw CocoaError(.fileWriteUnknown) }
        return try result.get()
    }

    private static func insertMarkdown(
        _ markdown: String, into file: URL, sheetURL: URL, section: EntrySectionChoice
    ) throws -> Int {
        var bytes = try Data(contentsOf: file)
        // Keep the original UTF-8 bytes, including a byte order mark when present.
        let bomSize = bytes.starts(with: [0xEF, 0xBB, 0xBF]) ? 3 : 0
        guard let source = String(bytes: bytes.dropFirst(bomSize), encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        let document = CheatSheetParser.parseDocument(source, fileURL: sheetURL)
        let headings = document.sectionHeadings
        let nextHeading: (section: CheatSheetSection, start: String.Index)?
        switch section {
        case .existing(let existing):
            guard let index = headings.firstIndex(where: { $0.section == existing }) else {
                throw InsertionError.missingSection
            }
            nextHeading = headings.dropFirst(index + 1).first
        case .newSection:
            nextHeading = nil
        case .unsectioned:
            nextHeading = headings.first
        }
        guard nextHeading != nil || !document.endsInsideBlock else {
            throw InsertionError.unclosedBlock
        }

        let position = nextHeading?.start ?? source.endIndex
        let preceding = source[..<position]
        let newline = source.first(where: \.isNewline).map(String.init) ?? "\n"
        var insertion = ""
        if let last = preceding.last {
            if !last.isNewline {
                insertion = newline + newline
            } else if preceding.dropLast().last?.isNewline == false {
                insertion = newline
            }
        }
        insertion += markdown.replacingOccurrences(of: "\n", with: newline)
        if nextHeading != nil {
            insertion += newline + newline
        } else if source.isEmpty || source.last?.isNewline == true {
            insertion += newline
        }
        bytes.insert(contentsOf: insertion.utf8, at: bomSize + preceding.utf8.count)
        try bytes.write(to: file, options: .atomic)
        // A newly appended heading occupies the item immediately before the entry.
        if section == .newSection { return document.sheet.items.endIndex + 1 }
        return nextHeading.flatMap { document.sheet.items.firstIndex(of: .section($0.section)) }
            ?? document.sheet.items.endIndex
    }

    /// Exclusive creation also protects a file added after the settings view checks for it.
    @discardableResult
    static func createInstructionsIfNeeded(in folderURL: URL) throws -> URL {
        let url = folderURL.appendingPathComponent(instructionsFileName)
        do {
            try Data(StarterContent.instructionsFile.utf8).write(to: url, options: .withoutOverwriting)
        } catch CocoaError.fileWriteFileExists {
            // Existing instructions belong to the user; keep them unchanged.
        }
        return url
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
        guard isSheetFile(fileURL) else { throw CreationError.reservedName }
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
        )) ?? []).contains { isSheetFile($0) }

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
