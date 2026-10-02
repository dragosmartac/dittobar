import Foundation

enum CheatSheetSearch {
    /// Search filtering contract:
    /// - An empty query returns every item.
    /// - Matching an entry includes that entry and its section.
    /// - Matching a section includes that section and its entries.
    /// - A matching empty section remains included.
    /// - No matches returns an empty array.
    static func filteredItems(
        in sheet: CheatSheet,
        matching query: String,
        valuesForEntry: (CheatSheetEntry) -> [String: String]
    ) -> [CheatSheetItem] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return sheet.items }

        return groups(in: sheet.items).flatMap { group -> [CheatSheetItem] in
            let sectionMatches = group.section?.title
                .localizedCaseInsensitiveContains(trimmedQuery) == true
            let matchingEntries = sectionMatches
                ? group.entries
                : group.entries.filter { entry in
                    matches(entry, query: trimmedQuery, valuesForEntry: valuesForEntry)
                }

            guard sectionMatches || !matchingEntries.isEmpty else { return [] }

            var items: [CheatSheetItem] = []
            if let section = group.section {
                items.append(.section(section))
            }
            items.append(contentsOf: matchingEntries.map(CheatSheetItem.entry))
            return items
        }
    }

    private struct ItemGroup {
        let section: CheatSheetSection?
        var entries: [CheatSheetEntry]
    }

    private static func groups(in items: [CheatSheetItem]) -> [ItemGroup] {
        var groups: [ItemGroup] = []
        var current = ItemGroup(section: nil, entries: [])

        for item in items {
            switch item {
            case .section(let section):
                if current.section != nil || !current.entries.isEmpty {
                    groups.append(current)
                }
                current = ItemGroup(section: section, entries: [])
            case .entry(let entry):
                current.entries.append(entry)
            }
        }

        if current.section != nil || !current.entries.isEmpty {
            groups.append(current)
        }
        return groups
    }

    private static func matches(
        _ entry: CheatSheetEntry,
        query: String,
        valuesForEntry: (CheatSheetEntry) -> [String: String]
    ) -> Bool {
        if entry.title.localizedCaseInsensitiveContains(query) {
            return true
        }

        let values = valuesForEntry(entry)
        return rawTexts(for: entry).contains { raw in
            let resolved = TextVariables.resolve(raw, values: values)
            return raw.localizedCaseInsensitiveContains(query)
                || resolved.localizedCaseInsensitiveContains(query)
                || MarkdownText.stripped(resolved).localizedCaseInsensitiveContains(query)
        }
    }

    private static func rawTexts(for entry: CheatSheetEntry) -> [String] {
        switch entry {
        case .note(let note):
            return [note.rawContent]
        case .command(let command):
            return [command.rawDescription, command.rawCommand].compactMap { $0 }
        case .url(let url):
            return [url.rawDescription, url.rawURL].compactMap { $0 }
        }
    }
}
