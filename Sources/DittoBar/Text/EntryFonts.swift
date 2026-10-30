import AppKit

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
