import AppKit
import SwiftUI

struct SectionHeaderRow: View {
    let title: String
    let isCollapsed: Bool
    let fontSize: CGFloat
    let fonts: EntryFonts

    var body: some View {
        // Uppercase and a trailing rule mark a heading, so a large gray
        // title is not mistaken for a disabled entry.
        HStack(spacing: 8) {
            Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                .font(.system(size: fontSize * 0.65, weight: .semibold))
                .frame(width: fontSize * 0.8)
                .accessibilityHidden(true)
            Text(title.uppercased())
                .font(Font(fonts.text(size: fontSize * 0.8, weight: .semibold)))
                .tracking(fontSize * 0.06)
                .foregroundStyle(.primary)
                .lineLimit(1)
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(height: 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(PanelStyle.mutedFill, in: RoundedRectangle(cornerRadius: 6))
        .padding(.top, 10)
        .padding(.bottom, 4)
        .listRowSeparator(.hidden)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isHeader)
    }
}
