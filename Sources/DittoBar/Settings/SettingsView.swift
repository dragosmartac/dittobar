import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: CheatSheetStore
    @State private var selectedTab: SettingsTab? = .layout

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            detail
        }
        .frame(width: 680, height: selectedTab == .sheets ? 470 : 410)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Settings")
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 10)

            List(SettingsTab.allCases, selection: $selectedTab) { tab in
                HStack(spacing: 10) {
                    Image(systemName: tab.systemImage)
                        .frame(width: 20)
                        .accessibilityHidden(true)
                    Text(tab.title)
                }
                .tag(tab)
            }
            .listStyle(.sidebar)
        }
        .frame(width: 185)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private var detail: some View {
        switch selectedTab ?? .layout {
        case .layout: LayoutSettingsView()
        case .text: TextSettingsView()
        case .sheets: SheetsSettingsView(store: store)
        case .editor: EditorSettingsView()
        case .shortcuts: ShortcutsSettingsView()
        }
    }
}

/// Shared detail layout; each tab owns its preferences and reset behavior.
struct SettingsPane<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    var isUsingDefaults = true
    var reset: (() -> Void)? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            content()
            Spacer(minLength: 0)
            Divider()
            HStack {
                if let reset {
                    Button("Reset to Defaults", action: reset)
                        .disabled(isUsingDefaults)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private enum SettingsTab: String, CaseIterable, Identifiable {
    case layout
    case text
    case editor
    case sheets
    case shortcuts

    var id: Self { self }

    var title: String {
        switch self {
        case .layout: "Layout"
        case .text: "Text"
        case .sheets: "Sheets"
        case .editor: "Editor"
        case .shortcuts: "Shortcuts"
        }
    }

    var systemImage: String {
        switch self {
        case .layout: "rectangle.split.2x1"
        case .text: "textformat.size"
        case .sheets: "folder"
        case .editor: "square.and.pencil"
        case .shortcuts: "keyboard"
        }
    }
}
