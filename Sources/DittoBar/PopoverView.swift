import AppKit
import SwiftUI

extension Notification.Name {
    static let focusCheatSheetSearch = Notification.Name("focusCheatSheetSearch")
    static let openCheatSheetMoreOptions = Notification.Name("openCheatSheetMoreOptions")
}

struct PopoverView: View {
    @ObservedObject var store: CheatSheetStore
    @FocusState private var searchIsFocused: Bool
    @AppStorage(DisplayPreferences.titleFontSizeKey)
    private var titleFontSize = DisplayPreferences.defaultTitleFontSize
    @AppStorage(DisplayPreferences.descriptionFontSizeKey)
    private var descriptionFontSize = DisplayPreferences.defaultDescriptionFontSize
    @AppStorage(DisplayPreferences.payloadFontSizeKey)
    private var payloadFontSize = DisplayPreferences.defaultPayloadFontSize

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if store.sheets.isEmpty {
                emptyState
            } else {
                entryList
            }

            Divider()
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay {
            // Built only while a form is up, so its @FocusState starts fresh
            // each time instead of carrying focus over from the last entry.
            if store.variableForm != nil {
                VariableFormView(store: store)
            }
        }
        .sheet(isPresented: $store.isSettingsPresented) {
            DisplaySettingsView()
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
            HStack {
                Image(systemName: "command.square.fill")
                    .font(.title2)
                    .foregroundStyle(.tint)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("Ditto Bar")
                        .font(.headline)
                    Text("Write it only once")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                MoreOptionsButton(store: store)
                    .frame(width: 20, height: 20)
            }

            TextField("Search entries", text: $store.query)
                .textFieldStyle(.roundedBorder)
                .focused($searchIsFocused)
                .onChange(of: store.query) {
                    store.selectedEntryIndex = 0
                }
                .onReceive(NotificationCenter.default.publisher(for: .focusCheatSheetSearch)) { _ in
                    searchIsFocused = true
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
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(
                                index == store.selectedSheetIndex
                                    ? Color.accentColor.opacity(0.18)
                                    : Color.clear,
                                in: RoundedRectangle(cornerRadius: 7)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14)
    }

    private var entryList: some View {
        ScrollViewReader { proxy in
            List(store.visibleRows) { row in
                switch row {
                case .section(let section):
                    SectionHeaderRow(title: section.title)

                case .entry(let item, let index):
                    EntryRow(
                        entry: item,
                        values: store.effectiveValues(for: item),
                        titleFontSize: CGFloat(titleFontSize),
                        descriptionFontSize: CGFloat(descriptionFontSize),
                        payloadFontSize: CGFloat(payloadFontSize),
                        isSelected: store.isEntrySelected(item, at: index),
                        wasCopied: item.id == store.copiedEntryID,
                        onSelect: { store.selectedEntryIndex = index }
                    )
                    .id(item.id)
                    .background(
                        SelectedRowAnchor(
                            store: store,
                            isSelected: store.isEntrySelected(item, at: index)
                        )
                    )
                    .contentShape(Rectangle())
                    // No double-click action: it would swallow the double-click
                    // that selects a word in the selectable text below.
                    .onTapGesture {
                        store.selectedEntryIndex = index
                    }
                    .contextMenu {
                        actionButtons(for: item)
                    }
                    .listRowBackground(
                        item.id == store.copiedEntryID
                            ? Color.green.opacity(0.24)
                            : store.isEntrySelected(item, at: index)
                                ? Color.accentColor.opacity(0.12)
                                : Color.clear
                    )
                    .listRowSeparator(.hidden)
                    .overlay(alignment: .bottom) {
                        Divider()
                    }
                }
            }
            .listStyle(.inset)
            .overlay {
                if store.visibleRows.isEmpty {
                    ContentUnavailableView.search(text: store.query)
                }
            }
            .onChange(of: store.selectedEntryIndex) {
                if let id = store.selectedEntry?.id {
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
            .onChange(of: store.query) {
                guard let id = store.visibleEntries.first?.id else { return }

                // The selected index may already be zero, in which case its
                // onChange handler does not fire. Wait for the filtered rows
                // to be laid out, then center the first result explicitly.
                DispatchQueue.main.async {
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func actionButtons(for entry: CheatSheetEntry) -> some View {
        Button(entry.actions.primary.title) {
            store.perform(entry.actions.primary, for: entry)
        }

        if !entry.actions.secondary.isEmpty {
            Divider()

            ForEach(Array(entry.actions.secondary.enumerated()), id: \.offset) { _, action in
                Button(action.title) {
                    store.perform(action, for: entry)
                }
            }
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
        HStack(spacing: 14) {
            Label("Tab / ⇧Tab navigate", systemImage: "arrow.up.arrow.down")
            footerShortcutDivider
            Text("⌘⌥←/→ tabs")
            footerShortcutDivider
            Label("↩ copy", systemImage: "doc.on.doc")
            footerShortcutDivider
            Text("⌥↩ options")
            footerShortcutDivider
            Text("⌘↩ skip form")
            footerShortcutDivider
            Text("⌘E edit")
            footerShortcutDivider
            Text("⌘F search")
            footerShortcutDivider
            Text("⌘⇧N new")
            footerShortcutDivider
            Text("⌘⇧M more")
            Spacer()
            footerShortcutDivider
            Text("⌥Space")
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .frame(height: 38)
    }

    private var footerShortcutDivider: some View {
        Divider()
            .frame(height: 14)
            .opacity(0.7)
    }
}

private struct SelectedRowAnchor: NSViewRepresentable {
    let store: CheatSheetStore
    let isSelected: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(store: store)
    }

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ view: NSView, context: Context) {
        if isSelected {
            store.selectedRowAnchorView = view
        } else if store.selectedRowAnchorView === view {
            store.selectedRowAnchorView = nil
        }
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        if coordinator.store?.selectedRowAnchorView === view {
            coordinator.store?.selectedRowAnchorView = nil
        }
    }

    @MainActor
    final class Coordinator {
        weak var store: CheatSheetStore?

        init(store: CheatSheetStore) {
            self.store = store
        }
    }
}

private struct MoreOptionsButton: NSViewRepresentable {
    let store: CheatSheetStore

    func makeCoordinator() -> Coordinator {
        Coordinator(store: store)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton()
        button.image = NSImage(
            systemSymbolName: "ellipsis.circle",
            accessibilityDescription: "More actions"
        )
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.isBordered = false
        button.toolTip = "More actions (⌘⇧M)"
        button.target = context.coordinator
        button.action = #selector(Coordinator.showMenu(_:))
        context.coordinator.button = button
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.button = button
    }

    @MainActor
    final class Coordinator: NSObject {
        weak var button: NSButton?

        private let store: CheatSheetStore
        private let menu = NSMenu()

        init(store: CheatSheetStore) {
            self.store = store
            super.init()

            addItem(
                "New Cheat Sheet in Editor",
                action: #selector(createNewSheet),
                key: "n",
                modifiers: [.command, .shift]
            )
            addItem("Edit Current Sheet in Editor", action: #selector(editCurrentSheet), key: "e")
            addItem("Open Cheat Sheets Folder", action: #selector(openFolder))
            addItem(
                "Copy Cheat Sheets Folder Path",
                action: #selector(copyFolderPath),
                key: "c",
                modifiers: []
            )
            menu.addItem(.separator())
            addItem("Settings…", action: #selector(openSettings), key: ",")
            menu.addItem(.separator())
            addItem("Quit DittoBar", action: #selector(quitApplication), key: "q")

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(openMenuFromKeyboard(_:)),
                name: .openCheatSheetMoreOptions,
                object: nil
            )
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        private func addItem(
            _ title: String,
            action: Selector,
            key: String = "",
            modifiers: NSEvent.ModifierFlags = .command
        ) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers
            item.target = self
            menu.addItem(item)
        }

        @objc func showMenu(_ sender: NSButton) {
            showMenu(relativeTo: sender)
        }

        @objc private func openMenuFromKeyboard(_ notification: Notification) {
            guard let button else { return }
            showMenu(relativeTo: button)
        }

        private func showMenu(relativeTo button: NSButton) {
            menu.popUp(
                positioning: menu.items.first,
                at: NSPoint(x: button.bounds.minX, y: button.bounds.minY),
                in: button
            )
        }

        @objc private func editCurrentSheet() {
            store.openSelectedSheetInEditor()
        }

        @objc private func createNewSheet() {
            store.requestNewSheetCreation()
        }

        @objc private func openFolder() {
            store.openFolder()
        }

        @objc private func copyFolderPath() {
            store.copyFolderPath()
        }

        @objc private func openSettings() {
            store.isSettingsPresented = true
        }

        @objc private func quitApplication() {
            NSApp.terminate(nil)
        }
    }
}

private struct EntryRow: View {
    let entry: CheatSheetEntry
    let values: [String: String]
    let titleFontSize: CGFloat
    let descriptionFontSize: CGFloat
    let payloadFontSize: CGFloat
    let isSelected: Bool
    let wasCopied: Bool
    let onSelect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                SelectableText(
                    attributedString: EntryTextStyle.title(entry.title, size: titleFontSize),
                    maximumNumberOfLines: 1,
                    onMouseDown: onSelect
                )
                .fixedSize()
                if entry.hasVariables {
                    VariableCountBadge(count: entry.variables.count)
                }
                if case .url = entry {
                    Label("URL", systemImage: "link")
                        .font(.caption2)
                        .foregroundStyle(.tint)
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
                descriptionText(note.rawContent)
            case .command(let command):
                if let rawDescription = command.rawDescription {
                    descriptionText(rawDescription)
                }
                payloadText(command.rawCommand)
            case .url(let url):
                if let rawDescription = url.rawDescription {
                    descriptionText(rawDescription)
                }
                payloadText(url.rawURL)
            }
        }
        .padding(.vertical, 5)
    }

    private func descriptionText(_ raw: String) -> some View {
        SelectableText(
            attributedString: EntryTextStyle.markdownRenderedDescription(
                TextVariables.segments(of: raw, values: values),
                size: descriptionFontSize
            ),
            onMouseDown: onSelect
        )
    }

    private func payloadText(_ raw: String) -> some View {
        SelectableText(
            attributedString: EntryTextStyle.payload(
                TextVariables.segments(of: raw, values: values),
                size: payloadFontSize
            ),
            maximumNumberOfLines: 4,
            onMouseDown: onSelect
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(
            Color(nsColor: .textBackgroundColor),
            in: RoundedRectangle(cornerRadius: 6)
        )
    }
}

private struct SectionHeaderRow: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 10)
            .padding(.bottom, 2)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct VariableCountBadge: View {
    let count: Int

    var body: some View {
        Label(
            count == 1 ? "1 field" : "\(count) fields",
            systemImage: "square.and.pencil"
        )
        .font(.caption2)
        .foregroundStyle(.tint)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.accentColor.opacity(0.14), in: Capsule())
    }
}
