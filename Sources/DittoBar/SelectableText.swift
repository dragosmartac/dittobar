import AppKit
import SwiftUI

private extension NSAttributedString.Key {
    static let dittoInlineCode = NSAttributedString.Key("DittoInlineCode")
}

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
        let width = bound

        // Cap at the proposal so a short label does not shove its neighbours
        // out of an HStack, but still report the height wrapping needs.
        return CGSize(
            width: min(ceil(fitting.width) + inlineCodeHorizontalInset, width),
            height: ceil(fitting.height)
        )
    }

    private var inlineCodeHorizontalInset: CGFloat {
        guard containsInlineCode else { return 0 }
        return InlineCodeTextFieldCell.horizontalInset * 2
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
    static let horizontalInset: CGFloat = 3
    private static let verticalInset: CGFloat = 1.5

    override func titleRect(forBounds rect: NSRect) -> NSRect {
        var titleRect = super.titleRect(forBounds: rect)
        guard containsInlineCode else { return titleRect }
        titleRect.origin.x += Self.horizontalInset
        titleRect.size.width = max(0, titleRect.width - Self.horizontalInset * 2)
        return titleRect
    }

    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        drawInlineCodeBackgrounds(in: cellFrame, controlView: controlView)
        super.drawInterior(withFrame: cellFrame, in: controlView)
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
            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: characterRange,
                actualCharacterRange: nil
            )
            layoutManager.enumerateEnclosingRects(
                forGlyphRange: glyphRange,
                withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                in: textContainer
            ) { rect, _ in
                var pillRect = rect.offsetBy(dx: textRect.minX, dy: textRect.minY)
                pillRect.origin.x -= Self.horizontalInset
                pillRect.size.width += Self.horizontalInset * 1.5
                pillRect = pillRect.insetBy(dx: 0, dy: -Self.verticalInset)
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

/// Attributed-string equivalents of the SwiftUI fonts the rows used before.
///
/// Explicit sizes rather than `NSFont.preferredFont(forTextStyle:)` — on macOS
/// those text styles do not line up with SwiftUI's `.headline` / `.caption`,
/// which made the rows render at inconsistent sizes.
enum EntryTextStyle {
    static func title(_ text: String, size: CGFloat) -> NSAttributedString {
        NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: size, weight: .semibold),
                .foregroundColor: NSColor.labelColor
            ]
        )
    }

    /// Descriptions support inline Markdown and variables. Private-use marker
    /// characters let the Markdown parser remove its delimiters without losing
    /// which rendered ranges came from variable placeholders.
    static func markdownRenderedDescription(
        _ segments: [TextVariables.Segment],
        size: CGFloat,
        emphasized: Bool = false,
        baseColor: NSColor = .secondaryLabelColor,
        lineSpacing: CGFloat = 0
    ) -> NSAttributedString {
        let rendered = renderMarkdown(
            segments,
            size: size,
            emphasized: emphasized,
            baseColor: baseColor
        ) ?? build(
            segments,
            plain: NSFont.systemFont(
                ofSize: size,
                weight: emphasized ? .semibold : .regular
            ),
            emphasised: NSFont.systemFont(ofSize: size, weight: .semibold),
            plainColor: baseColor
        )
        guard lineSpacing > 0, rendered.length > 0 else { return rendered }

        let result = NSMutableAttributedString(attributedString: rendered)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = lineSpacing
        paragraphStyle.lineBreakMode = .byWordWrapping
        result.addAttribute(
            .paragraphStyle,
            value: paragraphStyle,
            range: NSRange(location: 0, length: result.length)
        )
        return result
    }

    /// Substituted variable values are tinted and bold, as in the SwiftUI version.
    static func payload(
        _ segments: [TextVariables.Segment],
        size: CGFloat
    ) -> NSAttributedString {
        return build(
            segments,
            plain: NSFont.monospacedSystemFont(ofSize: size, weight: .regular),
            emphasised: NSFont.monospacedSystemFont(ofSize: size, weight: .bold),
            plainColor: .labelColor
        )
    }

    private static func renderMarkdown(
        _ segments: [TextVariables.Segment],
        size: CGFloat,
        emphasized: Bool,
        baseColor: NSColor
    ) -> NSAttributedString? {
        let variableStart = "\u{E000}"
        let variableEnd = "\u{E001}"
        let markedSource = segments.map { segment in
            segment.isVariable
                ? "\(variableStart)\(segment.text)\(variableEnd)"
                : segment.text
        }.joined()

        guard let parsed = try? AttributedString(
            markdown: markedSource,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) else {
            return nil
        }

        let result = NSMutableAttributedString()
        var isVariable = false

        for run in parsed.runs {
            let intent = run.inlinePresentationIntent ?? []
            let isCode = intent.contains(.code)
            let isBold = intent.contains(.stronglyEmphasized)
            let isItalic = intent.contains(.emphasized)
            let isStruckThrough = intent.contains(.strikethrough)

            for character in parsed[run.range].characters {
                let text = String(character)
                if text == variableStart {
                    isVariable = true
                    continue
                }
                if text == variableEnd {
                    isVariable = false
                    continue
                }

                var font = isCode
                    ? NSFont.monospacedSystemFont(
                        ofSize: size,
                        weight: emphasized || isVariable || isBold ? .semibold : .regular
                    )
                    : NSFont.systemFont(
                        ofSize: size,
                        weight: emphasized || isVariable || isBold ? .semibold : .regular
                    )

                if isItalic {
                    let descriptor = font.fontDescriptor.withSymbolicTraits(.italic)
                    font = NSFont(descriptor: descriptor, size: size) ?? font
                }

                var attributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: isVariable
                        ? NSColor.controlAccentColor
                        : baseColor
                ]

                if isCode {
                    attributes[.dittoInlineCode] = true
                }
                if isStruckThrough {
                    attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                }
                if let link = run.link,
                   let target = linkTarget(for: link) {
                    attributes[.link] = target
                    attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
                    if !isVariable {
                        attributes[.foregroundColor] = NSColor.linkColor
                    }
                }

                result.append(NSAttributedString(string: text, attributes: attributes))
            }
        }

        widenWhitespaceAroundInlineCode(in: result, size: size)
        return result
    }

    /// A system-font space is visually cramped beside a bordered code pill.
    /// Give adjacent whitespace the wider monospace advance without inserting
    /// characters, so selecting and copying still returns the original text.
    private static func widenWhitespaceAroundInlineCode(
        in result: NSMutableAttributedString,
        size: CGFloat
    ) {
        let fullRange = NSRange(location: 0, length: result.length)
        var codeRanges: [NSRange] = []
        result.enumerateAttribute(.dittoInlineCode, in: fullRange) { value, range, _ in
            if value != nil {
                codeRanges.append(range)
            }
        }

        for codeRange in codeRanges {
            for location in [codeRange.location - 1, NSMaxRange(codeRange)]
            where location >= 0 && location < result.length {
                let range = NSRange(location: location, length: 1)
                let character = (result.string as NSString).substring(with: range)
                guard character.rangeOfCharacter(from: .whitespacesAndNewlines) != nil else {
                    continue
                }
                result.addAttribute(
                    .font,
                    value: NSFont.monospacedSystemFont(ofSize: size, weight: .regular),
                    range: range
                )
            }
        }
    }

    /// Markdown accepts relative link destinations, but descriptions do not
    /// have a meaningful base URL. Treat destinations such as `www.apple.com`
    /// as web links instead of handing AppKit a relative file URL.
    private static func linkTarget(for link: URL) -> URL? {
        guard link.scheme == nil else { return link }

        let destination = link.relativeString
        guard !destination.isEmpty, !destination.hasPrefix("#") else { return nil }
        return URL(string: "https://\(destination)")
    }

    private static func build(
        _ segments: [TextVariables.Segment],
        plain: NSFont,
        emphasised: NSFont,
        plainColor: NSColor
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for segment in segments {
            result.append(
                NSAttributedString(
                    string: segment.text,
                    attributes: [
                        .font: segment.isVariable ? emphasised : plain,
                        .foregroundColor: segment.isVariable
                            ? NSColor.controlAccentColor
                            : plainColor
                    ]
                )
            )
        }
        return result
    }
}
