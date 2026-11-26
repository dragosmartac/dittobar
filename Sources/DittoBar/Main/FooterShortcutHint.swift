import SwiftUI

struct FooterShortcutHint: View {
    let keys: String
    let label: String
    let keySize: CGFloat

    var body: some View {
        HStack(spacing: 8) {
            Text(keys)
                .font(.system(size: keySize, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(PanelStyle.mutedFill, in: RoundedRectangle(cornerRadius: 4))
                .overlay {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
                }
            Text(label)
                .foregroundStyle(.secondary.opacity(0.85))
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}

/// Keep each keycap with its label as the panel width or text size changes.
struct ShortcutHintsLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(subviews, width: proposal.width ?? .infinity).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let arrangement = arrange(subviews, width: bounds.width)
        for (view, origin) in zip(subviews, arrangement.origins) {
            view.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                       anchor: .topLeading, proposal: .unspecified)
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> (origins: [CGPoint], size: CGSize) {
        var origins: [CGPoint] = []
        var nextX: CGFloat = 0
        var rowY: CGFloat = 0
        var size = CGSize.zero
        for view in subviews {
            let hint = view.sizeThatFits(.unspecified)
            if nextX > 0, nextX + hint.width > width {
                nextX = 0
                rowY = size.height + 6
            }
            origins.append(CGPoint(x: nextX, y: rowY))
            size.width = max(size.width, nextX + hint.width)
            size.height = max(size.height, rowY + hint.height)
            nextX += hint.width + 14
        }
        return (origins, size)
    }
}
