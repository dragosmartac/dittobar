import AppKit
import SwiftUI

extension NSColor {
    /// The app's accent, used instead of the system accent colour.
    static var dittoAccent: NSColor {
        DisplayPreferences.accentColor(from: UserDefaults.standard.string(forKey: DisplayPreferences.accentColorKey) ?? "")
    }
}

extension Color {
    static var dittoAccent: Color { Color(nsColor: .dittoAccent) }
}

private struct DittoAccentKey: EnvironmentKey {
    static let defaultValue = Color(nsColor: .systemOrange)
}

extension EnvironmentValues {
    var dittoAccent: Color {
        get { self[DittoAccentKey.self] }
        set { self[DittoAccentKey.self] = newValue }
    }
}

/// Observe the saved colour at each presentation root so changes reach all views.
struct AccentTheme: ViewModifier {
    @AppStorage(DisplayPreferences.accentColorKey) private var value = ""

    func body(content: Content) -> some View {
        let color = Color(nsColor: DisplayPreferences.accentColor(from: value))
        content.environment(\.dittoAccent, color).tint(color)
    }
}

enum PanelStyle {
    static let mutedFill = Color.primary.opacity(0.05)
}
