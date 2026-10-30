import AppKit

extension NSAttributedString.Key {
    static let dittoInlineCode = NSAttributedString.Key("DittoInlineCode")
}

enum InlineCodeStyle {
    static let horizontalInset: CGFloat = 3
    static let verticalInset: CGFloat = 1.5
    /// Keeps pills on consecutive lines from touching.
    static let minimumLineSpacing: CGFloat = verticalInset * 2 + 2
}
