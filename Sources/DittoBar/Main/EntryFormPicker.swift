import AppKit
import SwiftUI

/// A native pop-up button that participates in the form's key-view loop even
/// when macOS Keyboard navigation is off.
struct EntryFormPicker<Value: Hashable>: NSViewRepresentable {
    enum Item: Equatable {
        case option(String, Value)
        case divider
    }

    let label: String
    @Binding var selection: Value
    let items: [Item]

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = FocusablePopUpButton()
        button.target = context.coordinator
        button.action = #selector(Coordinator.choose(_:))
        button.setAccessibilityLabel(label)
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        let coordinator = context.coordinator
        if button.numberOfItems == 0 || items != coordinator.picker.items {
            button.removeAllItems()
            for item in items {
                switch item {
                case .option(let title, _):
                    button.menu?.addItem(withTitle: title, action: nil, keyEquivalent: "")
                case .divider:
                    button.menu?.addItem(.separator())
                }
            }
        }
        coordinator.picker = self
        let index = items.firstIndex {
            guard case .option(_, let value) = $0 else { return false }
            return value == selection
        }
        button.selectItem(at: index ?? -1)
    }

    @MainActor
    final class Coordinator: NSObject {
        var picker: EntryFormPicker

        init(_ picker: EntryFormPicker) { self.picker = picker }

        @objc func choose(_ sender: NSPopUpButton) {
            let index = sender.indexOfSelectedItem
            guard picker.items.indices.contains(index),
                  case .option(_, let value) = picker.items[index] else { return }
            picker.selection = value
        }
    }
}

private final class FocusablePopUpButton: NSPopUpButton {
    override var acceptsFirstResponder: Bool { isEnabled }
    override var canBecomeKeyView: Bool { isEnabled && !isHiddenOrHasHiddenAncestor }

    override func keyDown(with event: NSEvent) {
        // Return (36) or keypad Enter (76) opens this button's native menu.
        if event.keyCode == 36 || event.keyCode == 76,
           event.modifierFlags.isDisjoint(with: [.command, .control, .option, .shift]) {
            if !event.isARepeat { performClick(nil) }
            return
        }
        super.keyDown(with: event)
    }
}
