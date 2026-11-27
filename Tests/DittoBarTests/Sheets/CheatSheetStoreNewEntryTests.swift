import AppKit
import Carbon
import SwiftUI
import Testing
@testable import DittoBar

// The keyboard tests present real sheets, which share the application's key window.
@Suite(.serialized)
@MainActor
struct CheatSheetStoreNewEntryTests {
    @Test func capturedTabOpensAnEditableDraftAndWritesOnlyOnSave() throws {
        let record = NSAppleEventDescriptor.record()
        let url = "https://example.org/page?a=1&b=2#top"
        record.setDescriptor(.init(string: url), forKeyword: 0x55524C20) // Chrome's 'URL ' property
        record.setDescriptor(.init(string: "Example\npage"), forKeyword: AEKeyword(pName))
        let draft = try ChromeTabCapture.draft(from: record)
        #expect(draft == EntryDraft(kind: .url, title: "Example page", rawContent: url))

        try withStore { store in
            store.selectSheet(at: 1)
            let destination = try #require(store.selectedSheet?.sourceURL)
            let original = try String(contentsOf: destination, encoding: .utf8)
            store.beginNewEntry(draft: draft)
            #expect(store.entryForm?.sheetURL == destination)
            #expect(store.entryForm?.draft == draft)
            store.cancelEntryForm()
            #expect(try String(contentsOf: destination, encoding: .utf8) == original)

            store.beginNewEntry(draft: draft)
            store.entryForm?.draft.title = "Saved tab"
            store.saveEntryForm()
            let saved = try #require(store.selectedEntry)
            #expect(EntryDraft(entry: saved) == EntryDraft(kind: .url, title: "Saved tab", rawContent: url))
        }
    }

    @Test func footerGrowsToFitHintsAtNarrowWidths() throws {
        try withStore { store in
            store.selectFirstEntry()
            @MainActor func footerSize(width: CGFloat, fontSize: CGFloat) throws -> CGSize {
                let footer = MainFooter(store: store, chromeSize: fontSize).frame(width: width)
                let image = ImageRenderer(content: footer).nsImage
                return try #require(image).size
            }
            let wide = try footerSize(width: 1200, fontSize: 14)
            let narrow = try footerSize(width: 500, fontSize: 14)
            let largeText = try footerSize(width: 500, fontSize: 28)
            #expect(narrow.width == 500)
            #expect(narrow.height > wide.height)
            #expect(largeText.width == 500)
            #expect(largeText.height > narrow.height)
        }
    }

    @Test func editingWithSheetsPreservesExistingRowIDs() async throws {
        let (store, cleanup) = try makeStore()
        defer { cleanup() }
        let url = try #require(store.selectedSheet?.sourceURL)
        let source = (1...8).map { section in
            let entries = (1...8).map { number in
                "### Task \(number)\nText with **emphasis** and {{variables}}.\n\n| A | B |\n| --- | --- |\n| one | two |"
            }
            return (["## Section \(section)"] + entries).joined(separator: "\n")
        }.joined(separator: "\n")
        try source.write(to: url, atomically: true, encoding: .utf8)
        store.reload()
        _ = NSApplication.shared
        let delegate = AppDelegate(store: store)
        delegate.configurePanel()
        let panel = try #require(delegate.panel)
        panel.alphaValue = 0
        panel.setContentSize(NSSize(width: 780, height: 650))
        panel.makeKeyAndOrderFront(nil)
        defer { panel.orderOut(nil) }
        @MainActor func waitForSheet(_ visible: Bool) async throws {
            let deadline = ContinuousClock.now + .seconds(2)
            while (panel.attachedSheet != nil) != visible, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            #expect((panel.attachedSheet != nil) == visible)
        }
        store.selectFirstEntry()
        let originalIDs = store.visibleItems.map(\.id)
        #expect(Set(originalIDs).count == originalIDs.count)
        for _ in 0..<3 {
            store.beginNewEntry()
            try await waitForSheet(true)
            store.entryForm?.draft = .init(kind: .note, title: "Inserted", rawContent: "Edit")
            store.saveEntryForm()
            try await waitForSheet(false)
            let inserted = try #require(store.selectedItem)
            #expect(inserted.entry?.title == "Inserted")
            #expect(store.visibleItems.map(\.id).filter { $0 != inserted.id } == originalIDs)
            store.requestEntryRemoval()
            try await waitForSheet(true)
            store.removeEntry(try #require(store.pendingEntryRemoval))
            try await waitForSheet(false)
            #expect(store.visibleItems.map(\.id) == originalIDs)
            store.selectFirstEntry()
        }
    }

    @Test func listRevealsSelectionAfterAddingAndRemovingAnEntry() async throws {
        let (store, cleanup) = try makeStore()
        defer { cleanup() }
        let url = try #require(store.selectedSheet?.sourceURL)
        let notes = (1...40).map { "### Note \($0)\nBody \($0)" }.joined(separator: "\n\n")
        try notes.write(to: url, atomically: true, encoding: .utf8)
        store.reload()

        _ = NSApplication.shared
        let delegate = AppDelegate(store: store)
        delegate.configurePanel()
        let panel = try #require(delegate.panel)
        panel.alphaValue = 0
        panel.setContentSize(NSSize(width: 640, height: 350))
        panel.orderBack(nil)
        defer { panel.orderOut(nil) }

        @MainActor func selectedRowIsVisible() async -> Bool {
            let deadline = ContinuousClock.now + .seconds(2)
            repeat {
                if let scrollView = store.selectedRowAnchorView?.enclosingScrollView,
                   let table = scrollView.documentView as? NSTableView,
                   let index = store.visibleItems.firstIndex(where: { $0.id == store.selectedItemID }),
                   table.numberOfRows == store.visibleItems.count,
                   scrollView.documentVisibleRect.intersects(table.rect(ofRow: index)) {
                    return true
                }
                try? await Task.sleep(for: .milliseconds(10))
            } while ContinuousClock.now < deadline
            return false
        }
        #expect(await selectedRowIsVisible())
        store.beginNewEntry()
        store.entryForm?.draft = .init(kind: .note, title: "Last", rawContent: "New note")
        store.saveEntryForm()
        #expect(store.selectedEntry?.title == "Last")
        #expect(await selectedRowIsVisible())

        store.requestEntryRemoval()
        store.removeEntry(try #require(store.pendingEntryRemoval))
        #expect(store.selectedEntry?.title == "Note 40")
        #expect(await selectedRowIsVisible())
    }

    @Test func addEntryShortcutsOpenHelpAndNavigateFields() async throws {
        let (store, cleanup) = try makeStore()
        defer { cleanup() }
        _ = NSApplication.shared
        let delegate = AppDelegate(store: store)
        delegate.configurePanel()
        let panel = try #require(delegate.panel)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        defer { panel.orderOut(nil) }
        store.beginNewEntry()
        let form = try #require(store.entryForm)
        form.draft = .init(
            kind: .command, title: "Title", rawContent: "Command",
            rawDescription: "Description", language: "Language"
        )

        // Presentation and initial focus are asynchronous.
        let deadline = ContinuousClock.now + .seconds(2)
        while ((panel.attachedSheet ?? panel).firstResponder as? NSTextView)?.string != "Title",
              ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        let window = panel.attachedSheet ?? panel
        let windowNumber = window.windowNumber

        let helpShortcut = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
            windowNumber: windowNumber, context: nil, characters: "m", charactersIgnoringModifiers: "m",
            isARepeat: false, keyCode: 46
        ))
        #expect(window.performKeyEquivalent(with: helpShortcut))
        let presentationDeadline = ContinuousClock.now + .seconds(2)
        while !form.isMarkdownHelpPresented, ContinuousClock.now < presentationDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(form.isMarkdownHelpPresented)
        window.contentView?.layoutSubtreeIfNeeded()
        let done = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r",
            isARepeat: false, keyCode: 36
        ))
        #expect(window.performKeyEquivalent(with: done))
        let dismissalDeadline = ContinuousClock.now + .seconds(2)
        while form.isMarkdownHelpPresented || (window.firstResponder as? NSTextView)?.string != "Title",
              ContinuousClock.now < dismissalDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(!form.isMarkdownHelpPresented)
        #expect(store.entryForm === form)
        #expect(form.draft.rawContent == "Command")

        @MainActor func press(_ code: UInt16) throws {
            let character = code == 125 ? "\u{F701}" : "\u{F700}"
            let event = try #require(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [.command, .function, .numericPad],
                timestamp: 0, windowNumber: windowNumber, context: nil, characters: character,
                charactersIgnoringModifiers: character, isARepeat: false, keyCode: code
            ))
            #expect(delegate.handleKeyEvent(event) == nil)
        }
        @MainActor func focusedText() -> String? {
            (window.firstResponder as? NSTextView)?.string
        }
        #expect(focusedText() == "Title")
        @MainActor func focusPicker(_ label: String, with code: UInt16) throws -> FocusablePopUpButton {
            try press(code)
            let button = try #require(window.firstResponder as? FocusablePopUpButton)
            #expect(button.accessibilityLabel() == label)
            return button
        }
        let type = try focusPicker("Type", with: 126)
        _ = try focusPicker("Section", with: 126)
        _ = try focusPicker("Sheet", with: 126)
        _ = try focusPicker("Section", with: 125)
        _ = try focusPicker("Type", with: 125)
        #expect(type.titleOfSelectedItem == "Command")
        type.selectItem(withTitle: "URL")
        #expect(type.sendAction(type.action, to: type.target))
        #expect(form.draft.kind == .url)
        type.selectItem(withTitle: "Command")
        #expect(type.sendAction(type.action, to: type.target))
        try press(125)
        #expect(focusedText() == "Title")
        try press(125)
        #expect(focusedText() == "Command")
        try press(125)
        #expect(focusedText() == "Language")
        try press(125)
        #expect(focusedText() == "Description")
        try press(126)
        #expect(focusedText() == "Language")
        try press(126)
        #expect(focusedText() == "Command")
        let originalFile = try Data(contentsOf: form.sheetURL)
        let escape = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: windowNumber, context: nil, characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}",
            isARepeat: false, keyCode: 53
        ))
        if let event = delegate.handleKeyEvent(escape) { window.sendEvent(event) }
        #expect(store.entryForm == nil)
        #expect(panel.isVisible)
        #expect(try Data(contentsOf: form.sheetURL) == originalFile)
        // Escape clears the form immediately. AppKit still needs the panel until dismissal finishes.
        let deadlineAfterCancel = ContinuousClock.now + .seconds(2)
        while panel.attachedSheet != nil, ContinuousClock.now < deadlineAfterCancel {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(panel.attachedSheet == nil)
    }

    @Test func commandReturnSavesFromMultilineAddEntryField() async throws {
        let (store, cleanup) = try makeStore()
        defer { cleanup() }
        _ = NSApplication.shared
        let delegate = AppDelegate(store: store)
        delegate.configurePanel()
        let panel = try #require(delegate.panel)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        defer { panel.orderOut(nil) }
        store.beginNewEntry()
        let form = try #require(store.entryForm)
        form.draft = .init(kind: .note, title: "Two lines", rawContent: "First")
        let deadline = ContinuousClock.now + .seconds(2)
        while (panel.attachedSheet?.firstResponder as? NSTextView)?.string != "Two lines", ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        let window = try #require(panel.attachedSheet)
        func key(_ code: UInt16, _ text: String, _ modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
            try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                                          windowNumber: window.windowNumber, context: nil, characters: text,
                                          charactersIgnoringModifiers: text, isARepeat: false, keyCode: code))
        }
        #expect(delegate.handleKeyEvent(try key(125, "\u{F701}", [.command, .function, .numericPad])) == nil)
        let editor = try #require(window.firstResponder as? NSTextView)
        #expect(editor.string == "First")
        editor.setSelectedRange(NSRange(location: 5, length: 0))
        window.sendEvent(try key(36, "\r"))
        #expect(editor.string == "First\n")
        editor.insertText("Second", replacementRange: editor.selectedRange())
        #expect(store.entryForm === form)
        #expect(window.performKeyEquivalent(with: try key(36, "\r", .command)))
        let dismissalDeadline = ContinuousClock.now + .seconds(2)
        while panel.attachedSheet != nil, ContinuousClock.now < dismissalDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(store.entryForm == nil)
        #expect(store.selectedEntry.map(EntryDraft.init(entry:))?.rawContent == "First\nSecond")
    }

    @Test func returnAndKeypadEnterRequestTheNativePickerMenu() throws {
        _ = NSApplication.shared
        let picker = PickerClickProbe()
        for (code, text, modifiers): (UInt16, String, NSEvent.ModifierFlags) in [
            (36, "\r", []), (76, "\u{3}", .numericPad)
        ] {
            let event = try #require(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                windowNumber: 0, context: nil, characters: text, charactersIgnoringModifiers: text,
                isARepeat: false, keyCode: code
            ))
            let before = picker.clickCount
            picker.keyDown(with: event)
            #expect(picker.clickCount == before + 1)
        }
    }

    @Test func moreMenuKeyboardNavigationWrapsAndSkipsUnavailableItems() throws {
        try withStore { store in
            _ = NSApplication.shared
            let delegate = AppDelegate(store: store)
            delegate.configurePanel()
            let panel = try #require(delegate.panel)
            panel.alphaValue = 0
            panel.orderBack(nil)
            defer { panel.orderOut(nil) }

            @MainActor func press(_ code: UInt16, _ flags: NSEvent.ModifierFlags = [], text: String = "") throws {
                let event = try #require(NSEvent.keyEvent(
                    with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                    windowNumber: panel.windowNumber, context: nil, characters: text,
                    charactersIgnoringModifiers: text, isARepeat: false, keyCode: code
                ))
                #expect(delegate.handleKeyEvent(event) == nil)
            }

            let options = delegate.moreOptions
            let entryIndex = store.selectedItemIndex
            let unrelatedKey = try #require(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, characters: "\t", charactersIgnoringModifiers: "\t",
                isARepeat: false, keyCode: 48
            ))
            #expect(delegate.handleKeyEvent(unrelatedKey) === unrelatedKey)
            #expect(store.selectedItemIndex == entryIndex)
            try press(46, [.command, .shift], text: "M")
            #expect(options.highlightedItem?.title == "Add Sheet Entry")
            try press(126) // Up from first
            #expect(options.highlightedItem?.title == "Quit DittoBar")
            try press(48) // Tab from last
            #expect(options.highlightedItem?.title == "Add Sheet Entry")
            try press(48)
            #expect(options.highlightedItem?.title == "Edit Selected Entry")
            try press(48)
            #expect(options.highlightedItem?.title == "Remove Selected Entry")
            try press(48) // Skip the separator
            #expect(options.highlightedItem?.title == "New Cheat Sheet in Editor")
            try press(48, .shift)
            #expect(options.highlightedItem?.title == "Remove Selected Entry")
            try press(48, .shift)
            #expect(options.highlightedItem?.title == "Edit Selected Entry")
            try press(48, .shift)
            #expect(options.highlightedItem?.title == "Add Sheet Entry")
            try press(48, .shift)
            #expect(options.highlightedItem?.title == "Quit DittoBar")
            try press(53)
            #expect(options.highlightedItem == nil)
            #expect(panel.isVisible)
            #expect(store.selectedItemIndex == entryIndex)

            store.selectedSheetIndex = store.sheets.count
            options.open()
            #expect(options.highlightedItem?.title == "New Cheat Sheet in Editor")
            try press(48)
            #expect(options.highlightedItem?.title == "Open Cheat Sheets Folder")
            try press(48, .shift)
            try press(48, .shift)
            #expect(options.highlightedItem?.title == "Quit DittoBar")
            try press(126)
            try press(36)
            #expect(options.highlightedItem == nil)
            #expect(store.isSettingsPresented)
        }
    }

    @Test func editSelectedSearchResultFromMenuAndShortcut() async throws {
        let (store, cleanup) = try makeStore()
        defer { cleanup() }
        _ = NSApplication.shared
        let delegate = AppDelegate(store: store)
        delegate.configurePanel()
        let panel = try #require(delegate.panel)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        defer { panel.orderOut(nil) }
        store.query = "Later body"
        let sheet = try #require(store.selectedSheet)
        let menu = delegate.moreOptions
        let editItem = try #require(menu.menu.item(withTitle: "Edit Selected Entry"))
        #expect(editItem.keyEquivalent == "=")
        #expect(editItem.keyEquivalentModifierMask == .command)
        menu.choose(editItem)
        let form = try #require(store.entryForm)
        #expect(form.draft.rawContent == "Later body.")
        #expect(form.section == .existing(try #require(sheet.items.compactMap(\.section).last)))
        form.draft.title = "Discarded"
        store.cancelEntryForm()
        #expect(try String(contentsOf: sheet.sourceURL, encoding: .utf8) == Self.source)

        let shortcut = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
            windowNumber: panel.windowNumber, context: nil, characters: "=", charactersIgnoringModifiers: "=",
            isARepeat: false, keyCode: 24
        ))
        #expect(delegate.handleKeyEvent(shortcut) == nil)
        let edit = try #require(store.entryForm)
        edit.draft = .init(kind: .command, title: "Print", rawContent: "echo {{name}}", rawDescription: "**Output**")
        let deadline = ContinuousClock.now + .seconds(2)
        while panel.attachedSheet == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        let window = try #require(panel.attachedSheet)
        func picker(_ label: String, under view: NSView) -> NSPopUpButton? {
            if let button = view as? NSPopUpButton, button.accessibilityLabel() == label { return button }
            return view.subviews.lazy.compactMap { picker(label, under: $0) }.first
        }
        let content = try #require(window.contentView)
        content.layoutSubtreeIfNeeded()
        let sheetPicker = try #require(picker("Sheet", under: content))
        #expect(sheetPicker.titleOfSelectedItem == sheet.title)
        let sectionPicker = try #require(picker("Section", under: content))
        #expect(sectionPicker.titleOfSelectedItem == "Later")
        sectionPicker.selectItem(withTitle: "Tools")
        #expect(sectionPicker.sendAction(sectionPicker.action, to: sectionPicker.target))
        let save = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r",
            isARepeat: false, keyCode: 36
        ))
        #expect(window.performKeyEquivalent(with: save))
        let dismissalDeadline = ContinuousClock.now + .seconds(2)
        while panel.attachedSheet != nil, ContinuousClock.now < dismissalDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(panel.attachedSheet == nil)
        #expect(store.entryForm == nil)
        #expect(store.selectedSheet?.items.map(\.entry?.title) == ["First", nil, "Existing", "Print", nil])
        let saved = try #require(store.selectedEntry)
        #expect(EntryDraft(entry: saved) == edit.draft)
        #expect(saved.variables.map(\.name) == ["name"])
    }

    @Test(arguments: [false, true]) func editMovesEntryToAnotherSheetAndSelectsIt(createSection: Bool) throws {
        try withStore { store in
            store.query = "Later body"
            let source = try #require(store.selectedSheet)
            let destination = try #require(store.sheets.last)
            store.editSelectedEntry()
            let form = try #require(store.entryForm)
            form.sheetURL = destination.sourceURL
            #expect(form.section == .unsectioned)
            if createSection {
                form.section = .newSection
                form.newSectionName = "Moved"
            }
            form.draft.title = "Same"
            form.draft.rawContent = "Moved {{value}}."
            store.saveEntryForm()
            #expect(store.entryForm == nil)
            #expect(store.selectedSheet?.sourceURL == destination.sourceURL)
            let saved = try #require(store.selectedEntry)
            #expect(EntryDraft(entry: saved) == form.draft)
            let items = try #require(store.selectedSheet?.items)
            #expect(items.compactMap(\.entry).count == destination.items.compactMap(\.entry).count + 1)
            let index = try #require(items.firstIndex(of: .entry(saved)))
            #expect(items[..<index].compactMap(\.section).last?.title == (createSection ? "Moved" : nil))
            #expect(try String(contentsOf: source.sourceURL, encoding: .utf8) ==
                    Self.source.replacingOccurrences(of: "### Existing\nLater body.", with: ""))
        }
    }

    @Test func invalidMoveLeavesBothSheetsIntactAndAllowsRetry() throws {
        try withStore { store in
            let source = try #require(store.selectedSheet)
            let destination = try #require(store.sheets.last)
            store.editSelectedEntry()
            let form = try #require(store.entryForm)
            form.sheetURL = destination.sourceURL
            form.section = .existing(try #require(destination.items.compactMap(\.section).first))
            let latest = "## Renamed\n### Other\nExternal edit."
            try latest.write(to: destination.sourceURL, atomically: true, encoding: .utf8)
            store.saveEntryForm()
            #expect(store.entryForm === form)
            #expect(form.errorMessage == SheetFiles.InsertionError.missingSection.localizedDescription)
            #expect(try String(contentsOf: source.sourceURL, encoding: .utf8) == Self.source)
            #expect(try String(contentsOf: destination.sourceURL, encoding: .utf8) == latest)
            form.section = .unsectioned
            store.saveEntryForm()
            #expect(store.entryForm == nil)
            #expect(store.selectedEntry?.title == form.draft.title)
            #expect(try String(contentsOf: destination.sourceURL, encoding: .utf8).hasSuffix(latest))
        }
    }

    @Test func failedEditRetainsDraftAndProtectsExternalChanges() throws {
        try withStore { store in
            store.selectFirstEntry()
            store.editSelectedEntry()
            let form = try #require(store.entryForm)
            form.draft.rawContent = ""
            store.saveEntryForm()
            #expect(form.errorMessage == EntryDraft.ValidationError.missingContent.localizedDescription)
            #expect(try String(contentsOf: form.sheetURL, encoding: .utf8) == Self.source)
            let external = Self.source + "\n### External\nNew text."
            try external.write(to: form.sheetURL, atomically: true, encoding: .utf8)
            store.reload()
            form.draft.rawContent = "My edit"
            store.saveEntryForm()
            #expect(store.entryForm === form)
            #expect(form.draft.rawContent == "My edit")
            #expect(form.errorMessage == SheetFiles.EntryChangeError.sheetChanged.localizedDescription)
            #expect(try String(contentsOf: form.sheetURL, encoding: .utf8) == external)
        }
    }

    @Test func markdownRulesMenuSectionPrecedesSettings() throws {
        try withStore { store in
            _ = NSApplication.shared
            let options = MoreOptionsMenu(store: store)
            let menu = options.menu
            let rules = try #require(menu.item(withTitle: "Display Markdown Rules"))
            let index = menu.index(of: rules)
            #expect(menu.item(at: index - 1)?.isSeparatorItem == true)
            #expect(menu.item(at: index + 1)?.isSeparatorItem == true)
            #expect(menu.item(at: index + 2)?.title == "Settings…")
            menu.performActionForItem(at: index)
            #expect(store.isMarkdownRulesPresented)
            #expect(store.isPanelSheetPresented)
        }
    }

    @Test func keyboardAndMenuConfirmRemovalOfTheSelectedSearchResult() async throws {
        let (store, cleanup) = try makeStore()
        defer { cleanup() }
        _ = NSApplication.shared
        let delegate = AppDelegate(store: store)
        delegate.configurePanel()
        let panel = try #require(delegate.panel)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        defer { panel.orderOut(nil) }
        store.query = "Later body"
        let sheet = try #require(store.selectedSheet)
        let selected = try #require(store.selectedEntry)
        let number = panel.windowNumber
        let shortcut = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
            windowNumber: number, context: nil, characters: "-", charactersIgnoringModifiers: "-",
            isARepeat: false, keyCode: 27
        ))
        #expect(delegate.handleKeyEvent(shortcut) == nil)
        #expect(store.pendingEntryRemoval?.entry == selected)
        #expect(try String(contentsOf: sheet.sourceURL, encoding: .utf8) == Self.source)

        @MainActor func pressConfirmationKey(_ code: UInt16, character: String) async throws {
            let deadline = ContinuousClock.now + .seconds(2)
            while panel.attachedSheet == nil, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            let confirmation = try #require(panel.attachedSheet)
            let confirmationNumber = confirmation.windowNumber
            let key = try #require(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: confirmationNumber, context: nil, characters: character,
                charactersIgnoringModifiers: character, isARepeat: false, keyCode: code
            ))
            #expect(delegate.handleKeyEvent(key) === key)
            if !confirmation.performKeyEquivalent(with: key) { confirmation.sendEvent(key) }
            while panel.attachedSheet != nil, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            #expect(panel.attachedSheet == nil)
        }

        try await pressConfirmationKey(53, character: "\u{1B}") // Escape
        #expect(store.pendingEntryRemoval == nil)
        #expect(try String(contentsOf: sheet.sourceURL, encoding: .utf8) == Self.source)
        let options = delegate.moreOptions
        let action = try #require(options.menu.item(withTitle: "Remove Selected Entry"))
        #expect(action.keyEquivalent == "-")
        options.choose(action)
        try await pressConfirmationKey(36, character: "\r") // Return
        #expect(try String(contentsOf: sheet.sourceURL, encoding: .utf8) == Self.source.replacingOccurrences(
            of: "### Existing\nLater body.", with: ""
        ))
        #expect(store.query == "Later body")
        #expect(store.selectedEntry == nil)
        #expect(!options.validateMenuItem(action))
    }

    @Test func moreOptionsOpensDraftAndSavesMultilineCommand() throws {
        try withStore { store in
            let destination = try #require(store.selectedSheet?.sourceURL)
            let options = MoreOptionsMenu(store: store)
            let menu = options.menu
            let action = try #require(menu.item(withTitle: "Add Sheet Entry"))
            #expect(action.keyEquivalent == "+")
            #expect(action.keyEquivalentModifierMask == .command)
            #expect(options.validateMenuItem(action))
            #expect(menu.item(at: menu.index(of: action) + 1)?.title == "Edit Selected Entry")
            #expect(menu.item(at: menu.index(of: action) + 2)?.title == "Remove Selected Entry")
            _ = NSApplication.shared
            menu.performActionForItem(at: menu.index(of: action))
            let form = try #require(store.entryForm)
            #expect(form.sheetURL == destination)
            store.entryForm?.draft = .init(
                kind: .command, title: "Diff", rawContent: "git fetch\ngit diff {{branch=main}}", language: "sh"
            )
            store.saveEntryForm()
            #expect(store.entryForm == nil)
            guard case .command(let entry) = store.selectedEntry else {
                Issue.record("Expected the saved command to be selected")
                return
            }
            #expect(entry.rawCommand == "git fetch\ngit diff {{branch=main}}")
            #expect(try String(contentsOf: destination, encoding: .utf8).contains(entry.rawCommand))
        }
    }

    @Test func commandPlusOpensOneDraftFromSearchAndPreservesTextInput() throws {
        try withStore { store in
            _ = NSApplication.shared
            let delegate = AppDelegate(store: store)
            delegate.configurePanel()
            let panel = try #require(delegate.panel)
            panel.alphaValue = 0
            panel.orderBack(nil)
            defer { panel.orderOut(nil) }

            let windowNumber = panel.windowNumber
            func plus(_ flags: NSEvent.ModifierFlags, repeat isRepeat: Bool = false) throws -> NSEvent {
                try #require(NSEvent.keyEvent(
                    with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                    windowNumber: windowNumber, context: nil,
                    characters: "+", charactersIgnoringModifiers: "+", isARepeat: isRepeat,
                    keyCode: flags.contains(.numericPad) ? 69 : 24
                ))
            }

            let key = try plus(.shift)
            let search = NSSearchField(string: "C")
            panel.contentView?.addSubview(search)
            #expect(panel.makeFirstResponder(search))
            let editor = try #require(search.currentEditor() as? NSTextView)
            let selection = store.selectedItemIndex
            let selectText = try #require(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [.shift, .numericPad, .function], timestamp: 0,
                windowNumber: windowNumber, context: nil, characters: "\u{F701}", charactersIgnoringModifiers: "\u{F701}",
                isARepeat: false, keyCode: 125
            ))
            #expect(delegate.handleKeyEvent(selectText) === selectText)
            #expect(store.selectedItemIndex == selection)
            editor.setSelectedRange(NSRange(location: 1, length: 0))
            for _ in 0..<2 {
                let passed = try #require(delegate.handleKeyEvent(key))
                editor.insertText(passed.characters ?? "", replacementRange: editor.selectedRange())
            }
            #expect(search.stringValue == "C++")
            #expect(store.entryForm == nil)

            let shortcut = try plus([.command, .shift])
            let modified = try plus([.command, .control])
            #expect(delegate.handleKeyEvent(modified) === modified)
            #expect(delegate.handleKeyEvent(try plus([.command, .shift], repeat: true)) == nil)
            #expect(store.entryForm == nil)
            #expect(delegate.handleKeyEvent(shortcut) == nil)
            #expect(search.stringValue == "C++")
            let form = try #require(store.entryForm)
            form.draft.title = "Language"
            form.draft.rawContent = "C"
            for _ in 0..<2 {
                let passed = try #require(delegate.handleKeyEvent(key))
                form.draft.rawContent += passed.characters ?? ""
            }
            #expect(store.entryForm === form)
            store.saveEntryForm()

            delegate.closePanel(restoringFocus: false)
            #expect(delegate.handleKeyEvent(shortcut) === shortcut)
            store.reload()
            panel.orderBack(nil)
            guard case .note(let saved) = store.selectedEntry else {
                Issue.record("Expected the saved note after reopening")
                return
            }
            #expect(saved.metadata.title == "Language")
            #expect(saved.rawContent == "C++")
            panel.makeFirstResponder(nil)
            #expect(delegate.handleKeyEvent(key) === key)
            #expect(delegate.handleKeyEvent(try plus([.command, .numericPad])) == nil)
            #expect(store.entryForm != nil)
            store.cancelEntryForm()
        }
    }

    @Test(arguments: [true, false])
    func presentedFormSurvivesSaveAndCancel(save: Bool) throws {
        try withStore { store in
            store.beginNewEntry()
            let form = try #require(store.entryForm)
            let view = EntryFormView(store: store, form: form)
            let host = NSHostingView(rootView: view)
            host.setFrameSize(host.fittingSize)
            let content = view.$form.draft.rawContent
            let note = "This is a test **bold**\n\n[test link](www.google.com)"
            form.draft.title = "Test Note 1"
            content.wrappedValue = note
            host.layoutSubtreeIfNeeded()

            if save { store.saveEntryForm() } else { store.cancelEntryForm() }
            #expect(store.entryForm == nil)
            // The closing sheet can still lay out controls and read or write field bindings.
            host.needsLayout = true
            host.layoutSubtreeIfNeeded()
            #expect(content.wrappedValue == note)
            store.beginNewEntry()
            content.wrappedValue = "Late edit from the closing sheet"
            #expect(store.entryForm?.draft.rawContent == "")
            if save {
                let entry = try #require(store.selectedEntry)
                guard case .note(let saved) = entry else {
                    Issue.record("Expected the saved note")
                    return
                }
                #expect(saved.rawContent == note)
            }
        }
    }

    @Test func cancelKeepsTheFileAndPanelSelection() throws {
        try withStore { store in
            let original = try #require(store.selectedSheet)
            let initialSelection = store.selectedItem
            store.beginNewEntry()
            #expect(store.entryForm?.sheetURL == original.sourceURL)
            #expect(store.entryForm?.section == .unsectioned)
            store.entryForm?.draft.title = "Unsaved"
            store.beginNewEntry()
            #expect(store.entryForm?.draft.title == "Unsaved")
            store.cancelEntryForm()
            #expect(store.entryForm == nil)
            #expect(store.selectedItem == initialSelection)
            #expect(try String(contentsOf: original.sourceURL, encoding: .utf8) == Self.source)
        }
    }

    @Test func changingDestinationResetsSectionAndSelectsNewUnsectionedEntry() throws {
        try withStore { store in
            store.query = "Existing"
            let previous = try #require(store.selectedSheet)
            let section = try #require(previous.items.compactMap(\.section).first)
            store.beginNewEntry()
            #expect(store.entryForm?.section == .existing(section))
            let destination = store.sheets[1]
            store.entryForm?.sheetURL = destination.sourceURL
            #expect(store.entryForm?.section == .unsectioned)
            #expect(store.selectedSheet == previous)
            store.entryForm?.draft = .init(kind: .note, title: "Same", rawContent: "Inserted")
            store.saveEntryForm()

            #expect(store.selectedSheet?.sourceURL == destination.sourceURL)
            #expect(store.query.isEmpty)
            #expect(store.selectedItem == store.selectedSheet?.items[1])
            guard case .note(let note) = store.selectedEntry else {
                Issue.record("Expected the newly added note")
                return
            }
            #expect(note.rawContent == "Inserted")
            #expect(store.entryForm == nil)
        }
    }

    @Test(arguments: ["", "Existing", "missing"])
    func saveRevealsInsertedDuplicateInCollapsedSection(query: String) throws {
        try withStore { store in
            let sheet = try #require(store.selectedSheet)
            let section = try #require(sheet.items.compactMap(\.section).first)
            store.toggleSection(section)
            store.beginNewEntry()
            #expect(store.entryForm?.section == .existing(section))
            store.query = query
            if query == "Existing" { store.toggleSection(section) }
            store.entryForm?.draft = .init(kind: .note, title: "Existing", rawContent: "New body")
            store.saveEntryForm()
            #expect(store.entryForm == nil)
            #expect(store.query == (query == "missing" ? "" : query))
            #expect(!store.isCollapsed(section))
            #expect(store.selectedItem == store.selectedSheet?.items[3])
            guard case .note(let note) = store.selectedEntry else {
                Issue.record("Expected the newly added duplicate")
                return
            }
            #expect(note.rawContent == "New body")
            // A filesystem notification can cause a second reload after saving.
            store.reload()
            #expect(store.selectedEntry == .note(note))
        }
    }

    @Test func newSectionAndEntryAreSavedTogetherInTheChosenSheet() throws {
        try withStore { store in
            let original = try #require(store.selectedSheet)
            let destination = store.sheets[1]
            store.beginNewEntry()
            let form = try #require(store.entryForm)
            form.section = .newSection
            form.newSectionName = "Old destination"
            form.sheetURL = destination.sourceURL
            #expect(form.section == .unsectioned)
            #expect(form.newSectionName.isEmpty)
            form.section = .newSection
            form.newSectionName = "  Other  "
            form.draft = .init(kind: .note, title: "Same", rawContent: "In the new section")
            store.saveEntryForm()

            #expect(store.entryForm == nil)
            let saved = try #require(store.selectedSheet)
            #expect(saved.sourceURL == destination.sourceURL)
            // Repeated titles are valid in the sheet format. A new section gets its own heading.
            #expect(saved.items.compactMap(\.section).map(\.title) == ["Other", "Other"])
            #expect(store.selectedItem == saved.items.last)
            #expect(try String(contentsOf: original.sourceURL, encoding: .utf8) == Self.source)
            let text = try String(contentsOf: destination.sourceURL, encoding: .utf8)
            #expect(text.hasSuffix("## Other\n\n### Same\n\nIn the new section"))
        }
    }

    @Test func invalidOrCancelledNewSectionLeavesTheSheetIntact() throws {
        try withStore { store in
            store.beginNewEntry()
            let form = try #require(store.entryForm)
            form.section = .newSection
            form.draft = .init(kind: .note, title: "First", rawContent: "Keep draft")
            for invalidName in ["  ", "One\n## Two"] {
                form.newSectionName = invalidName
                store.saveEntryForm()
                #expect(form.errorMessage == SheetFiles.InsertionError.invalidSectionName.localizedDescription)
                #expect(store.entryForm === form)
            }
            form.newSectionName = "Valid name"
            form.draft.title = ""
            store.saveEntryForm()
            #expect(form.errorMessage == EntryDraft.ValidationError.missingTitle.localizedDescription)
            store.cancelEntryForm()
            #expect(store.entryForm == nil)
            #expect(try String(contentsOf: form.sheetURL, encoding: .utf8) == Self.source)
        }
    }

    @Test func failedSaveKeepsDraftForRetry() throws {
        try withStore { store in
            store.query = "Existing"
            store.beginNewEntry()
            let url = try #require(store.entryForm?.sheetURL)
            try "# Replaced".write(to: url, atomically: true, encoding: .utf8)
            store.entryForm?.draft = .init(kind: .note, title: "Retry", rawContent: "My text")
            store.saveEntryForm()
            #expect(store.entryForm?.errorMessage == SheetFiles.InsertionError.missingSection.localizedDescription)
            #expect(store.entryForm?.draft.rawContent == "My text")
            #expect(store.query == "Existing")
            #expect(try String(contentsOf: url, encoding: .utf8) == "# Replaced")

            store.entryForm?.section = .unsectioned
            store.saveEntryForm()
            store.saveEntryForm()
            #expect(store.entryForm == nil)
            #expect(store.selectedEntry?.title == "Retry")
            #expect(store.selectedSheet?.items.count == 1)
        }
    }

    private static let source = """
    # Work
    ### First
    Outside any section.
    ## Tools
    ### Existing
    Original body.
    ## Later
    ### Existing
    Later body.
    """

    private func withStore(_ body: (CheatSheetStore) throws -> Void) throws {
        let (store, cleanup) = try makeStore()
        defer { cleanup() }
        try body(store)
    }

    private func makeStore() throws -> (CheatSheetStore, () -> Void) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let suite = "CheatSheetStoreNewEntryTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let cleanup = {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: folder)
        }
        defaults.set(folder.path, forKey: CheatSheetStore.sheetsDirectoryPathKey)
        try Self.source.write(to: folder.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)
        try "### Same\nBefore.\n## Other\n### Same\nAfter.".write(
            to: folder.appendingPathComponent("b.md"), atomically: true, encoding: .utf8
        )
        return (CheatSheetStore(defaults: defaults), cleanup)
    }
}

// Cancelling a real pop-up menu inside Swift Testing can stop the runner's main run loop.
@MainActor private final class PickerClickProbe: FocusablePopUpButton {
    private(set) var clickCount = 0

    override func performClick(_ sender: Any?) {
        clickCount += 1
    }
}
