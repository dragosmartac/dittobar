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
    @AppStorage(DisplayPreferences.commandFontSizeKey)
    private var commandFontSize = DisplayPreferences.defaultCommandFontSize

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if store.sheets.isEmpty {
                emptyState
            } else {
                commandList
            }

            Divider()
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay {
            // Built only while a form is up, so its @FocusState starts fresh
            // each time instead of carrying focus over from the last command.
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
                store.createNewSheetInVSCode(named: store.newSheetName)
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
                Text("Bar Cheat Sheets")
                    .font(.headline)
                Spacer()
                MoreOptionsButton(store: store)
                    .frame(width: 20, height: 20)
            }

            TextField("Search commands", text: $store.query)
                .textFieldStyle(.roundedBorder)
                .focused($searchIsFocused)
                .onChange(of: store.query) {
                    store.selectedCommandIndex = 0
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

    private var commandList: some View {
        ScrollViewReader { proxy in
            List(Array(store.visibleCommands.enumerated()), id: \.element.id) { index, item in
                CommandRow(
                    command: item,
                    segments: store.resolvedSegments(for: item),
                    detailSegments: store.resolvedDetailSegments(for: item),
                    titleFontSize: CGFloat(titleFontSize),
                    descriptionFontSize: CGFloat(descriptionFontSize),
                    commandFontSize: CGFloat(commandFontSize),
                    isSelected: index == store.selectedCommandIndex,
                    wasCopied: item.id == store.copiedCommandID
                )
                .id(item.id)
                .contentShape(Rectangle())
                // No double-click action: it would swallow the double-click
                // that selects a word in the selectable text below.
                .onTapGesture {
                    store.selectedCommandIndex = index
                }
                .listRowBackground(
                    item.id == store.copiedCommandID
                        ? Color.green.opacity(0.24)
                        : index == store.selectedCommandIndex
                            ? Color.accentColor.opacity(0.12)
                            : Color.clear
                )
            }
            .listStyle(.inset)
            .overlay {
                if store.visibleCommands.isEmpty {
                    ContentUnavailableView.search(text: store.query)
                }
            }
            .onChange(of: store.selectedCommandIndex) {
                if let id = store.selectedCommand?.id {
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
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
            Text("⌘⌥←/→ tabs")
            Label("↩ copy", systemImage: "doc.on.doc")
            Text("⌘↩ skip form")
            Text("⌘E edit")
            Text("⌘F search")
            Text("⌘⇧N new")
            Text("⌘⇧M more")
            Spacer()
            Text("⌥Space")
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .frame(height: 38)
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
                "New Cheat Sheet in VS Code",
                action: #selector(createNewSheet),
                key: "n",
                modifiers: [.command, .shift]
            )
            addItem("Edit Current Sheet in VS Code", action: #selector(editCurrentSheet), key: "e")
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
            addItem("Quit Bar Cheat Sheets", action: #selector(quitApplication), key: "q")

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
            store.openSelectedSheetInVSCode()
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

private struct CommandRow: View {
    let command: CheatCommand
    let segments: [CommandTemplate.Segment]
    let detailSegments: [CommandTemplate.Segment]
    let titleFontSize: CGFloat
    let descriptionFontSize: CGFloat
    let commandFontSize: CGFloat
    let isSelected: Bool
    let wasCopied: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                SelectableText(
                    attributedString: CommandTextStyle.title(command.title, size: titleFontSize),
                    maximumNumberOfLines: 1
                )
                .fixedSize()
                if command.hasVariables {
                    VariableCountBadge(count: command.variables.count)
                }
                Spacer()
                if wasCopied {
                    Label("Copied", systemImage: "checkmark")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            if !command.detail.isEmpty {
                SelectableText(
                    attributedString: CommandTextStyle.detail(
                        detailSegments,
                        size: descriptionFontSize
                    )
                )
            }

            if !command.isDescriptionOnly {
                SelectableText(
                    attributedString: CommandTextStyle.command(segments, size: commandFontSize),
                    maximumNumberOfLines: 4
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(
                    Color(nsColor: .textBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 6)
                )
            }
        }
        .padding(.vertical, 5)
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
