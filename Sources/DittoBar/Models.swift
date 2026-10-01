import Foundation

struct CommandVariable: Identifiable, Equatable {
    let name: String
    let defaultValue: String

    var id: String { name }
}

struct CheatCommand: Identifiable, Equatable {
    let id: String
    /// Stable across reordering, so remembered variable values survive edits.
    let storageKey: String
    let title: String
    /// Optional visual group within a cheat-sheet page.
    let sectionTitle: String?
    let rawDescription: String
    /// May contain `{{name=default}}` placeholders.
    let rawCommand: String
    let language: String
    let variables: [CommandVariable]

    var hasVariables: Bool { !variables.isEmpty }
    var isDescriptionOnly: Bool { rawCommand.isEmpty }
    var isLink: Bool { language.caseInsensitiveCompare("url") == .orderedSame }
    var rawCopyText: String { isDescriptionOnly ? rawDescription : rawCommand }

    // This is computed on each access. We might consider to change this functionality
    var defaultValues: [String: String] {
        Dictionary(uniqueKeysWithValues: variables.map { ($0.name, $0.defaultValue) })
    }
}

struct CheatSheetSection: Identifiable, Equatable {
    let id: String
    let title: String
    /// Position in the unfiltered command list where this header appears.
    let commandOffset: Int
}

struct CheatSheet: Identifiable, Equatable {
    let id: String
    let title: String
    let commands: [CheatCommand]
    let sections: [CheatSheetSection]
    let sourceURL: URL
}

enum CheatSheetRow: Identifiable, Equatable {
    case section(CheatSheetSection)
    case command(CheatCommand, visibleIndex: Int)

    var id: String {
        switch self {
        case .section(let section):
            return "section:\(section.id)"
        case .command(let command, _):
            return "command:\(command.id)"
        }
    }
}

enum CopyOutputFormat: Equatable {
    case resolvedCommand
    case markdownStrippedDescription
    case resolvedDescription
}

enum VariableFormAction: Equatable {
    case copy
    case openLink
}

/// The in-flight state of the variable form.
struct VariableFormState: Equatable {
    let commandID: String
    let storageKey: String
    let title: String
    let raw: String
    let outputFormat: CopyOutputFormat
    let action: VariableFormAction
    let variables: [CommandVariable]
    var values: [String: String]

    var output: String {
        let text = TextVariables.resolve(raw, values: values)
        return outputFormat == .markdownStrippedDescription ? MarkdownText.stripped(text) : text
    }

    var segments: [TextVariables.Segment] {
        TextVariables.segments(of: raw, values: values)
    }

    var matchesDefaults: Bool {
        variables.allSatisfy { values[$0.name] == $0.defaultValue }
    }
}
