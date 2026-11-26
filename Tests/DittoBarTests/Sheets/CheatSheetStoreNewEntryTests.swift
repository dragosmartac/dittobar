import AppKit
import SwiftUI
import Testing
@testable import DittoBar

@MainActor
struct CheatSheetStoreNewEntryTests {
    @Test func moreOptionsOpensDraftAndSavesMultilineCommand() throws {
        try withStore { store in
            let destination = try #require(store.selectedSheet?.sourceURL)
            let coordinator = MoreOptionsButton.Coordinator(store: store)
            let menu = coordinator.menu
            let action = try #require(menu.item(withTitle: "Add Sheet Entry"))
            #expect(action.keyEquivalent == "+")
            #expect(action.keyEquivalentModifierMask == .command)
            #expect(coordinator.validateMenuItem(action))
            #expect(menu.item(at: menu.index(of: action) + 1)?.isSeparatorItem == true)
            _ = NSApplication.shared
            menu.performActionForItem(at: menu.index(of: action))
            let form = try #require(store.newEntryForm)
            #expect(form.sheetURL == destination)
            store.newEntryForm?.draft = .init(
                kind: .command, title: "Diff", rawContent: "git fetch\ngit diff {{branch=main}}", language: "sh"
            )
            store.saveNewEntry()
            #expect(store.newEntryForm == nil)
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
            editor.setSelectedRange(NSRange(location: 1, length: 0))
            for _ in 0..<2 {
                let passed = try #require(delegate.handleKeyEvent(key))
                editor.insertText(passed.characters ?? "", replacementRange: editor.selectedRange())
            }
            #expect(search.stringValue == "C++")
            #expect(store.newEntryForm == nil)

            let shortcut = try plus([.command, .shift])
            let modified = try plus([.command, .control])
            #expect(delegate.handleKeyEvent(modified) === modified)
            #expect(delegate.handleKeyEvent(try plus([.command, .shift], repeat: true)) == nil)
            #expect(store.newEntryForm == nil)
            #expect(delegate.handleKeyEvent(shortcut) == nil)
            #expect(search.stringValue == "C++")
            let form = try #require(store.newEntryForm)
            form.draft.title = "Language"
            form.draft.rawContent = "C"
            for _ in 0..<2 {
                let passed = try #require(delegate.handleKeyEvent(key))
                form.draft.rawContent += passed.characters ?? ""
            }
            #expect(store.newEntryForm === form)
            store.saveNewEntry()

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
            #expect(store.newEntryForm != nil)
            store.cancelNewEntry()
        }
    }

    @Test(arguments: [true, false])
    func presentedFormSurvivesSaveAndCancel(save: Bool) throws {
        try withStore { store in
            store.beginNewEntry()
            let form = try #require(store.newEntryForm)
            let view = NewEntryFormView(store: store, form: form)
            let host = NSHostingView(rootView: view)
            host.setFrameSize(host.fittingSize)
            let content = view.$form.draft.rawContent
            let note = "This is a test **bold**\n\n[test link](www.google.com)"
            form.draft.title = "Test Note 1"
            content.wrappedValue = note
            host.layoutSubtreeIfNeeded()

            if save { store.saveNewEntry() } else { store.cancelNewEntry() }
            #expect(store.newEntryForm == nil)
            // The closing sheet can still lay out controls and read or write field bindings.
            host.needsLayout = true
            host.layoutSubtreeIfNeeded()
            #expect(content.wrappedValue == note)
            store.beginNewEntry()
            content.wrappedValue = "Late edit from the closing sheet"
            #expect(store.newEntryForm?.draft.rawContent == "")
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
            #expect(store.newEntryForm?.sheetURL == original.sourceURL)
            #expect(store.newEntryForm?.section == .unsectioned)
            store.newEntryForm?.draft.title = "Unsaved"
            store.beginNewEntry()
            #expect(store.newEntryForm?.draft.title == "Unsaved")
            store.cancelNewEntry()
            #expect(store.newEntryForm == nil)
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
            #expect(store.newEntryForm?.section == .existing(section))
            let destination = store.sheets[1]
            store.newEntryForm?.sheetURL = destination.sourceURL
            #expect(store.newEntryForm?.section == .unsectioned)
            #expect(store.selectedSheet == previous)
            store.newEntryForm?.draft = .init(kind: .note, title: "Same", rawContent: "Inserted")
            store.saveNewEntry()

            #expect(store.selectedSheet?.sourceURL == destination.sourceURL)
            #expect(store.query.isEmpty)
            #expect(store.selectedItem == store.selectedSheet?.items[1])
            guard case .note(let note) = store.selectedEntry else {
                Issue.record("Expected the newly added note")
                return
            }
            #expect(note.rawContent == "Inserted")
            #expect(store.newEntryForm == nil)
        }
    }

    @Test(arguments: ["", "Existing", "missing"])
    func saveRevealsInsertedDuplicateInCollapsedSection(query: String) throws {
        try withStore { store in
            let sheet = try #require(store.selectedSheet)
            let section = try #require(sheet.items.compactMap(\.section).first)
            store.toggleSection(section)
            store.beginNewEntry()
            #expect(store.newEntryForm?.section == .existing(section))
            store.query = query
            if query == "Existing" { store.toggleSection(section) }
            store.newEntryForm?.draft = .init(kind: .note, title: "Existing", rawContent: "New body")
            store.saveNewEntry()
            #expect(store.newEntryForm == nil)
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
            let form = try #require(store.newEntryForm)
            form.section = .newSection
            form.newSectionName = "Old destination"
            form.sheetURL = destination.sourceURL
            #expect(form.section == .unsectioned)
            #expect(form.newSectionName.isEmpty)
            form.section = .newSection
            form.newSectionName = "  Other  "
            form.draft = .init(kind: .note, title: "Same", rawContent: "In the new section")
            store.saveNewEntry()

            #expect(store.newEntryForm == nil)
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
            let form = try #require(store.newEntryForm)
            form.section = .newSection
            form.draft = .init(kind: .note, title: "First", rawContent: "Keep draft")
            for invalidName in ["  ", "One\n## Two"] {
                form.newSectionName = invalidName
                store.saveNewEntry()
                #expect(form.errorMessage == SheetFiles.InsertionError.invalidSectionName.localizedDescription)
                #expect(store.newEntryForm === form)
            }
            form.newSectionName = "Valid name"
            form.draft.title = ""
            store.saveNewEntry()
            #expect(form.errorMessage == NewEntryDraft.ValidationError.missingTitle.localizedDescription)
            store.cancelNewEntry()
            #expect(store.newEntryForm == nil)
            #expect(try String(contentsOf: form.sheetURL, encoding: .utf8) == Self.source)
        }
    }

    @Test func failedSaveKeepsDraftForRetry() throws {
        try withStore { store in
            store.query = "Existing"
            store.beginNewEntry()
            let url = try #require(store.newEntryForm?.sheetURL)
            try "# Replaced".write(to: url, atomically: true, encoding: .utf8)
            store.newEntryForm?.draft = .init(kind: .note, title: "Retry", rawContent: "My text")
            store.saveNewEntry()
            #expect(store.newEntryForm?.errorMessage == SheetFiles.InsertionError.missingSection.localizedDescription)
            #expect(store.newEntryForm?.draft.rawContent == "My text")
            #expect(store.query == "Existing")
            #expect(try String(contentsOf: url, encoding: .utf8) == "# Replaced")

            store.newEntryForm?.section = .unsectioned
            store.saveNewEntry()
            store.saveNewEntry()
            #expect(store.newEntryForm == nil)
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
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let suite = "CheatSheetStoreNewEntryTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: folder)
        }
        defaults.set(folder.path, forKey: CheatSheetStore.sheetsDirectoryPathKey)
        try Self.source.write(to: folder.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)
        try "### Same\nBefore.\n## Other\n### Same\nAfter.".write(
            to: folder.appendingPathComponent("b.md"), atomically: true, encoding: .utf8
        )
        try body(CheatSheetStore(defaults: defaults))
    }
}
