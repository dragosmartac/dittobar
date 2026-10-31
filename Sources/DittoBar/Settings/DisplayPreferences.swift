import AppKit

enum DisplayPreferences {
    static let accentColorKey = "display.accentColor"

    static func accentColor(from value: String) -> NSColor {
        let parts = value.split(separator: ",", omittingEmptySubsequences: false)
        let components = parts.compactMap { Double($0) }
        guard parts.count == 3, components.count == 3,
              components.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
            return .systemOrange
        }
        return NSColor(srgbRed: components[0], green: components[1], blue: components[2], alpha: 1)
    }

    static func encodeAccentColor(_ color: NSColor) -> String {
        guard let rgb = color.usingColorSpace(.sRGB) else { return "" }
        return [rgb.redComponent, rgb.greenComponent, rgb.blueComponent]
            .map { String(Double(min(1, max(0, $0)))) }.joined(separator: ",")
    }

    static let sectionTitleFontSizeKey = "display.sectionTitleFontSize"
    static let titleFontSizeKey = "display.titleFontSize"
    static let descriptionFontSizeKey = "display.descriptionFontSize"
    static let noteFontSizeKey = "display.noteFontSize"
    // Keep the persisted key unchanged so existing preferences survive the rename.
    static let payloadFontSizeKey = "display.commandFontSize"
    // Preserve the existing saved width preference.
    static let panelWidthFractionKey = "display.popoverWidthFraction"
    static let textFontFamilyKey = "display.textFontFamily"
    static let codeFontFamilyKey = "display.codeFontFamily"

    static let defaultSectionTitleFontSize = Double(NSFont.systemFontSize)
    static let defaultTitleFontSize = Double(NSFont.systemFontSize)
    static let defaultDescriptionFontSize = Double(NSFont.smallSystemFontSize)
    static let defaultNoteFontSize = Double(NSFont.systemFontSize)
    static let defaultPayloadFontSize = Double(NSFont.systemFontSize)
    static let defaultPanelWidthFraction = 0.85

    static let sectionTitleFontSizeRange = 9.0...28.0
    static let titleFontSizeRange = 9.0...28.0
    static let descriptionFontSizeRange = 9.0...24.0
    static let noteFontSizeRange = 9.0...28.0
    static let payloadFontSizeRange = 9.0...28.0
    static let panelWidthFractionRange = 0.5...0.95

    static func panelWidthFraction(defaults: UserDefaults = .standard) -> Double {
        let storedValue = (defaults.object(forKey: panelWidthFractionKey) as? NSNumber)?
            .doubleValue
        return min(
            max(storedValue ?? defaultPanelWidthFraction, panelWidthFractionRange.lowerBound),
            panelWidthFractionRange.upperBound
        )
    }
}
