import AppKit

@MainActor
final class CopyOptionsMenuController: NSObject {
    private let store: CheatSheetStore
    private weak var panel: NSPanel?
    private let copyOptionsMenu = NSMenu(title: "Copy Options")
    /// Run by the menu items, indexed by their tags.
    private var displayedActions: [() -> Void] = []
    private var copyOptionsItem: CheatSheetItem?
    private(set) var isPresented = false

    init(store: CheatSheetStore, panel: NSPanel) {
        self.store = store
        self.panel = panel
        super.init()
        copyOptionsMenu.autoenablesItems = false
    }

    func reset() {
        store.restorePinnedSelection()
        isPresented = false
        copyOptionsItem = nil
    }

    @objc private func performDisplayedAction(_ sender: NSMenuItem) {
        guard copyOptionsItem != nil,
              displayedActions.indices.contains(sender.tag) else { return }
        displayedActions[sender.tag]()
    }

    func present(for item: CheatSheetItem) {
        copyOptionsItem = item
        store.pinSelection(item)
        isPresented = true
        DispatchQueue.main.async { [weak self] in
            self?.showCopyOptionsMenu(for: item)
        }
    }

    private func showCopyOptionsMenu(for item: CheatSheetItem) {
        guard panel?.isVisible == true,
              let fallbackView = panel?.contentView else {
            isPresented = false
            copyOptionsItem = nil
            store.restorePinnedSelection()
            return
        }

        rebuildCopyOptionsMenu(for: item)

        let anchorView = store.selectedRowAnchorView?.window == fallbackView.window
            ? store.selectedRowAnchorView ?? fallbackView
            : fallbackView
        let anchorPoint: NSPoint
        if anchorView === fallbackView {
            anchorPoint = NSPoint(x: fallbackView.bounds.midX, y: fallbackView.bounds.midY)
        } else {
            anchorPoint = NSPoint(x: min(120, anchorView.bounds.midX), y: anchorView.bounds.midY)
        }

        copyOptionsMenu.popUp(
            positioning: copyOptionsMenu.items.first,
            at: anchorPoint,
            in: anchorView
        )
        store.restorePinnedSelection()
        isPresented = false
        copyOptionsItem = nil
    }

    private func rebuildCopyOptionsMenu(for item: CheatSheetItem) {
        copyOptionsMenu.removeAllItems()
        let titledActions: [(title: String, perform: () -> Void)]
        // An entry's primary action stands apart from its secondary ones.
        let separatorIndex: Int?
        switch item {
        case .entry(let entry):
            titledActions = entry.actions.all.map { action in
                (action.title, { [store] in store.perform(action, for: entry) })
            }
            separatorIndex = 1
        case .section(let section):
            titledActions = store.actions(for: section).map { action in
                (action.title, { [store] in store.perform(action, for: section) })
            }
            separatorIndex = nil
        }
        displayedActions = titledActions.map(\.perform)

        for (index, action) in titledActions.enumerated() {
            if index == separatorIndex {
                copyOptionsMenu.addItem(.separator())
            }
            let menuItem = NSMenuItem(
                title: action.title,
                action: #selector(performDisplayedAction(_:)),
                keyEquivalent: ""
            )
            menuItem.target = self
            menuItem.tag = index
            copyOptionsMenu.addItem(menuItem)
        }
    }
}
