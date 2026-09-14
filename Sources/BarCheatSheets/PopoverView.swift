import AppKit
import SwiftUI

extension Notification.Name {
    static let focusCheatSheetSearch = Notification.Name("focusCheatSheetSearch")
    static let openCheatSheetMoreOptions = Notification.Name("openCheatSheetMoreOptions")
}

struct PopoverView: View {
    static let contentSize = CGSize(width: 1040, height: 960)

    @ObservedObject var store: CheatSheetStore
    @FocusState private var searchIsFocused: Bool

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
        .frame(width: Self.contentSize.width, height: Self.contentSize.height)
        .background(Color(nsColor: .windowBackgroundColor))
        .alert(
            "Unable to Open VS Code",
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
                    isSelected: index == store.selectedCommandIndex,
                    wasCopied: item.id == store.copiedCommandID
                )
                .id(item.id)
                .contentShape(Rectangle())
                .onTapGesture {
                    store.selectedCommandIndex = index
                }
                .onTapGesture(count: 2) {
                    store.selectedCommandIndex = index
                    store.copySelectedCommand()
                }
                .listRowBackground(
                    index == store.selectedCommandIndex
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
            Label("Y copy", systemImage: "doc.on.doc")
            Text("⌘E edit")
            Text("⌘F search")
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

            addItem("Edit Current Sheet in VS Code", action: #selector(editCurrentSheet), key: "e")
            addItem("Open Cheat Sheets Folder", action: #selector(openFolder))
            addItem("Copy Cheat Sheets Folder Path", action: #selector(copyFolderPath))
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

        private func addItem(_ title: String, action: Selector, key: String = "") {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
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

        @objc private func openFolder() {
            store.openFolder()
        }

        @objc private func copyFolderPath() {
            store.copyFolderPath()
        }

        @objc private func quitApplication() {
            NSApp.terminate(nil)
        }
    }
}

private struct CommandRow: View {
    let command: CheatCommand
    let isSelected: Bool
    let wasCopied: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(command.title)
                    .font(.headline)
                Spacer()
                if wasCopied {
                    Label("Copied", systemImage: "checkmark")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            if !command.detail.isEmpty {
                Text(command.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(command.command)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
        }
        .padding(.vertical, 5)
    }
}
