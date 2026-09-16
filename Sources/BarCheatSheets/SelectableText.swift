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

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(labelWithAttributedString: attributedString)
        field.isSelectable = true
        // Clicking hands rendering to the field editor. Without rich-text
        // support it redraws everything in the field's base font, so the
        // styling visibly flattens on click. The field stays non-editable.
        field.allowsEditingTextAttributes = true
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
            forBounds: NSRect(x: 0, y: 0, width: bound, height: .greatestFiniteMagnitude)
        ) ?? .zero
        let width = bound

        // Cap at the proposal so a short label does not shove its neighbours
        // out of an HStack, but still report the height wrapping needs.
        return CGSize(width: min(ceil(fitting.width), width), height: ceil(fitting.height))
    }
}

/// Attributed-string equivalents of the SwiftUI fonts the rows used before.
///
/// Explicit sizes rather than `NSFont.preferredFont(forTextStyle:)` — on macOS
/// those text styles do not line up with SwiftUI's `.headline` / `.caption`,
/// which made the rows render at inconsistent sizes.
enum CommandTextStyle {
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
    static func detail(
        _ segments: [CommandTemplate.Segment],
        size: CGFloat
    ) -> NSAttributedString {
        markdownDetail(segments, size: size) ?? build(
            segments,
            plain: NSFont.systemFont(ofSize: size),
            emphasised: NSFont.systemFont(ofSize: size, weight: .semibold),
            plainColor: .secondaryLabelColor
        )
    }

    /// Substituted variable values are tinted and bold, as in the SwiftUI version.
    static func command(
        _ segments: [CommandTemplate.Segment],
        size: CGFloat
    ) -> NSAttributedString {
        return build(
            segments,
            plain: NSFont.monospacedSystemFont(ofSize: size, weight: .regular),
            emphasised: NSFont.monospacedSystemFont(ofSize: size, weight: .bold),
            plainColor: .labelColor
        )
    }

    private static func markdownDetail(
        _ segments: [CommandTemplate.Segment],
        size: CGFloat
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
                        weight: isVariable || isBold ? .semibold : .regular
                    )
                    : NSFont.systemFont(
                        ofSize: size,
                        weight: isVariable || isBold ? .semibold : .regular
                    )

                if isItalic {
                    let descriptor = font.fontDescriptor.withSymbolicTraits(.italic)
                    font = NSFont(descriptor: descriptor, size: size) ?? font
                }

                var attributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: isVariable
                        ? NSColor.controlAccentColor
                        : NSColor.secondaryLabelColor
                ]

                if isCode {
                    attributes[.backgroundColor] = NSColor.quaternaryLabelColor
                        .withAlphaComponent(0.14)
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

        return result
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
        _ segments: [CommandTemplate.Segment],
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
