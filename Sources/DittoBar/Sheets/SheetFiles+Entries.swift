import Foundation

extension SheetFiles {
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
        _ draft: EntryDraft, into url: URL, section: EntrySectionChoice,
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
        case sheetChanged, looseMarkdown, moveIncomplete

        var errorDescription: String? {
            switch self {
            case .sheetChanged: "The sheet has changed. Reopen the entry to use its latest version."
            case .looseMarkdown: "This change would attach loose Markdown to an entry. Separate that text in your sheet editor, then try again."
            case .moveIncomplete: "The original entry is still in its sheet. Check the destination for a saved copy before retrying."
            }
        }
    }

    static func remove(_ entry: CheatSheetEntry, from sheet: CheatSheet) throws {
        _ = try replace(entry, in: sheet, with: nil)
    }

    /// Replace the entry at its original position. A nil draft removes it.
    static func replace(_ entry: CheatSheetEntry, in sheet: CheatSheet, with draft: EntryDraft?) throws -> Int {
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
        _ entry: CheatSheetEntry, in sheet: CheatSheet, with draft: EntryDraft?, bytes: inout Data
    ) throws -> Int {
        let fileText = try MarkdownFileText(bytes)
        let source = fileText.text
        let document = CheatSheetParser.parseDocument(source, fileURL: sheet.sourceURL, locating: entry)
        // An external edit can change which duplicate has the confirmed ID.
        guard document.sheet == sheet, let first = document.entrySourceRanges.first,
              let index = sheet.items.firstIndex(of: .entry(entry)) else { throw EntryChangeError.sheetChanged }
        var originalDraft = EntryDraft(entry: entry)
        if let draft {
            if draft == originalDraft { return index }
            originalDraft.title = draft.title
            if draft == originalDraft {
                let title = try draft.validatedTitle()
                let heading = source[first].prefix(while: { !$0.isNewline })
                bytes.replaceSubrange(fileText.byteRange(heading.startIndex..<heading.endIndex), with: "### \(title)".utf8)
                return index
            }
        }

        let markdown = try draft?.markdown()
        var replacement = ""
        if let markdown {
            replacement = markdown.replacingOccurrences(of: "\n", with: fileText.newline)
            // Keep the separator before the next heading or an intervening HTML comment.
            let original = source[first]
            if let last = original.lastIndex(where: { !$0.isNewline }) {
                replacement += original[original.index(after: last)...]
            }
        }
        for range in document.entrySourceRanges.reversed() {
            let text = range == first ? replacement : ""
            bytes.replaceSubrange(fileText.byteRange(range), with: text.utf8)
        }

        // After a closing fence the parser ignores loose prose and standalone code blocks.
        // Removing that boundary can attach them to a note. Check before writing either file.
        if draft == nil || draft?.kind == .note, let end = document.entrySourceRanges.last?.upperBound {
            let following = source[end...].drop(while: \.isNewline)
            if following.isEmpty || CheatSheetParser.startsHeading(following) { return index }
            var expected = sheet.items
            let editedItems = markdown.map { CheatSheetParser.parse($0, fileURL: sheet.sourceURL).items } ?? []
            expected.replaceSubrange(index...index, with: editedItems)
            let result = try CheatSheetParser.parse(MarkdownFileText(bytes).text, fileURL: sheet.sourceURL)
            // Removing a duplicate can renumber later row IDs. Compare the actual entry fields.
            guard result.items.elementsEqual(expected, by: { lhs, rhs in
                lhs.section == rhs.section
                    && lhs.entry.map(EntryDraft.init(entry:)) == rhs.entry.map(EntryDraft.init(entry:))
            }) else { throw EntryChangeError.looseMarkdown }
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
        let fileText = try MarkdownFileText(bytes)
        let source = fileText.text
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
        let newline = fileText.newline
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
        bytes.replaceSubrange(fileText.byteRange(position..<position), with: insertion.utf8)
        // A newly appended heading occupies the item immediately before the entry.
        if section == .newSection { return document.sheet.items.endIndex + 1 }
        return nextHeading.flatMap { document.sheet.items.firstIndex(of: .section($0.section)) }
            ?? document.sheet.items.endIndex
    }
}

/// Parser indices refer to decoded text. File edits use byte offsets including the optional UTF-8 BOM.
private struct MarkdownFileText {
    let text: String
    private let bomSize: Int

    init(_ bytes: Data) throws {
        bomSize = bytes.starts(with: [0xEF, 0xBB, 0xBF]) ? 3 : 0
        guard let text = String(bytes: bytes.dropFirst(bomSize), encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        self.text = text
    }

    var newline: String { text.first(where: \.isNewline).map(String.init) ?? "\n" }

    func byteRange(_ range: Range<String.Index>) -> Range<Int> {
        let start = bomSize + text.utf8.distance(from: text.startIndex, to: range.lowerBound)
        return start..<(start + text.utf8.distance(from: range.lowerBound, to: range.upperBound))
    }
}
