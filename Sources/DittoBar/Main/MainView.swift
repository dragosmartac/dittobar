import AppKit
import SwiftUI

struct MainView: View {
    @Environment(\.dittoAccent) private var accentColor
    @ObservedObject var store: CheatSheetStore
    @ObservedObject var moreOptions: MoreOptionsMenu
    @FocusState private var searchIsFocused: Bool
    @AppStorage(DisplayPreferences.titleFontSizeKey)
    private var titleFontSize = DisplayPreferences.defaultTitleFontSize

    /// The header, tabs, and footer scale with the entry title size, so
    /// larger list text does not leave the controls around it looking tiny.
    /// The ratios match the system text styles at the default size.
    private var chromeSize: CGFloat { CGFloat(titleFontSize) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if store.sheets.isEmpty {
                emptyState
            } else {
                EntryListView(store: store)
            }

            Divider()
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { PanelBackground() }
        .overlayPreferenceValue(MoreOptionsAnchor.self) { anchor in
            if moreOptions.highlightedItem != nil, let anchor {
                GeometryReader { geometry in
                    let button = geometry[anchor]
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { moreOptions.dismiss() }
                        .accessibilityHidden(true)
                    MoreOptionsList(options: moreOptions)
                        .padding(.trailing, geometry.size.width - button.maxX)
                        .padding(.top, button.maxY + 4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
            }
        }
        .overlay {
            // Built only while a form is up, so its @FocusState starts fresh
            // each time instead of carrying focus over from the last entry.
            if store.variableForm != nil {
                VariableFormView(store: store)
            }
        }
        .sheet(item: $store.entryForm) { form in
            EntryFormView(store: store, form: form)
                .modifier(AccentTheme())
        }
        .sheet(item: $store.pendingEntryRemoval) { removal in
            RemoveEntryConfirmationView(removal: removal) {
                store.pendingEntryRemoval = nil
            } onRemove: {
                store.removeEntry(removal)
            }
            .modifier(AccentTheme())
        }
        .sheet(isPresented: $store.isMarkdownRulesPresented) {
            MarkdownRulesView()
                .modifier(AccentTheme())
        }
        .sheet(isPresented: $store.isSettingsPresented) {
            SettingsView(store: store)
                .modifier(AccentTheme())
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .alert("New Cheat Sheet", isPresented: $store.isNewSheetPromptPresented) {
            TextField("Name", text: $store.newSheetName)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                store.createNewSheetInEditor(named: store.newSheetName)
            }
            .keyboardShortcut(.defaultAction)
            .disabled(store.newSheetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Enter a name for the Markdown file.")
        }
        .alert(
            "Unable to Complete Action",
            isPresented: Binding(
                get: { store.editorErrorMessage != nil },
                set: { if !$0 { store.editorErrorMessage = nil } }
            )
        ) {
            Button("OK") {
                store.editorErrorMessage = nil
            }
        } message: {
            Text(store.editorErrorMessage ?? "Unknown error")
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            // The search field takes the title row: the menu-bar icon already
            // says which app this is, and the list gets the space back.
            HStack(spacing: 10) {
                searchField
                Button(action: moreOptions.open) {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: chromeSize * 1.15))
                        .frame(width: chromeSize * 1.5, height: chromeSize * 1.5)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("More actions")
                .help("More actions (⌘⇧M)")
                .anchorPreference(key: MoreOptionsAnchor.self, value: .bounds) { $0 }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(store.sheets.enumerated()), id: \.element.id) { index, sheet in
                        Button {
                            store.selectSheet(at: index)
                        } label: {
                            HStack(spacing: 5) {
                                if index < 9 {
                                    Text("⌘\(index + 1)")
                                        .foregroundStyle(.secondary)
                                }
                                Text(sheet.title)
                            }
                            .font(.system(size: chromeSize))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(
                                index == store.selectedSheetIndex
                                    ? accentColor.opacity(0.18)
                                    : Color.clear,
                                in: RoundedRectangle(cornerRadius: 7)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search entries", text: $store.query)
                .textFieldStyle(.plain)
                .focused($searchIsFocused)
                .onReceive(NotificationCenter.default.publisher(for: .focusCheatSheetSearch)) { _ in
                    searchIsFocused = true
                }
            if !store.query.isEmpty {
                Button {
                    store.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
            Text("⌘F")
                .font(.system(size: chromeSize * 0.8, design: .monospaced))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .font(.system(size: chromeSize))
        .padding(.horizontal, 9)
        .padding(.vertical, 9)
        .background(PanelStyle.mutedFill, in: RoundedRectangle(cornerRadius: 7))
        // Clicking the icon or padding focuses the field too.
        .contentShape(RoundedRectangle(cornerRadius: 7))
        .onTapGesture { searchIsFocused = true }
        // A thin tinted outline instead of the thick system focus ring.
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(
                    searchIsFocused ? accentColor.opacity(0.5) : Color.primary.opacity(0.08),
                    lineWidth: 1
                )
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No cheat sheets", systemImage: "doc.text")
        } description: {
            Text("Add a Markdown file to the cheat sheets folder.")
        } actions: {
            Button("Open Folder") {
                store.openFolder()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        ViewThatFits(in: .horizontal) {
            footerHints
            ScrollView(.horizontal) { footerHints }
        }
        .font(.system(size: chromeSize * 0.85))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .frame(height: max(38, chromeSize * 2.6))
    }

    private var footerHints: some View {
        HStack(spacing: 14) {
            switch store.selectedItem {
            case .entry(let entry):
                footerShortcut("↩", label: returnVerb(for: entry))
                footerShortcut("⌥↩", label: "options")
                if entry.hasVariables {
                    footerShortcut("⌘↩", label: "skip form")
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
                Divider().frame(height: chromeSize * 1.4)
                footerShortcut("⌘+", label: "add entry")
                if store.selectedEntry != nil {
                    footerShortcut("⌘=", label: "edit entry")
                    footerShortcut("⌘−", label: "remove entry")
                }
            }
            Spacer()
            footerShortcut("⌘⇧M", label: "more")
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
