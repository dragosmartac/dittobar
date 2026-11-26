import Combine
import Foundation

enum EntrySectionChoice: Hashable {
    case unsectioned
    case existing(CheatSheetSection)
    case newSection

    init(_ section: CheatSheetSection?) {
        self = section.map(Self.existing) ?? .unsectioned
    }
}

/// Capture the sheet at the time of selection so a later reload cannot retarget an edit or removal.
struct SheetEntrySelection: Identifiable {
    let id = UUID()
    let entry: CheatSheetEntry
    let sheet: CheatSheet
}

/// Each presented sheet retains its own fields while SwiftUI finishes dismissing it.
final class EntryFormState: ObservableObject, Identifiable {
    let original: SheetEntrySelection?
    @Published var sheetURL: URL {
        didSet {
            if oldValue != sheetURL {
                section = .unsectioned
                newSectionName = ""
            }
        }
    }
    @Published var section: EntrySectionChoice
    @Published var newSectionName = ""
    @Published var draft = EntryDraft(kind: .note, title: "", rawContent: "")
    @Published var isMarkdownHelpPresented = false
    @Published var errorMessage: String?

    init(sheet: CheatSheet, section: CheatSheetSection?, editing entry: CheatSheetEntry? = nil) {
        original = entry.map { SheetEntrySelection(entry: $0, sheet: sheet) }
        self.sheetURL = sheet.sourceURL
        self.section = EntrySectionChoice(section)
        if let entry { draft = EntryDraft(entry: entry) }
    }
}
