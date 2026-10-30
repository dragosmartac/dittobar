import AppKit
import SwiftUI

struct MarkdownDescriptionView: View {
    let raw: String
    let values: [String: String]
    let fontSize: CGFloat
    let fonts: EntryFonts
    var textColor: NSColor = .secondaryLabelColor
    var usesExpandedParagraphLayout = false
    let onSelect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: usesExpandedParagraphLayout ? 14 : 6) {
            ForEach(Array(renderBlocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .text(let text):
                    renderedText(text, baseColor: textColor)
                case .quote(let quote):
                    renderedQuote(quote)
                case .table(let table):
                    renderedTable(table)
                case .list(let items):
                    renderedList(items)
                }
            }
        }
    }

    private var renderBlocks: [MarkdownText.Block] {
        let blocks = MarkdownText.blocks(in: raw)
        guard usesExpandedParagraphLayout else { return blocks }

        return blocks.flatMap { block -> [MarkdownText.Block] in
            guard case .text(let text) = block else { return [block] }
            return text.components(separatedBy: "\n\n").compactMap { paragraph in
                let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : .text(trimmed)
            }
        }
    }

    private func renderedText(
        _ raw: String,
        emphasized: Bool = false,
        baseColor: NSColor = .secondaryLabelColor
    ) -> some View {
        SelectableText(
            attributedString: EntryTextStyle.markdownRenderedDescription(
                TextVariables.segments(of: raw, values: values),
                size: fontSize,
                fonts: fonts,
                emphasized: emphasized,
                baseColor: baseColor,
                lineSpacing: EntryTextStyle.lineSpacing
            ),
            onMouseDown: onSelect
        )
    }

    private func renderedTable(_ table: MarkdownText.Table) -> some View {
        ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(Array(table.header.enumerated()), id: \.offset) { column, cell in
                        tableCell(
                            cell,
                            emphasized: true,
                            background: Color.gray.opacity(0.22),
                            drawsTrailingRule: column < table.columnCount - 1
                        )
                    }
                }

                Divider()
                    .gridCellColumns(table.columnCount)

                ForEach(Array(table.rows.enumerated()), id: \.offset) { rowIndex, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { column, cell in
                            tableCell(
                                cell,
                                background: rowIndex.isMultiple(of: 2)
                                    ? Color.clear
                                    : Color(nsColor: .controlBackgroundColor).opacity(0.35),
                                drawsTrailingRule: column < table.columnCount - 1
                            )
                        }
                    }

                    if rowIndex < table.rows.count - 1 {
                        Divider()
                            .gridCellColumns(table.columnCount)
                    }
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.8), lineWidth: 1)
            }
            .padding(.vertical, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func renderedList(_ items: [MarkdownText.ListItem]) -> some View {
        SelectableText(
            attributedString: EntryTextStyle.markdownRenderedList(
                items.map { item in
                    EntryTextStyle.ListItemSegments(
                        item: item,
                        segments: TextVariables.segments(of: item.text, values: values)
                    )
                },
                size: fontSize,
                fonts: fonts,
                baseColor: textColor,
                lineSpacing: EntryTextStyle.lineSpacing
            ),
            onMouseDown: onSelect
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func renderedQuote(_ raw: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(Color(nsColor: .tertiaryLabelColor))
                .frame(width: 3)

            renderedText(raw, baseColor: .secondaryLabelColor)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 3)
        .padding(.leading, 2)
    }

    private func tableCell(
        _ raw: String,
        emphasized: Bool = false,
        background: Color,
        drawsTrailingRule: Bool
    ) -> some View {
        renderedText(raw, emphasized: emphasized, baseColor: .labelColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(background)
            .background {
                if isInlineCodeOnly(raw) {
                    Color.primary.opacity(0.035)
                }
            }
            .overlay(alignment: .trailing) {
                if drawsTrailingRule {
                    Rectangle()
                        .fill(Color(nsColor: .separatorColor).opacity(0.65))
                        .frame(width: 1)
                }
            }
    }

    private func isInlineCodeOnly(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2,
              trimmed.hasPrefix("`"),
              trimmed.hasSuffix("`") else { return false }
        return !trimmed.dropFirst().dropLast().contains("`")
    }
}
