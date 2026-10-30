import AppKit
import SwiftUI

/// A selectable, non-editable AppKit label.
///
/// SwiftUI's `.textSelection(.enabled)` draws a selection inside a `List` but
/// never takes first responder, so `⌘C` — which travels the responder chain as
/// the `copy:` selector — is delivered to whatever is first responder instead.
/// In this app that is the search field, which has nothing selected, so the
/// copy silently does nothing. An `NSTextField` takes first responder when
/// clicked, putting the highlighted text on the receiving end of `copy:`.
struct SelectableText: NSViewRepresentable {
    let attributedString: NSAttributedString
    var maximumNumberOfLines = 0
    var onMouseDown: (() -> Void)?

    func makeNSView(context: Context) -> NSTextField {
        let field = SelectionNotifyingTextField(labelWithString: "")
        field.cell = InlineCodeTextFieldCell(textCell: "")
        field.attributedStringValue = attributedString
        field.onMouseDown = onMouseDown
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.isEditable = false
        field.isSelectable = true
        // Clicking hands rendering to the field editor. Without rich-text
        // support it redraws everything in the field's base font, so the
        // styling visibly flattens on click. The field stays non-editable.
        field.allowsEditingTextAttributes = true
        field.focusRingType = .none
        field.lineBreakMode = .byWordWrapping
        field.maximumNumberOfLines = maximumNumberOfLines
        field.cell?.usesSingleLineMode = false
        field.cell?.wraps = true
        field.cell?.isScrollable = false
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        applyBaseFont(to: field)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        (field as? SelectionNotifyingTextField)?.onMouseDown = onMouseDown
        if field.attributedStringValue != attributedString {
            field.attributedStringValue = attributedString
            applyBaseFont(to: field)
        }
        field.maximumNumberOfLines = maximumNumberOfLines
    }

    /// Anything the field editor renders without attributes falls back to the
    /// field's own font, so seed it from the string's first run.
    private func applyBaseFont(to field: NSTextField) {
        guard attributedString.length > 0,
              let font = attributedString.attribute(
                  .font,
                  at: 0,
                  effectiveRange: nil
              ) as? NSFont else { return }
        field.font = font
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: NSTextField,
        context: Context
    ) -> CGSize? {
        // A nil or infinite proposal means "size to your content" — measure
        // against an unbounded width rather than refusing to answer.
        let bound: CGFloat
        if let proposed = proposal.width, proposed > 0, proposed < .infinity {
            bound = proposed
            nsView.preferredMaxLayoutWidth = proposed
        } else {
            bound = .greatestFiniteMagnitude
        }

        let fitting = nsView.cell?.cellSize(
            forBounds: NSRect(
                x: 0,
                y: 0,
                width: max(0, bound - inlineCodeHorizontalInset),
                height: .greatestFiniteMagnitude
            )
        ) ?? .zero
        // Cap at the proposal so a short label does not shove its neighbours
        // out of an HStack, but still report the height wrapping needs.
        var width = min(ceil(fitting.width) + inlineCodeHorizontalInset, bound)

        // The unbounded measurement can come up a few points short, as with a
        // list's tab-aligned items, so at the reported width the widest line
        // would wrap and its last word fall outside the reported height. Take
        // the whole proposal then, where the text was measured to fit.
        if width < bound, bound < .greatestFiniteMagnitude {
            let heightAtWidth = nsView.cell?.cellSize(
                forBounds: NSRect(
                    x: 0,
                    y: 0,
                    width: max(0, width - inlineCodeHorizontalInset),
                    height: .greatestFiniteMagnitude
                )
            ).height ?? 0
            if heightAtWidth > fitting.height {
                width = bound
            }
        }

        return CGSize(width: width, height: ceil(fitting.height))
    }

    private var inlineCodeHorizontalInset: CGFloat {
        guard containsInlineCode else { return 0 }
        return InlineCodeStyle.horizontalInset * 2
    }

    private var containsInlineCode: Bool {
        var found = false
        attributedString.enumerateAttribute(
            .dittoInlineCode,
            in: NSRange(location: 0, length: attributedString.length)
        ) { value, _, stop in
            if value != nil {
                found = true
                stop.pointee = true
            }
        }
        return found
    }
}

/// Selectable labels consume clicks before SwiftUI's row gesture sees them.
/// Notify the row first, then preserve NSTextField's normal text-selection behavior.
private final class SelectionNotifyingTextField: NSTextField {
    var onMouseDown: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onMouseDown?()
        super.mouseDown(with: event)
    }
}

/// NSTextField supports attributed backgrounds, but they are square and hug
/// the glyphs. Draw an adaptive rounded backdrop behind inline-code ranges so
/// they read as code pills without adding characters that would affect copy.
private final class InlineCodeTextFieldCell: NSTextFieldCell {
    override func titleRect(forBounds rect: NSRect) -> NSRect {
        var titleRect = super.titleRect(forBounds: rect)
        guard containsInlineCode else { return titleRect }
        titleRect.origin.x += InlineCodeStyle.horizontalInset
        titleRect.size.width = max(0, titleRect.width - InlineCodeStyle.horizontalInset * 2)
        return titleRect
    }

    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        drawInlineCodeBackgrounds(in: cellFrame, controlView: controlView)
        super.drawInterior(withFrame: cellFrame, in: controlView)
    }

    /// The field editor draws links with its own attributes, ignoring the
    /// string's colour, so links would turn system blue on click.
    override func setUpFieldEditorAttributes(_ textObj: NSText) -> NSText {
        let textObj = super.setUpFieldEditorAttributes(textObj)
        (textObj as? NSTextView)?.linkTextAttributes = [
            .foregroundColor: NSColor.dittoAccent,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .cursor: NSCursor.pointingHand
        ]
        return textObj
    }

    private var containsInlineCode: Bool {
        guard attributedStringValue.length > 0 else { return false }
        var found = false
        attributedStringValue.enumerateAttribute(
            .dittoInlineCode,
            in: NSRange(location: 0, length: attributedStringValue.length)
        ) { value, _, stop in
            if value != nil {
                found = true
                stop.pointee = true
            }
        }
        return found
    }

    private func drawInlineCodeBackgrounds(in cellFrame: NSRect, controlView: NSView) {
        guard containsInlineCode else { return }

        let textRect = titleRect(forBounds: cellFrame)
        let textStorage = NSTextStorage(attributedString: attributedStringValue)
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(
            containerSize: NSSize(
                width: textRect.width,
                height: .greatestFiniteMagnitude
            )
        )
        textContainer.lineFragmentPadding = 0
        textContainer.lineBreakMode = lineBreakMode
        textContainer.maximumNumberOfLines = (controlView as? NSTextField)?
            .maximumNumberOfLines ?? 0
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: textContainer)

        attributedStringValue.enumerateAttribute(
            .dittoInlineCode,
            in: NSRange(location: 0, length: attributedStringValue.length)
        ) { value, characterRange, _ in
            guard value != nil else { return }
            let codeGlyphs = layoutManager.glyphRange(
                forCharacterRange: characterRange,
                actualCharacterRange: nil
            )
            let font = attributedStringValue.attribute(
                .font,
                at: characterRange.location,
                effectiveRange: nil
            ) as? NSFont ?? NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)

            // Size each pill from the code font around its baseline. The line
            // fragment also includes line spacing, so growing it would run
            // into a pill on the next line.
            layoutManager.enumerateLineFragments(forGlyphRange: codeGlyphs) { lineRect, _, _, lineGlyphs, _ in
                let glyphs = NSIntersectionRange(lineGlyphs, codeGlyphs)
                guard glyphs.length > 0 else { return }

                let bounds = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
                let baseline = lineRect.minY + layoutManager.location(forGlyphAt: glyphs.location).y
                var pillRect = NSRect(
                    x: bounds.minX,
                    y: baseline - font.ascender - InlineCodeStyle.verticalInset,
                    width: bounds.width,
                    height: font.ascender - font.descender + InlineCodeStyle.verticalInset * 2
                )
                pillRect = pillRect.offsetBy(dx: textRect.minX, dy: textRect.minY)
                pillRect.origin.x -= InlineCodeStyle.horizontalInset
                pillRect.size.width += InlineCodeStyle.horizontalInset * 1.5
                pillRect = pillRect.intersection(cellFrame)

                let path = NSBezierPath(
                    roundedRect: pillRect,
                    xRadius: 4,
                    yRadius: 4
                )
                NSColor.labelColor.withAlphaComponent(0.09).setFill()
                path.fill()
                NSColor.separatorColor.withAlphaComponent(0.75).setStroke()
                path.lineWidth = 0.75
                path.stroke()
            }
        }
    }
}
