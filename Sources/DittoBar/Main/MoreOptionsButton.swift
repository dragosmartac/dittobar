import AppKit
import SwiftUI

struct MoreOptionsButton: NSViewRepresentable {
    let store: CheatSheetStore
    let symbolSize: CGFloat

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
        // The button only scales its image down, so size the symbol itself.
        button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: symbolSize, weight: .regular)
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
            addItem("Copy Current Sheet Path", action: #selector(copyCurrentSheetPath))
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

        @objc private func copyCurrentSheetPath() {
            store.copySelectedSheetPath()
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
