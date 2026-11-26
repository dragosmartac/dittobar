import AppKit
import SwiftUI

@MainActor
final class MoreOptionsMenu: NSObject, ObservableObject, NSMenuItemValidation {
    @Published private(set) var highlightedItem: NSMenuItem?

    private let store: CheatSheetStore
    let menu = NSMenu()

    init(store: CheatSheetStore) {
        self.store = store
        super.init()

        addItem("Add Sheet Entry", action: #selector(addEntry), key: "+")
        addItem("Edit Selected Entry", action: #selector(editSelectedEntry), key: "=")
        addItem("Remove Selected Entry", action: #selector(removeSelectedEntry), key: "-")
        menu.addItem(.separator())
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
        addItem("Display Markdown Rules", action: #selector(displayMarkdownRules))
        menu.addItem(.separator())
        addItem("Settings…", action: #selector(openSettings), key: ",")
        menu.addItem(.separator())
        addItem("Quit DittoBar", action: #selector(quitApplication), key: "q")
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

    private var selectableItems: [NSMenuItem] {
        menu.items.filter { !$0.isSeparatorItem && !$0.isHidden && validateMenuItem($0) }
    }

    func open() {
        highlightedItem = selectableItems.first
    }

    func dismiss() {
        highlightedItem = nil
    }

    func highlight(_ item: NSMenuItem) {
        if validateMenuItem(item) { highlightedItem = item }
    }

    func choose(_ item: NSMenuItem) {
        guard validateMenuItem(item) else { return }
        dismiss()
        menu.performActionForItem(at: menu.index(of: item))
    }

    private func move(by offset: Int) {
        let items = selectableItems
        guard let current = highlightedItem, let index = items.firstIndex(of: current) else {
            highlightedItem = offset > 0 ? items.first : items.last
            return
        }
        highlightedItem = items[(index + offset + items.count) % items.count]
    }

    func handleKeyEvent(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        switch (event.keyCode, flags) {
        case (48, []), (125, []): // Tab or Down Arrow
            move(by: 1)
        case (48, .shift), (126, []): // Shift-Tab or Up Arrow
            move(by: -1)
        case (53, []): // Escape
            dismiss()
        case (36, []), (76, []), (49, []): // Return, keypad Enter, or Space
            if let highlightedItem { choose(highlightedItem) }
        default:
            if menu.performKeyEquivalent(with: event) {
                dismiss()
            } else if flags.isSubset(of: .shift), let text = event.characters, !text.isEmpty,
                      let match = selectableItems.first(where: { $0.title.localizedLowercase.hasPrefix(text.localizedLowercase) }) {
                highlightedItem = match
            }
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(addEntry), #selector(editCurrentSheet), #selector(copyCurrentSheetPath):
            store.selectedSheet != nil
        case #selector(editSelectedEntry), #selector(removeSelectedEntry): store.selectedEntry != nil
        default: true
        }
    }

    @objc private func removeSelectedEntry() {
        store.requestEntryRemoval()
    }

    @objc private func addEntry() {
        store.beginNewEntry()
    }

    @objc private func editSelectedEntry() {
        store.editSelectedEntry()
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

    @objc private func displayMarkdownRules() {
        store.isMarkdownRulesPresented = true
    }

    @objc private func openSettings() {
        store.isSettingsPresented = true
    }

    @objc private func quitApplication() {
        NSApp.terminate(nil)
    }
}

struct MoreOptionsAnchor: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

struct MoreOptionsList: View {
    @Environment(\.dittoAccent) private var accentColor
    @ObservedObject var options: MoreOptionsMenu

    var body: some View {
        ViewThatFits(in: .vertical) {
            rows
            ScrollViewReader { proxy in
                ScrollView { rows }
                    .onChange(of: options.highlightedItem) { _, item in
                        if let item { proxy.scrollTo(item) }
                    }
            }
        }
        .padding(5)
        .frame(width: 260)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 6)
    }

    private var rows: some View {
        VStack(spacing: 1) {
            ForEach(options.menu.items, id: \.self) { item in
                if item.isSeparatorItem {
                    Divider().padding(.vertical, 3)
                } else {
                    let selected = options.highlightedItem == item
                    Button {
                        options.choose(item)
                    } label: {
                        HStack {
                            Text(item.title)
                            Spacer()
                            Text(shortcut(for: item))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(selected ? accentColor.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 4))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .onHover { inside in
                        if inside { options.highlight(item) }
                    }
                    .disabled(!options.validateMenuItem(item))
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func shortcut(for item: NSMenuItem) -> String {
        guard !item.keyEquivalent.isEmpty else { return "" }
        let flags = item.keyEquivalentModifierMask
        return (flags.contains(.shift) ? "⇧" : "") + (flags.contains(.command) ? "⌘" : "")
            + item.keyEquivalent.uppercased()
    }
}
