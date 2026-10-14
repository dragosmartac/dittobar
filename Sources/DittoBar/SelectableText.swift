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
    /// Keeps pills on consecutive lines from touching.
    static let minimumLineSpacing: CGFloat = verticalInset * 2 + 2

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
                    y: baseline - font.ascender - Self.verticalInset,
                    width: bounds.width,
                    height: font.ascender - font.descender + Self.verticalInset * 2
                )
                pillRect = pillRect.offsetBy(dx: textRect.minX, dy: textRect.minY)
                pillRect.origin.x -= Self.horizontalInset
                pillRect.size.width += Self.horizontalInset * 1.5
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
    /// Matches descriptions, below entry titles and section titles. One
    /// shared instance keeps the rendered-text cache key stable.
    static let noteBodyColor = NSColor.secondaryLabelColor

    /// A step brighter than descriptions and notes, so titles lead each entry
    /// while staying dimmer than section titles.
    static let entryTitleColor = NSColor.labelColor.withAlphaComponent(0.75)

    /// Shared by all description and note text, so lines are spaced the same
    /// everywhere and inline-code pills on consecutive lines never touch.
    static let lineSpacing = InlineCodeTextFieldCell.minimumLineSpacing

    private struct MarkdownRenderedKey: Hashable {
        let segments: [TextVariables.Segment]
        let size: CGFloat
        let fonts: EntryFonts
        let emphasized: Bool
        let baseColor: NSColor
        let lineSpacing: CGFloat
    }

    /// Rendering parses Markdown and styles it character by character, and a
    /// row renders its text again each time it scrolls into view. The result
    /// depends only on the key, so keep it. Rows are only built on the main
    /// thread. Cleared when full rather than evicted one by one, since a full
    /// cache means the text or settings changed a lot anyway.
    private static var markdownRenderedCache: [MarkdownRenderedKey: NSAttributedString] = [:]
    private static let markdownRenderedCacheLimit = 2_000

    struct ListItemSegments: Hashable {
        let item: MarkdownText.ListItem
        let segments: [TextVariables.Segment]
    }

    private struct MarkdownRenderedListKey: Hashable {
        let items: [ListItemSegments]
        let size: CGFloat
        let fonts: EntryFonts
        let baseColor: NSColor
        let lineSpacing: CGFloat
    }

    private static var markdownRenderedListCache: [MarkdownRenderedListKey: NSAttributedString] = [:]

    static func title(_ text: String, size: CGFloat, fonts: EntryFonts) -> NSAttributedString {
        NSAttributedString(
            string: text,
            attributes: [
                .font: fonts.text(size: size, weight: .semibold),
                .foregroundColor: entryTitleColor
            ]
        )
    }

    /// Descriptions support inline Markdown and variables. Private-use marker
    /// characters let the Markdown parser remove its delimiters without losing
    /// which rendered ranges came from variable placeholders.
    static func markdownRenderedDescription(
        _ segments: [TextVariables.Segment],
        size: CGFloat,
        fonts: EntryFonts,
        emphasized: Bool = false,
        baseColor: NSColor = .secondaryLabelColor,
        lineSpacing: CGFloat = 0
    ) -> NSAttributedString {
        let key = MarkdownRenderedKey(
            segments: segments,
            size: size,
            fonts: fonts,
            emphasized: emphasized,
            baseColor: baseColor,
            lineSpacing: lineSpacing
        )
        if let cached = markdownRenderedCache[key] {
            return cached
        }

        let result = uncachedMarkdownRenderedDescription(
            segments,
            size: size,
            fonts: fonts,
            emphasized: emphasized,
            baseColor: baseColor,
            lineSpacing: lineSpacing
        )
        if markdownRenderedCache.count >= markdownRenderedCacheLimit {
            markdownRenderedCache.removeAll()
        }
        markdownRenderedCache[key] = result
        return result
    }

    private static func uncachedMarkdownRenderedDescription(
        _ segments: [TextVariables.Segment],
        size: CGFloat,
        fonts: EntryFonts,
        emphasized: Bool,
        baseColor: NSColor,
        lineSpacing: CGFloat
    ) -> NSAttributedString {
        let rendered = renderMarkdown(
            segments,
            size: size,
            fonts: fonts,
            emphasized: emphasized,
            baseColor: baseColor
        ) ?? build(
            segments,
            plain: fonts.text(
                size: size,
                weight: emphasized ? .semibold : .regular
            ),
            emphasised: fonts.text(size: size, weight: .semibold),
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

    /// A whole list as one string, so a selection can span items. Each item
    /// is a paragraph whose wrapped lines hang under its text, past the marker.
    static func markdownRenderedList(
        _ items: [ListItemSegments],
        size: CGFloat,
        fonts: EntryFonts,
        baseColor: NSColor = .secondaryLabelColor,
        lineSpacing: CGFloat = 0
    ) -> NSAttributedString {
        let key = MarkdownRenderedListKey(
            items: items,
            size: size,
            fonts: fonts,
            baseColor: baseColor,
            lineSpacing: lineSpacing
        )
        if let cached = markdownRenderedListCache[key] {
            return cached
        }

        let result = uncachedMarkdownRenderedList(
            items,
            size: size,
            fonts: fonts,
            baseColor: baseColor,
            lineSpacing: lineSpacing
        )
        if markdownRenderedListCache.count >= markdownRenderedCacheLimit {
            markdownRenderedListCache.removeAll()
        }
        markdownRenderedListCache[key] = result
        return result
    }

    private static func uncachedMarkdownRenderedList(
        _ items: [ListItemSegments],
        size: CGFloat,
        fonts: EntryFonts,
        baseColor: NSColor,
        lineSpacing: CGFloat
    ) -> NSAttributedString {
        let markerAttributes: [NSAttributedString.Key: Any] = [
            .font: fonts.text(size: size),
            .foregroundColor: baseColor
        ]

        // A nested item's marker starts where its parent's text starts, and
        // each depth's text starts past the widest marker at that depth.
        let leadingInset = size * 0.4
        let gap = size * 0.45
        let maxDepth = items.map(\.item.depth).max() ?? 0
        var markerColumns: [CGFloat] = []
        var textColumns: [CGFloat] = []
        for depth in 0...maxDepth {
            let widest = items
                .filter { $0.item.depth == depth }
                .map { listMarker(for: $0.item, attributes: markerAttributes, size: size, fonts: fonts).size().width }
                .max() ?? 0
            let markerColumn = depth == 0 ? leadingInset : textColumns[depth - 1]
            markerColumns.append(markerColumn)
            textColumns.append(ceil(markerColumn + max(widest, size * 0.6) + gap))
        }

        func paragraphStyle(firstLineIndent: CGFloat, textColumn: CGFloat) -> NSParagraphStyle {
            let style = NSMutableParagraphStyle()
            style.firstLineHeadIndent = firstLineIndent
            style.headIndent = textColumn
            style.tabStops = [NSTextTab(textAlignment: .left, location: textColumn)]
            style.lineSpacing = lineSpacing
            style.paragraphSpacing = size * 0.2
            style.lineBreakMode = .byWordWrapping
            return style
        }

        let renderedItems = items.map { entry in
            renderMarkdown(
                entry.segments,
                size: size,
                fonts: fonts,
                emphasized: false,
                baseColor: baseColor
            ) ?? build(
                entry.segments,
                plain: fonts.text(size: size),
                emphasised: fonts.text(size: size, weight: .semibold),
                plainColor: baseColor
            )
        }

        let result = NSMutableAttributedString()
        for (index, entry) in items.enumerated() {
            let item = entry.item
            let textColumn = textColumns[item.depth]
            let rendered = renderedItems[index]
            let paragraph = NSMutableAttributedString(
                attributedString: listMarker(for: item, attributes: markerAttributes, size: size, fonts: fonts)
            )
            paragraph.append(NSAttributedString(string: "\t", attributes: markerAttributes))
            paragraph.append(rendered)
            if index < items.count - 1 {
                paragraph.append(NSAttributedString(string: "\n", attributes: markerAttributes))
            }

            // Continuation lines inside the item are paragraphs of their own;
            // they start at the text column rather than under the marker.
            let fullRange = NSRange(location: 0, length: paragraph.length)
            paragraph.addAttribute(
                .paragraphStyle,
                value: paragraphStyle(firstLineIndent: textColumn, textColumn: textColumn),
                range: fullRange
            )
            let firstLine = (paragraph.string as NSString).paragraphRange(
                for: NSRange(location: 0, length: 0)
            )
            paragraph.addAttribute(
                .paragraphStyle,
                value: paragraphStyle(
                    firstLineIndent: markerColumns[item.depth],
                    textColumn: textColumn
                ),
                range: firstLine
            )
            result.append(paragraph)
        }
        return result
    }

    /// The `☐` and `☑` glyphs come from different fallback fonts and render
    /// at different sizes, so task checkboxes are drawn as matching symbols.
    private static func listMarker(
        for item: MarkdownText.ListItem,
        attributes: [NSAttributedString.Key: Any],
        size: CGFloat,
        fonts: EntryFonts
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        switch item.marker {
        case .bullet where item.task == nil:
            result.append(NSAttributedString(
                string: MarkdownText.ListItem.bulletGlyph(depth: item.depth),
                attributes: attributes
            ))
        case .bullet:
            break
        case .ordered(let number):
            result.append(NSAttributedString(string: "\(number).", attributes: attributes))
        }

        guard let task = item.task else { return result }
        if result.length > 0 {
            result.append(NSAttributedString(string: " ", attributes: attributes))
        }
        let symbolName = task == .done ? "checkmark.square" : "square"
        let color = attributes[.foregroundColor] as? NSColor ?? .secondaryLabelColor
        let configuration = NSImage.SymbolConfiguration(pointSize: size * 1.15, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        guard let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) else {
            result.append(NSAttributedString(
                string: task == .done ? "☑" : "☐",
                attributes: attributes
            ))
            return result
        }

        // Center the symbol on the text's x-height rather than its baseline.
        let font = attributes[.font] as? NSFont ?? fonts.text(size: size)
        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = NSRect(
            x: 0,
            y: (font.xHeight - image.size.height) / 2,
            width: image.size.width,
            height: image.size.height
        )
        let symbol = NSMutableAttributedString(attachment: attachment)
        symbol.addAttributes(attributes, range: NSRange(location: 0, length: symbol.length))
        result.append(symbol)
        return result
    }

    /// Substituted variable values are tinted and bold, as in the SwiftUI version.
    /// When the fence names a known language, the resolved text is also
    /// syntax highlighted, with variable values keeping their tint on top.
    static func payload(
        _ segments: [TextVariables.Segment],
        language: String? = nil,
        size: CGFloat,
        fonts: EntryFonts
    ) -> NSAttributedString {
        let built = build(
            segments,
            plain: fonts.code(size: size, weight: .regular),
            emphasised: fonts.code(size: size, weight: .bold),
            plainColor: .labelColor
        )
        let tokens = SyntaxHighlighter.tokens(in: built.string, language: language)
        guard !tokens.isEmpty else { return built }

        let result = NSMutableAttributedString(attributedString: built)
        for token in tokens {
            result.addAttribute(.foregroundColor, value: syntaxColor(for: token.kind), range: token.range)
        }

        var location = 0
        for segment in segments {
            let length = (segment.text as NSString).length
            if segment.isVariable {
                result.addAttribute(
                    .foregroundColor,
                    value: NSColor.controlAccentColor,
                    range: NSRange(location: location, length: length)
                )
            }
            location += length
        }
        return result
    }

    /// System colors, so they adapt to light and dark appearance.
    private static func syntaxColor(for kind: SyntaxHighlighter.TokenKind) -> NSColor {
        switch kind {
        case .keyword: .systemPink
        case .string: .systemRed
        case .comment: .secondaryLabelColor
        case .number: .systemPurple
        case .variable: .systemTeal
        }
    }

    private static func renderMarkdown(
        _ segments: [TextVariables.Segment],
        size: CGFloat,
        fonts: EntryFonts,
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
                    ? fonts.code(
                        size: size,
                        weight: emphasized || isVariable || isBold ? .semibold : .regular
                    )
                    : fonts.text(
                        size: size,
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

        widenWhitespaceAroundInlineCode(in: result, size: size, fonts: fonts)
        return result
    }

    /// A system-font space is visually cramped beside a bordered code pill.
    /// Give adjacent whitespace the wider monospace advance without inserting
    /// characters, so selecting and copying still returns the original text.
    private static func widenWhitespaceAroundInlineCode(
        in result: NSMutableAttributedString,
        size: CGFloat,
        fonts: EntryFonts
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
                    value: fonts.code(size: size, weight: .regular),
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
