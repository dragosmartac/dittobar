import AppKit

extension AppDelegate {
    /// Return nil to consume a key press, or return the event to let AppKit deliver it.
    func handleKeyEvent(_ event: NSEvent) -> NSEvent? {
        guard panel.isVisible else { return event }

        // keyCode identifies a physical key. Letter and number shortcuts below use
        // charactersIgnoringModifiers to read the character for the current keyboard layout.
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Alerts bring their own Return and Escape handling.
        if store.isNewSheetPromptPresented || store.editorErrorMessage != nil
            || copyOptionsController.isPresented {
            return event
        }

        // SwiftUI can host Add Entry inside the panel or in an attached sheet.
        if let form = store.newEntryForm, !form.isMarkdownHelpPresented, let window = event.window,
           window === (panel.attachedSheet ?? panel),
           modifiers.intersection([.command, .option, .control, .shift]) == .command,
           let start = focusTraversalStart(in: window) {
            switch event.keyCode {
            case 125: // Down Arrow
                window.selectKeyView(following: start)
                return nil
            case 126: // Up Arrow
                window.selectKeyView(preceding: start)
                return nil
            default:
                break
            }
        }

        // Pass other sheet events through for normal editing and key equivalents.
        if store.isPanelSheetPresented {
            return event
        }

        // The variable form owns the keyboard while it is open: Tab moves
        // between its fields and Return confirms via their onSubmit.
        if store.isVariableFormPresented {
            if event.keyCode == 53 { // Escape
                store.cancelVariableForm()
                return nil
            }
            return event
        }

        if moreOptions.highlightedItem != nil, event.window === panel {
            moreOptions.handleKeyEvent(event)
            return nil
        }

        if event.keyCode == 53 { // Escape
            closePanel(restoringFocus: true)
            return nil
        }

        // Match the plus character, including Shift-= and keypad +, while search has focus too.
        if modifiers.contains(.command), event.charactersIgnoringModifiers == "+",
           modifiers.isDisjoint(with: [.control, .option, .function]),
           event.window === panel, store.selectedSheet != nil {
            if !event.isARepeat { store.beginNewEntry() }
            return nil
        }

        if modifiers.contains(.command),
           let characters = event.charactersIgnoringModifiers,
           let number = Int(characters),
           (1...9).contains(number) {
            store.selectSheet(at: number - 1)
            return nil
        }

        if modifiers.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "f" {
            NotificationCenter.default.post(name: .focusCheatSheetSearch, object: nil)
            return nil
        }

        if modifiers == .command, event.charactersIgnoringModifiers == "," {
            store.isSettingsPresented = true
            return nil
        }

        if modifiers.contains(.command), modifiers.contains(.shift),
           event.charactersIgnoringModifiers?.lowercased() == "m" {
            moreOptions.open()
            return nil
        }

        if modifiers.contains(.command), modifiers.contains(.shift),
           event.charactersIgnoringModifiers?.lowercased() == "n" {
            store.requestNewSheetCreation()
            return nil
        }

        if modifiers.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "e" {
            store.openSelectedSheetInEditor()
            return nil
        }

        if modifiers.contains(.command), modifiers.contains(.option),
           !modifiers.contains(.control), !modifiers.contains(.shift) {
            if event.keyCode == 123 { // Left Arrow
                store.moveSheetSelection(by: -1)
                return nil
            }
            if event.keyCode == 124 { // Right Arrow
                store.moveSheetSelection(by: 1)
                return nil
            }
        }

        if event.keyCode == 48 { // Tab
            store.moveSelection(by: modifiers.contains(.shift) ? -1 : 1, isRepeat: event.isARepeat)
            return nil
        }

        if event.keyCode == 125 { // Down Arrow
            store.moveSelection(by: 1, isRepeat: event.isARepeat)
            return nil
        }

        if event.keyCode == 126 { // Up Arrow
            store.moveSelection(by: -1, isRepeat: event.isARepeat)
            return nil
        }

        // Return copies, leaving ⌘C to the system so text in the list stays
        // selectable and copyable. ⌥Return opens copy options, while ⌘Return
        // copies without opening the variable form. Return toggles sections.
        if event.keyCode == 36 || event.keyCode == 76 { // Return (36) or numeric keypad Enter (76)
            if let item = store.selectedItem, modifiers == .option {
                copyOptionsController.present(for: item)
            } else if modifiers.contains(.command) {
                store.performPrimaryActionForSelectedEntry(skippingVariableForm: true)
            } else {
                store.performPrimaryActionForSelectedEntry()
            }
            return nil
        }

        return event
    }

    private func focusTraversalStart(in window: NSWindow) -> NSView? {
        // A single-line field edits through a shared NSTextView. The field itself
        // participates in the key-view loop, so start traversal from its owner.
        if let editor = window.firstResponder as? NSTextView, editor.isFieldEditor,
           let owner = editor.delegate as? NSView {
            return owner
        }
        return window.firstResponder as? NSView ?? window.contentView
    }
}
