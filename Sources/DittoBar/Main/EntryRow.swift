import AppKit
import SwiftUI

/// Equatable so a selection change re-renders only the rows whose selection
/// or copied state changed. Otherwise the `onSelect` closure, which SwiftUI
/// cannot compare, makes every row re-parse its Markdown on each key press.
struct EntryRow: View, Equatable {
    let entry: CheatSheetEntry
    let values: [String: String]
    let titleFontSize: CGFloat
    let descriptionFontSize: CGFloat
    let noteFontSize: CGFloat
    let payloadFontSize: CGFloat
    let fonts: EntryFonts
    let isSelected: Bool
    let wasCopied: Bool
    let onSelect: () -> Void

    /// `onSelect` is left out: it always selects `entry`, which is compared.
    static func == (lhs: EntryRow, rhs: EntryRow) -> Bool {
        lhs.entry == rhs.entry
            && lhs.values == rhs.values
            && lhs.titleFontSize == rhs.titleFontSize
            && lhs.descriptionFontSize == rhs.descriptionFontSize
            && lhs.noteFontSize == rhs.noteFontSize
            && lhs.payloadFontSize == rhs.payloadFontSize
            && lhs.fonts == rhs.fonts
            && lhs.isSelected == rhs.isSelected
            && lhs.wasCopied == rhs.wasCopied
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                SelectableText(
                    attributedString: EntryTextStyle.title(entry.title, size: titleFontSize, fonts: fonts),
                    maximumNumberOfLines: 1,
                    onMouseDown: onSelect
                )
                .fixedSize()
                if entry.hasVariables {
                    EntryBadge(
                        title: entry.variables.count == 1 ? "1 field" : "\(entry.variables.count) fields",
                        symbol: "square.and.pencil",
                        titleFontSize: titleFontSize,
                        fonts: fonts
                    )
                }
                if case .url = entry {
                    EntryBadge(title: "URL", symbol: "link", titleFontSize: titleFontSize, fonts: fonts)
                }
                if case .file = entry {
                    EntryBadge(title: "File", symbol: "doc", titleFontSize: titleFontSize, fonts: fonts)
                }
                Spacer()
                if wasCopied {
                    Label("Copied", systemImage: "checkmark")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            switch entry {
            case .note(let note):
                noteText(note.rawContent)
            case .command(let command):
                if let rawDescription = command.rawDescription {
                    descriptionText(rawDescription)
                }
                payloadText(command.rawCommand, language: command.language)
            case .url(let url):
                if let rawDescription = url.rawDescription {
                    descriptionText(rawDescription)
                }
                payloadText(url.rawURL)
            case .file(let file):
                if let rawDescription = file.rawDescription {
                    descriptionText(rawDescription)
                }
                payloadText(file.rawPath)
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .overlay(alignment: .leading) {
            if isSelected {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.dittoAccent)
                    .frame(width: 3)
                    .padding(.vertical, 8)
                    .padding(.leading, 4)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }

    private func descriptionText(_ raw: String) -> some View {
        MarkdownDescriptionView(
            raw: raw,
            values: values,
            fontSize: descriptionFontSize,
            fonts: fonts,
            onSelect: onSelect
        )
    }

    private func noteText(_ raw: String) -> some View {
        MarkdownDescriptionView(
            raw: raw,
            values: values,
            fontSize: noteFontSize,
            fonts: fonts,
            textColor: EntryTextStyle.noteBodyColor,
            usesExpandedParagraphLayout: true,
            onSelect: onSelect
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func payloadText(_ raw: String, language: String? = nil) -> some View {
        SelectableText(
            attributedString: EntryTextStyle.payload(
                TextVariables.segments(of: raw, values: values),
                language: language,
                size: payloadFontSize,
                fonts: fonts
            ),
            onMouseDown: onSelect
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(
            PanelStyle.mutedFill,
            in: RoundedRectangle(cornerRadius: 6)
        )
    }
}

private struct EntryBadge: View {
    let title: String
    let symbol: String
    let titleFontSize: CGFloat
    let fonts: EntryFonts

    private var badgeFontSize: CGFloat { max(9, titleFontSize * 0.8) }

    var body: some View {
        Label(title, systemImage: symbol)
        .font(Font(fonts.text(size: badgeFontSize, weight: .medium)))
        .foregroundStyle(.tint)
        .fixedSize()
        .padding(.horizontal, badgeFontSize * 0.6)
        .padding(.vertical, badgeFontSize * 0.2)
        .background(Color.dittoAccent.opacity(0.14), in: Capsule())
    }
}
