import AppKit
import SwiftUI

struct SelectedRowAnchor: NSViewRepresentable {
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
