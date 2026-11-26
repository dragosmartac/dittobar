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
