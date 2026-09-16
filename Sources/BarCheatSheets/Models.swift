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
    let detail: String
    /// The raw template; may contain `{{name=default}}` placeholders.
    let command: String
    let language: String
    let variables: [CommandVariable]

    var hasVariables: Bool { !variables.isEmpty }
    var isDescriptionOnly: Bool { command.isEmpty }
    var isLink: Bool { language.caseInsensitiveCompare("url") == .orderedSame }
    var copyTemplate: String { isDescriptionOnly ? detail : command }

    var defaultValues: [String: String] {
        Dictionary(uniqueKeysWithValues: variables.map { ($0.name, $0.defaultValue) })
    }
}

struct CheatSheet: Identifiable, Equatable {
    let id: String
    let title: String
    let commands: [CheatCommand]
    let sourceURL: URL
}

enum CopyOutputFormat: Equatable {
    case command
    case plainDescription
    case markdownDescription
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
    let template: String
    let outputFormat: CopyOutputFormat
    let action: VariableFormAction
    let variables: [CommandVariable]
    var values: [String: String]

    var rendered: String {
        let text = CommandTemplate.render(template, values: values)
        return outputFormat == .plainDescription ? MarkdownText.plainText(text) : text
    }

    var segments: [CommandTemplate.Segment] {
        CommandTemplate.segments(of: template, values: values)
    }

    var matchesDefaults: Bool {
        variables.allSatisfy { values[$0.name] == $0.defaultValue }
    }
}
