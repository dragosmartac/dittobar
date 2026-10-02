import Testing
@testable import DittoBar

struct DisplayPreferencesTests {
    @Test func sectionTitleDefaultIsWithinRange() {
        #expect(
            DisplayPreferences.sectionTitleFontSizeRange
                .contains(DisplayPreferences.defaultSectionTitleFontSize)
        )
    }

    @Test func sectionTitleKeyIsDistinct() {
        let keys = [
            DisplayPreferences.titleFontSizeKey,
            DisplayPreferences.descriptionFontSizeKey,
            DisplayPreferences.payloadFontSizeKey,
            DisplayPreferences.sectionTitleFontSizeKey
        ]
        #expect(Set(keys).count == keys.count)
    }
}
