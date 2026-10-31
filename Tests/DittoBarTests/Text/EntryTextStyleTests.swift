import AppKit
import Testing
@testable import DittoBar

struct EntryTextStyleTests {
    @Test func payloadKeepsVariableTintOverSyntaxColors() {
        let segments = [
            TextVariables.Segment(text: "SELECT * FROM ", variableName: nil),
            TextVariables.Segment(text: "select", variableName: "table")
        ]
        let payload = EntryTextStyle.payload(
            segments,
            language: "sql",
            size: 12,
            fonts: EntryFonts(textFamily: "", codeFamily: "")
        )

        let keywordColor = payload.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        let variableColor = payload.attribute(.foregroundColor, at: 14, effectiveRange: nil) as? NSColor
        #expect(keywordColor == .systemPink)
        #expect(variableColor == .dittoAccent)
    }
}
