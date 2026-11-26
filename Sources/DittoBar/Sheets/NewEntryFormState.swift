import Foundation

struct NewEntryFormState {
    var sheetURL: URL {
        didSet {
            if oldValue != sheetURL { section = nil }
        }
    }
    var section: CheatSheetSection?
    var draft = NewEntryDraft(kind: .note, title: "", rawContent: "")
    var errorMessage: String?
}
