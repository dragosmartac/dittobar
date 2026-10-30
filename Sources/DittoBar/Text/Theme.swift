import AppKit
import SwiftUI

extension NSColor {
    /// The app's accent, used instead of the system accent colour.
    static let dittoAccent = NSColor.systemOrange
}

extension Color {
    static let dittoAccent = Color(nsColor: .dittoAccent)
}

enum PanelStyle {
    static let mutedFill = Color.primary.opacity(0.05)
}
