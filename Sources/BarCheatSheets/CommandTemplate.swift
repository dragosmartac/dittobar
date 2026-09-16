import Foundation

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
        let range: NSRange
        let name: String
        let defaultValue: String
    }

    private static let expression = try! NSRegularExpression(
        pattern: #"\{\{\s*([A-Za-z0-9_][A-Za-z0-9_.\-]*)\s*(?:=([^{}]*))?\}\}"#
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
        let source = template as NSString
        var segments: [Segment] = []
        var location = 0

        for placeholder in placeholders(in: template) {
            if placeholder.range.location > location {
                let literal = source.substring(
                    with: NSRange(
                        location: location,
                        length: placeholder.range.location - location
                    )
                )
                segments.append(Segment(text: literal, variableName: nil))
            }

            let value = values[placeholder.name] ?? placeholder.defaultValue
            segments.append(Segment(text: value, variableName: placeholder.name))
            location = placeholder.range.location + placeholder.range.length
        }

        if location < source.length {
            let tail = source.substring(from: location)
            segments.append(Segment(text: tail, variableName: nil))
        }

        return segments
    }

    private static func placeholders(in template: String) -> [Placeholder] {
        let source = template as NSString
        let matches = expression.matches(
            in: template,
            range: NSRange(location: 0, length: source.length)
        )

        return matches.map { match in
            let defaultRange = match.range(at: 2)
            return Placeholder(
                range: match.range,
                name: source.substring(with: match.range(at: 1)),
                defaultValue: defaultRange.location == NSNotFound
                    ? ""
                    : source.substring(with: defaultRange)
            )
        }
    }
}
