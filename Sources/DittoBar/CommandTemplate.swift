/// Placeholders are written inline in the Markdown code block as
/// `{{name}}` or `{{name=default value}}`. Repeating a name reuses the
/// same field, so one edit updates every occurrence in the command.
enum CommandTemplate {
    /// A rendered run of text, tagged with the variable it came from.
    struct Segment: Equatable {
        let text: String
        let variableName: String?

        var isVariable: Bool { variableName != nil }
    }

    private struct Placeholder {
        let range: Range<String.Index>
        let name: String
        let defaultValue: String
    }

    private static let expression = try! Regex(
        #"\{\{\s*([A-Za-z0-9_][A-Za-z0-9_.-]*)\s*(?:=([^{}]*))?\}\}"#
    )

    /// The distinct variables of a template, in the order they first appear.
    static func variables(in template: String) -> [CommandVariable] {
        var ordered: [CommandVariable] = []
        var indexByName: [String: Int] = [:]

        for placeholder in placeholders(in: template) {
            if let existing = indexByName[placeholder.name] {
                // A later occurrence may supply the default the first one omitted.
                if ordered[existing].defaultValue.isEmpty {
                    ordered[existing] = CommandVariable(
                        name: placeholder.name,
                        defaultValue: placeholder.defaultValue
                    )
                }
                continue
            }

            indexByName[placeholder.name] = ordered.count
            ordered.append(
                CommandVariable(name: placeholder.name, defaultValue: placeholder.defaultValue)
            )
        }

        return ordered
    }

    static func render(_ template: String, values: [String: String]) -> String {
        segments(of: template, values: values).map(\.text).joined()
    }

    static func segments(of template: String, values: [String: String]) -> [Segment] {
        var segments: [Segment] = []
        var location = template.startIndex

        for placeholder in placeholders(in: template) {
            if placeholder.range.lowerBound > location {
                let literal = String(template[location..<placeholder.range.lowerBound])
                segments.append(Segment(text: literal, variableName: nil))
            }

            let value = values[placeholder.name] ?? placeholder.defaultValue
            segments.append(Segment(text: value, variableName: placeholder.name))
            location = placeholder.range.upperBound
        }

        if location < template.endIndex {
            let tail = String(template[location...])
            segments.append(Segment(text: tail, variableName: nil))
        }

        return segments
    }

    private static func placeholders(in template: String) -> [Placeholder] {
        template.matches(of: expression).map { match in
            Placeholder(
                range: match.range,
                name: String(match.output[1].substring!),
                defaultValue: match.output[2].substring.map(String.init) ?? ""
            )
        }
    }
}
