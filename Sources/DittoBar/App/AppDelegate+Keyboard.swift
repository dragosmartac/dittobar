import AppKit

extension AppDelegate {
    /// Return nil to consume a key press, or return the event to let AppKit deliver it.
    func handleKeyEvent(_ event: NSEvent) -> NSEvent? {
        guard panel.isVisible else { return event }

        // keyCode identifies a physical key. Letter and number shortcuts below use
        // charactersIgnoringModifiers to read the character for the current keyboard layout.
        // Caps Lock and the numeric keypad do not change the meaning of a shortcut.
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])

        // Alerts bring their own Return and Escape handling.
        if store.isNewSheetPromptPresented || store.editorErrorMessage != nil
            || copyOptionsController.isPresented {
            return event
        }

        // SwiftUI can host the entry form inside the panel or in an attached sheet.
        if let form = store.entryForm, !form.isMarkdownHelpPresented, let window = event.window,
           window === (panel.attachedSheet ?? panel),
           modifiers == .command,
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
        guard !store.isPanelSheetPresented, panel.attachedSheet == nil, event.window === panel else { return event }

        // The variable form owns the keyboard while it is open: Tab moves
        // between its fields and Return confirms via their onSubmit.
        if store.isVariableFormPresented {
            if event.keyCode == 53 { // Escape
                store.cancelVariableForm()
                return nil
            }
            return event
        }

        if moreOptions.highlightedItem != nil {
            moreOptions.handleKeyEvent(event)
            return nil
        }

        if event.keyCode == 53 { // Escape
            closePanel(restoringFocus: true)
            return nil
        }

        let character = event.modifierFlags.contains(.function) ? nil : event.charactersIgnoringModifiers?.lowercased()
        if modifiers == .command, let character, let number = Int(character), (1...9).contains(number) {
            store.selectSheet(at: number - 1)
            return nil
        }
        // Match the produced symbol so Shift-= and keypad + both add an entry.
        switch (character, modifiers) {
        case ("+", .command), ("+", [.command, .shift]):
            guard store.selectedSheet != nil else { return event }
            if !event.isARepeat { store.beginNewEntry() }
        case ("=", .command), ("=", [.command, .shift]):
            if !event.isARepeat { store.editSelectedEntry() }
        case ("-", .command), ("-", [.command, .shift]):
            if !event.isARepeat { store.requestEntryRemoval() }
        case ("f", .command):
            NotificationCenter.default.post(name: .focusCheatSheetSearch, object: nil)
        case (",", .command):
            store.isSettingsPresented = true
        case ("m", [.command, .shift]):
            moreOptions.open()
        case ("n", [.command, .shift]):
            store.requestNewSheetCreation()
        case ("e", .command):
            store.openSelectedSheetInEditor()
        default:
            return handleNavigationKey(event, modifiers: modifiers)
        }
        return nil
    }

    private func handleNavigationKey(_ event: NSEvent, modifiers: NSEvent.ModifierFlags) -> NSEvent? {
        switch (event.keyCode, modifiers) {
        case (123, [.command, .option]): // Left Arrow
            store.moveSheetSelection(by: -1)
        case (124, [.command, .option]): // Right Arrow
            store.moveSheetSelection(by: 1)
        case (48, []), (125, []): // Tab or Down Arrow
            store.moveSelection(by: 1, isRepeat: event.isARepeat)
        case (48, .shift), (126, []): // Shift-Tab or Up Arrow
            store.moveSelection(by: -1, isRepeat: event.isARepeat)
        case (36, .option), (76, .option): // Option-Return or Option-keypad Enter
            if let item = store.selectedItem { copyOptionsController.present(for: item) }
        case (36, []), (76, []):
            store.performPrimaryActionForSelectedEntry()
        case (36, .command), (76, .command):
            store.performPrimaryActionForSelectedEntry(skippingVariableForm: true)
        default:
            return event
        }
        return nil
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
