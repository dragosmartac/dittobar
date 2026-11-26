import Combine
import Foundation

/// Each presented sheet retains its own fields while SwiftUI finishes dismissing it.
final class NewEntryFormState: ObservableObject, Identifiable {
    @Published var sheetURL: URL {
        didSet {
            if oldValue != sheetURL { section = nil }
        }
    }
    @Published var section: CheatSheetSection?
    @Published var draft = NewEntryDraft(kind: .note, title: "", rawContent: "")
    @Published var errorMessage: String?

    init(sheetURL: URL, section: CheatSheetSection?) {
        self.sheetURL = sheetURL
        self.section = section
    }
}
