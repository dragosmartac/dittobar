import AppKit

enum DisplayPreferences {
    static let titleFontSizeKey = "display.titleFontSize"
    static let descriptionFontSizeKey = "display.descriptionFontSize"
    // Keep the persisted key unchanged so existing preferences survive the rename.
    static let payloadFontSizeKey = "display.commandFontSize"
    static let popoverWidthFractionKey = "display.popoverWidthFraction"

    static let defaultTitleFontSize = Double(NSFont.systemFontSize)
    static let defaultDescriptionFontSize = Double(NSFont.smallSystemFontSize)
    static let defaultPayloadFontSize = Double(NSFont.systemFontSize)
    static let defaultPopoverWidthFraction = 0.85

    static let titleFontSizeRange = 9.0...28.0
    static let descriptionFontSizeRange = 9.0...24.0
    static let payloadFontSizeRange = 9.0...28.0
    static let popoverWidthFractionRange = 0.5...0.95

    static func popoverWidthFraction(defaults: UserDefaults = .standard) -> Double {
        let storedValue = (defaults.object(forKey: popoverWidthFractionKey) as? NSNumber)?
            .doubleValue
        return min(
            max(storedValue ?? defaultPopoverWidthFraction, popoverWidthFractionRange.lowerBound),
            popoverWidthFractionRange.upperBound
        )
    }
}
