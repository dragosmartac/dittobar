import SwiftUI

struct MainFooter: View {
    @ObservedObject var store: CheatSheetStore
    let chromeSize: CGFloat

    var body: some View {
        HStack(alignment: .bottom, spacing: 14) {
            footerHints.frame(maxWidth: .infinity, alignment: .leading)
            footerShortcut("⌘⇧M", label: "more options")
        }
        .font(.system(size: chromeSize * 0.85))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .frame(minHeight: max(38, chromeSize * 2.6))
        .fixedSize(horizontal: false, vertical: true)
    }

    private var footerHints: some View {
        ShortcutHintsLayout {
            switch store.selectedItem {
            case .entry(let entry):
                footerShortcut("↩", label: entry.hasVariables ? "fill variables" : returnVerb(for: entry))
                footerShortcut("⌥↩", label: "options")
                if entry.hasVariables {
                    footerShortcut("⌘↩", label: returnVerb(for: entry))
                }
            case .section(let section):
                footerShortcut("↩", label: store.isCollapsed(section) ? "expand" : "collapse")
                footerShortcut("⌥↩", label: "options")
            case nil:
                EmptyView()
            }
            footerShortcut("⌘⇧N", label: "new sheet")
            if store.selectedSheet != nil {
                footerShortcut("⌘E", label: "edit sheet")
                footerShortcut("⌘+", label: "add entry")
                if store.selectedEntry != nil {
                    footerShortcut("⌘=", label: "edit entry")
                    footerShortcut("⌘−", label: "remove entry")
                }
            }
        }
    }

    private func footerShortcut(_ keys: String, label: String) -> some View {
        FooterShortcutHint(keys: keys, label: label, keySize: chromeSize * 0.8)
    }

    private func returnVerb(for entry: CheatSheetEntry) -> String {
        switch entry.actions.primary {
        case .openURL, .openFile, .revealInFinder:
            return "open"
        default:
            return "copy"
        }
    }
}
