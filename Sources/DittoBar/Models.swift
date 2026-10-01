import Foundation

struct EntryMetadata: Equatable {
    let id: String
    /// Stable across reordering, so remembered variable values survive edits.
    let storageKey: String
    let title: String
    /// Optional visual group within a cheat-sheet page.
    let sectionTitle: String?
}

struct EntryVariable: Identifiable, Equatable {
    let name: String
    let defaultValue: String

    var id: String { name }
}

struct NoteEntry: Equatable {
    let metadata: EntryMetadata
    let rawContent: String
    let variables: [EntryVariable]
}

struct CommandEntry: Equatable {
    let metadata: EntryMetadata
    let rawDescription: String?
    /// May contain `{{name=default}}` placeholders.
    let rawCommand: String
    let language: String?
    let variables: [EntryVariable]
}

struct URLEntry: Equatable {
    let metadata: EntryMetadata
    let rawDescription: String?
    /// Kept as raw text because variables may make it an invalid URL until resolved.
    let rawURL: String
    let variables: [EntryVariable]
}

enum EntryTextForm: Equatable {
    case markdownStripped
    case resolved
}

enum EntryAction: Equatable {
    case copyTitle
    case copyCommand
    case copyNoteContent(EntryTextForm)
    case copyURL
    case copyDescription(EntryTextForm)
    case openURL

    var title: String {
        switch self {
        case .copyTitle:
            return "Copy Title"
        case .copyCommand:
            return "Copy Command"
        case .copyNoteContent(.markdownStripped):
            return "Copy Content"
        case .copyNoteContent(.resolved):
            return "Copy Content as Markdown"
        case .copyURL:
            return "Copy URL"
        case .copyDescription(.markdownStripped):
            return "Copy Description"
        case .copyDescription(.resolved):
            return "Copy Description as Markdown"
        case .openURL:
            return "Open URL"
        }
    }
}

struct EntryActions: Equatable {
    let primary: EntryAction
    let secondary: [EntryAction]

    var all: [EntryAction] { [primary] + secondary }
}

enum CheatSheetEntry: Identifiable, Equatable {
    case note(NoteEntry)
    case command(CommandEntry)
    case url(URLEntry)

    var metadata: EntryMetadata {
        switch self {
        case .note(let entry):
            return entry.metadata
        case .command(let entry):
            return entry.metadata
        case .url(let entry):
            return entry.metadata
        }
    }

    var id: String { metadata.id }
    var storageKey: String { metadata.storageKey }
    var title: String { metadata.title }
    var sectionTitle: String? { metadata.sectionTitle }

    var variables: [EntryVariable] {
        switch self {
        case .note(let entry):
            return entry.variables
        case .command(let entry):
            return entry.variables
        case .url(let entry):
            return entry.variables
        }
    }

    var hasVariables: Bool { !variables.isEmpty }

    var defaultValues: [String: String] {
        Dictionary(uniqueKeysWithValues: variables.map { ($0.name, $0.defaultValue) })
    }

    var actions: EntryActions {
        switch self {
        case .command(let entry):
            var secondary: [EntryAction] = [.copyTitle]
            if entry.rawDescription != nil {
                secondary.append(contentsOf: [
                    .copyDescription(.markdownStripped),
                    .copyDescription(.resolved)
                ])
            }
            return EntryActions(primary: .copyCommand, secondary: secondary)

        case .note:
            return EntryActions(
                primary: .copyNoteContent(.markdownStripped),
                secondary: [.copyTitle, .copyNoteContent(.resolved)]
            )

        case .url(let entry):
            var secondary: [EntryAction] = [.openURL, .copyTitle]
            if entry.rawDescription != nil {
                secondary.append(contentsOf: [
                    .copyDescription(.markdownStripped),
                    .copyDescription(.resolved)
                ])
            }
            return EntryActions(primary: .copyURL, secondary: secondary)
        }
    }
}

struct CheatSheetSection: Identifiable, Equatable {
    let id: String
    let title: String
    /// Position in the unfiltered entry list where this header appears.
    let entryOffset: Int
}

struct CheatSheet: Identifiable, Equatable {
    let id: String
    let title: String
    let entries: [CheatSheetEntry]
    let sections: [CheatSheetSection]
    let sourceURL: URL
}

enum CheatSheetRow: Identifiable, Equatable {
    case section(CheatSheetSection)
    case entry(CheatSheetEntry, visibleIndex: Int)

    var id: String {
        switch self {
        case .section(let section):
            return "section:\(section.id)"
        case .entry(let entry, _):
            return "entry:\(entry.id)"
        }
    }
}

/// The in-flight state of the variable form.
struct VariableFormState: Equatable {
    let entryID: String
    let storageKey: String
    let title: String
    let raw: String
    let textForm: EntryTextForm
    let action: EntryAction
    let variables: [EntryVariable]
    var values: [String: String]

    var output: String {
        let resolved = TextVariables.resolve(raw, values: values)
        return textForm == .markdownStripped ? MarkdownText.stripped(resolved) : resolved
    }

    var segments: [TextVariables.Segment] {
        TextVariables.segments(of: raw, values: values)
    }

    var matchesDefaults: Bool {
        variables.allSatisfy { values[$0.name] == $0.defaultValue }
    }
}
