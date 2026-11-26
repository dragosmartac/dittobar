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

/// Each presented sheet retains its own fields while SwiftUI finishes dismissing it.
final class NewEntryFormState: ObservableObject, Identifiable {
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
    @Published var draft = NewEntryDraft(kind: .note, title: "", rawContent: "")
    @Published var errorMessage: String?

    init(sheetURL: URL, section: CheatSheetSection?) {
        self.sheetURL = sheetURL
        self.section = EntrySectionChoice(section)
    }
}
