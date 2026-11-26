import AppKit
import Testing
@testable import DittoBar

struct EntryTextStyleTests {
    @MainActor
    @Test(arguments: ["", "Helvetica Neue"])
    func markdownRendersBoldItalic(textFamily: String) throws {
        let fonts = EntryFonts(textFamily: textFamily)
        let source = "plain *italic* **bold** ***both*** ___also___"
        let rendered = EntryTextStyle.markdownRenderedDescription(
            TextVariables.segments(of: source, values: [:]), size: 14, fonts: fonts
        )
        #expect(rendered.string == "plain italic bold both also")
        let manager = NSFontManager.shared
        let regularWeight = manager.weight(of: fonts.text(size: 14))
        for (word, bold, italic) in [
            ("plain", false, false), ("italic", false, true), ("bold", true, false),
            ("both", true, true), ("also", true, true)
        ] {
            let range = (rendered.string as NSString).range(of: word)
            try #require(range.location != NSNotFound)
            let font = try #require(
                rendered.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
            )
            #expect(font.fontDescriptor.symbolicTraits.contains(.italic) == italic)
            #expect((manager.weight(of: font) > regularWeight) == bold)
        }
    }

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
