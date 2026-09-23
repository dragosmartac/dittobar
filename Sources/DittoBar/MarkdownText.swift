import Foundation

enum MarkdownText {
    /// Returns the text a user sees after inline Markdown formatting is applied.
    static func plainText(_ source: String) -> String {
        guard let parsed = try? AttributedString(
            markdown: source,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) else {
            return source
        }
        return String(parsed.characters)
    }
}
