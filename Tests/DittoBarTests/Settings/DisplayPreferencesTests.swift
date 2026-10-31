import AppKit
import Testing
@testable import DittoBar

struct DisplayPreferencesTests {
    @Test func accentColourRoundTripsAsOpaqueSRGB() throws {
        let original = NSColor(srgbRed: 0.2, green: 0.4, blue: 0.8, alpha: 0.5)
        let saved = DisplayPreferences.encodeAccentColor(original)
        let restored = try #require(DisplayPreferences.accentColor(from: saved).usingColorSpace(.sRGB))
        #expect(abs(restored.redComponent - 0.2) < 0.0001)
        #expect(abs(restored.greenComponent - 0.4) < 0.0001)
        #expect(abs(restored.blueComponent - 0.8) < 0.0001)
        #expect(restored.alphaComponent == 1)
    }

    @Test func missingOrInvalidAccentColourUsesOrange() {
        for value in ["", "invalid", "1,0", "1,0,0,invalid", "1,,0,0", "2,0,0", "nan,0,0"] {
            #expect(DisplayPreferences.accentColor(from: value) == NSColor.systemOrange)
        }
    }

    @Test func sectionTitleDefaultIsWithinRange() {
        #expect(
            DisplayPreferences.sectionTitleFontSizeRange
                .contains(DisplayPreferences.defaultSectionTitleFontSize)
        )
    }

    @Test func noteDefaultIsWithinRange() {
        #expect(
            DisplayPreferences.noteFontSizeRange
                .contains(DisplayPreferences.defaultNoteFontSize)
        )
    }

    @Test func sectionTitleKeyIsDistinct() {
        let keys = [
            DisplayPreferences.titleFontSizeKey,
            DisplayPreferences.descriptionFontSizeKey,
            DisplayPreferences.noteFontSizeKey,
            DisplayPreferences.payloadFontSizeKey,
            DisplayPreferences.sectionTitleFontSizeKey
        ]
        #expect(Set(keys).count == keys.count)
    }
}
