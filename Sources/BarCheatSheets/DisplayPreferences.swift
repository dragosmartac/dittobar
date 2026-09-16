import AppKit

enum DisplayPreferences {
    static let titleFontSizeKey = "display.titleFontSize"
    static let descriptionFontSizeKey = "display.descriptionFontSize"
    static let commandFontSizeKey = "display.commandFontSize"

    static let defaultTitleFontSize = Double(NSFont.systemFontSize)
    static let defaultDescriptionFontSize = Double(NSFont.smallSystemFontSize)
    static let defaultCommandFontSize = Double(NSFont.systemFontSize)

    static let titleFontSizeRange = 9.0...28.0
    static let descriptionFontSizeRange = 9.0...24.0
    static let commandFontSizeRange = 9.0...28.0
}
