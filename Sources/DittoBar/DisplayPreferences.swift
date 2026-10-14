import AppKit

enum DisplayPreferences {
    static let sectionTitleFontSizeKey = "display.sectionTitleFontSize"
    static let titleFontSizeKey = "display.titleFontSize"
    static let descriptionFontSizeKey = "display.descriptionFontSize"
    static let noteFontSizeKey = "display.noteFontSize"
    // Keep the persisted key unchanged so existing preferences survive the rename.
    static let payloadFontSizeKey = "display.commandFontSize"
    static let popoverWidthFractionKey = "display.popoverWidthFraction"
    static let textFontFamilyKey = "display.textFontFamily"
    static let codeFontFamilyKey = "display.codeFontFamily"

    static let defaultSectionTitleFontSize = Double(NSFont.systemFontSize)
    static let defaultTitleFontSize = Double(NSFont.systemFontSize)
    static let defaultDescriptionFontSize = Double(NSFont.smallSystemFontSize)
    static let defaultNoteFontSize = Double(NSFont.systemFontSize)
    static let defaultPayloadFontSize = Double(NSFont.systemFontSize)
    static let defaultPopoverWidthFraction = 0.85

    static let sectionTitleFontSizeRange = 9.0...28.0
    static let titleFontSizeRange = 9.0...28.0
    static let descriptionFontSizeRange = 9.0...24.0
    static let noteFontSizeRange = 9.0...28.0
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

/// The font families chosen in Settings. An empty family means the system
/// font, and a family that is no longer installed falls back to it too.
struct EntryFonts: Hashable {
    var textFamily = ""
    var codeFamily = ""

    func text(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        Self.font(family: textFamily, size: size, weight: weight)
            ?? NSFont.systemFont(ofSize: size, weight: weight)
    }

    func code(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        Self.font(family: codeFamily, size: size, weight: weight)
            ?? NSFont.monospacedSystemFont(ofSize: size, weight: weight)
    }

    /// NSFontManager picks the family member closest to the requested weight,
    /// so families without a semibold still get their bold.
    private static func font(family: String, size: CGFloat, weight: NSFont.Weight) -> NSFont? {
        guard !family.isEmpty else { return nil }
        let managerWeight: Int
        switch weight {
        case ..<NSFont.Weight.regular: managerWeight = 4
        case ..<NSFont.Weight.medium: managerWeight = 5
        case ..<NSFont.Weight.semibold: managerWeight = 6
        case ..<NSFont.Weight.bold: managerWeight = 8
        default: managerWeight = 9
        }
        return NSFontManager.shared.font(
            withFamily: family,
            traits: [],
            weight: managerWeight,
            size: size
        )
    }

    /// Listed once, since checking every family for fixed pitch loads each
    /// font. Fonts installed while the app runs appear after a relaunch.
    static let installedFamilies: [String] = NSFontManager.shared.availableFontFamilies
        .filter { !$0.hasPrefix(".") }
        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

    static let installedMonospacedFamilies: [String] = installedFamilies.filter { family in
        font(family: family, size: NSFont.systemFontSize, weight: .regular)?.isFixedPitch == true
    }
}
