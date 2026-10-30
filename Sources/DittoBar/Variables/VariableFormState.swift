import Foundation

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
