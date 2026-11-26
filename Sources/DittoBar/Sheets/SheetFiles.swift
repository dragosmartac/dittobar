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

    /// Returns the entry's position in the destination sheet, including section headings.
    @discardableResult
    static func save(
        _ draft: NewEntryDraft, into url: URL, section: EntrySectionChoice,
        newSectionName: String = "", editing original: SheetEntrySelection? = nil
    ) throws -> Int {
        guard isSheetFile(url) else { throw InsertionError.invalidSheet }
        if let original, original.sheet.sourceURL == url {
            let items = original.sheet.items
            guard let index = items.firstIndex(of: .entry(original.entry)) else { throw EntryChangeError.sheetChanged }
            let oldSection = items[..<index].last(where: { $0.section != nil })?.section
            if section == EntrySectionChoice(oldSection) {
                return try replace(original.entry, in: original.sheet, with: draft)
            }
        }

        var markdown = try draft.markdown()
        if section == .newSection {
            let name = newSectionName.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !name.contains(where: \.isNewline) else { throw InsertionError.invalidSectionName }
            markdown = "## \(name)\n\n" + markdown
        }

        let sourceURL = original?.sheet.sourceURL ?? url
        return try updateFiles(at: sourceURL, and: url) { sourceFile, destinationFile in
            var sourceBytes = try Data(contentsOf: sourceFile)
            if let original {
                _ = try replace(original.entry, in: original.sheet, with: nil, bytes: &sourceBytes)
            }
            if sourceFile == destinationFile {
                let index = try insertMarkdown(markdown, into: &sourceBytes, sheetURL: url, section: section)
                try sourceBytes.write(to: sourceFile, options: .atomic)
                return index
            }

            let previousDestination = try Data(contentsOf: destinationFile)
            var destinationBytes = previousDestination
            let index = try insertMarkdown(markdown, into: &destinationBytes, sheetURL: url, section: section)
            // Write the destination first so an interrupted move always leaves a copy.
            try destinationBytes.write(to: destinationFile, options: .atomic)
            do {
                try sourceBytes.write(to: sourceFile, options: .atomic)
            } catch {
                do { try previousDestination.write(to: destinationFile, options: .atomic) }
                catch { throw EntryChangeError.moveIncomplete }
                throw error
            }
            return index
        }
    }

    enum EntryChangeError: LocalizedError {
        case sheetChanged, moveIncomplete

        var errorDescription: String? {
            switch self {
            case .sheetChanged: "The sheet has changed. Reopen the entry to use its latest version."
            case .moveIncomplete: "The original entry is still in its sheet. Check the destination for a saved copy before retrying."
            }
        }
    }

    static func remove(_ entry: CheatSheetEntry, from sheet: CheatSheet) throws {
        _ = try replace(entry, in: sheet, with: nil)
    }

    /// Replace the entry at its original position. A nil draft removes it.
    static func replace(_ entry: CheatSheetEntry, in sheet: CheatSheet, with draft: NewEntryDraft?) throws -> Int {
        guard isSheetFile(sheet.sourceURL) else { throw EntryChangeError.sheetChanged }
        return try updateFiles(at: sheet.sourceURL, and: sheet.sourceURL) { file, _ in
            let originalBytes = try Data(contentsOf: file)
            var bytes = originalBytes
            let index = try replace(entry, in: sheet, with: draft, bytes: &bytes)
            if bytes != originalBytes { try bytes.write(to: file, options: .atomic) }
            return index
        }
    }

    private static func replace(
        _ entry: CheatSheetEntry, in sheet: CheatSheet, with draft: NewEntryDraft?, bytes: inout Data
    ) throws -> Int {
        let bomSize = bytes.starts(with: [0xEF, 0xBB, 0xBF]) ? 3 : 0
        guard let source = String(bytes: bytes.dropFirst(bomSize), encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        let document = CheatSheetParser.parseDocument(source, fileURL: sheet.sourceURL, locating: entry)
        // An external edit can change which duplicate has the confirmed ID.
        guard document.sheet == sheet, let first = document.entrySourceRanges.first,
              let index = sheet.items.firstIndex(of: .entry(entry)) else { throw EntryChangeError.sheetChanged }
        if draft == NewEntryDraft(entry: entry) { return index }

        var replacement = ""
        if let draft {
            let newline = source.first(where: \.isNewline).map(String.init) ?? "\n"
            replacement = try draft.markdown().replacingOccurrences(of: "\n", with: newline)
            // Keep the separator before the next heading or an intervening HTML comment.
            let original = source[first]
            if let last = original.lastIndex(where: { !$0.isNewline }) {
                replacement += original[original.index(after: last)...]
            }
        }
        for range in document.entrySourceRanges.reversed() {
            let start = source.utf8.distance(from: source.startIndex, to: range.lowerBound)
            let end = source.utf8.distance(from: source.startIndex, to: range.upperBound)
            let text = range == first ? replacement : ""
            bytes.replaceSubrange((bomSize + start)..<(bomSize + end), with: text.utf8)
        }
        return index
    }

    // Keep cooperating writers out between reading the latest file and replacing it.
    private static func updateFiles<T>(
        at sourceURL: URL, and destinationURL: URL, _ update: (URL, URL) throws -> T
    ) throws -> T {
        var coordinationError: NSError?
        var result: Result<T, Error>?
        // Aliases with different spelling can point to one file on a case-insensitive volume.
        func target(of url: URL) throws -> URL {
            let resolved = url.resolvingSymlinksInPath().standardizedFileURL
            let path = try resolved.resourceValues(forKeys: [.canonicalPathKey]).canonicalPath
            return path.map { URL(fileURLWithPath: $0) } ?? resolved
        }
        let source = try target(of: sourceURL)
        let destination = sourceURL == destinationURL ? source : try target(of: destinationURL)
        let coordinator = NSFileCoordinator()
        if source == destination {
            coordinator.coordinate(writingItemAt: source, options: .forMerging, error: &coordinationError) { file in
                result = Result { try update(file, file) }
            }
        } else {
            coordinator.coordinate(writingItemAt: source, options: .forMerging,
                                   writingItemAt: destination, options: .forMerging, error: &coordinationError) { from, to in
                result = Result { try update(from, to) }
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw CocoaError(.fileWriteUnknown) }
        return try result.get()
    }

    private static func insertMarkdown(
        _ markdown: String, into bytes: inout Data, sheetURL: URL, section: EntrySectionChoice
    ) throws -> Int {
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
