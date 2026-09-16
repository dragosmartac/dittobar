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

/// The in-flight state of the variable form.
struct VariableFormState: Equatable {
    let commandID: String
    let storageKey: String
    let title: String
    let template: String
    let variables: [CommandVariable]
    var values: [String: String]

    var rendered: String {
        CommandTemplate.render(template, values: values)
    }

    var segments: [CommandTemplate.Segment] {
        CommandTemplate.segments(of: template, values: values)
    }

    var matchesDefaults: Bool {
        variables.allSatisfy { values[$0.name] == $0.defaultValue }
    }
}
