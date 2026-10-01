/// Placeholders are written inline in an entry's raw text as
/// `{{name}}` or `{{name=default value}}`. Repeating a name reuses the
/// same field, so one edit updates every occurrence in the text.
enum TextVariables {
    /// A resolved run of text, tagged with the variable it came from.
    struct Segment: Equatable {
        let text: String
        let variableName: String?

        var isVariable: Bool { variableName != nil }
    }

    struct Placeholder {
        let range: Range<String.Index>
        let name: String
        let defaultValue: String
    }

    private static let expression = try! Regex(
        #"\{\{\s*([A-Za-z0-9_][A-Za-z0-9_.-]*)\s*(?:=([^{}]*))?\}\}"#
    )

    /// The distinct variables of raw text, in the order they first appear.
    static func variables(in raw: String) -> [EntryVariable] {
        var ordered: [EntryVariable] = []
        var indexByName: [String: Int] = [:]

        for placeholder in placeholders(in: raw) {
            if let existing = indexByName[placeholder.name] {
                // Even though we saw the variable before, this might be the first time
                // we set the default value for it.
                if ordered[existing].defaultValue.isEmpty {
                    ordered[existing] = EntryVariable(
                        name: placeholder.name,
                        defaultValue: placeholder.defaultValue
                    )
                }
                continue
            }

            indexByName[placeholder.name] = ordered.count
            ordered.append(
                EntryVariable(name: placeholder.name, defaultValue: placeholder.defaultValue)
            )
        }

        return ordered
    }

    static func resolve(_ raw: String, values: [String: String]) -> String {
        segments(of: raw, values: values).map(\.text).joined()
    }

    static func segments(of raw: String, values: [String: String]) -> [Segment] {
        var segments: [Segment] = []
        var location = raw.startIndex

        for placeholder in placeholders(in: raw) {
            if placeholder.range.lowerBound > location {
                let literal = String(raw[location..<placeholder.range.lowerBound])
                segments.append(Segment(text: literal, variableName: nil))
            }

            let value = values[placeholder.name] ?? placeholder.defaultValue
            segments.append(Segment(text: value, variableName: placeholder.name))
            location = placeholder.range.upperBound
        }

        if location < raw.endIndex {
            let tail = String(raw[location...])
            segments.append(Segment(text: tail, variableName: nil))
        }

        return segments
    }

    static func placeholders(in raw: String) -> [Placeholder] {
        raw.matches(of: expression).map { match in
            Placeholder(
                range: match.range,
                name: String(match.output[1].substring!),
                defaultValue: match.output[2].substring.map(String.init) ?? ""
            )
        }
    }
}
