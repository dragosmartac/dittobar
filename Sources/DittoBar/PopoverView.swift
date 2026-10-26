import AppKit
import SwiftUI

private enum PanelStyle {
    static let mutedFill = Color.primary.opacity(0.05)
}

extension Notification.Name {
    static let focusCheatSheetSearch = Notification.Name("focusCheatSheetSearch")
    static let openCheatSheetMoreOptions = Notification.Name("openCheatSheetMoreOptions")
}

struct PopoverView: View {
    @ObservedObject var store: CheatSheetStore
    @FocusState private var searchIsFocused: Bool
    @State private var hoveredItemID: CheatSheetItem.ID?
    @AppStorage(DisplayPreferences.sectionTitleFontSizeKey)
    private var sectionTitleFontSize = DisplayPreferences.defaultSectionTitleFontSize
    @AppStorage(DisplayPreferences.titleFontSizeKey)
    private var titleFontSize = DisplayPreferences.defaultTitleFontSize
    @AppStorage(DisplayPreferences.descriptionFontSizeKey)
    private var descriptionFontSize = DisplayPreferences.defaultDescriptionFontSize
    @AppStorage(DisplayPreferences.noteFontSizeKey)
    private var noteFontSize = DisplayPreferences.defaultNoteFontSize
    @AppStorage(DisplayPreferences.payloadFontSizeKey)
    private var payloadFontSize = DisplayPreferences.defaultPayloadFontSize
    @AppStorage(DisplayPreferences.textFontFamilyKey)
    private var textFontFamily = ""
    @AppStorage(DisplayPreferences.codeFontFamilyKey)
    private var codeFontFamily = ""

    private var fonts: EntryFonts {
        EntryFonts(textFamily: textFontFamily, codeFamily: codeFontFamily)
    }

    /// The header, tabs, and footer scale with the entry title size, so
    /// larger list text does not leave the controls around it looking tiny.
    /// The ratios match the system text styles at the default size.
    private var chromeSize: CGFloat { CGFloat(titleFontSize) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if store.sheets.isEmpty {
                emptyState
            } else {
                entryList
            }

            Divider()
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay {
            // Built only while a form is up, so its @FocusState starts fresh
            // each time instead of carrying focus over from the last entry.
            if store.variableForm != nil {
                VariableFormView(store: store)
            }
        }
        .sheet(isPresented: $store.isSettingsPresented) {
            DisplaySettingsView()
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .alert("New Cheat Sheet", isPresented: $store.isNewSheetPromptPresented) {
            TextField("Name", text: $store.newSheetName)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                store.createNewSheetInEditor(named: store.newSheetName)
            }
            .keyboardShortcut(.defaultAction)
            .disabled(store.newSheetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Enter a name for the Markdown file.")
        }
        .alert(
            "Unable to Complete Action",
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
            // The search field takes the title row: the menu-bar icon already
            // says which app this is, and the list gets the space back.
            HStack(spacing: 10) {
                searchField
                MoreOptionsButton(store: store, symbolSize: chromeSize * 1.15)
                    .frame(width: chromeSize * 1.5, height: chromeSize * 1.5)
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
                            .font(.system(size: chromeSize))
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

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search entries", text: $store.query)
                .textFieldStyle(.plain)
                .focused($searchIsFocused)
                .onChange(of: store.query) {
                    store.selectFirstEntry()
                }
                .onReceive(NotificationCenter.default.publisher(for: .focusCheatSheetSearch)) { _ in
                    searchIsFocused = true
                }
            if !store.query.isEmpty {
                Button {
                    store.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
            Text("⌘F")
                .font(.system(size: chromeSize * 0.8, design: .monospaced))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .font(.system(size: chromeSize))
        .padding(.horizontal, 9)
        .padding(.vertical, 9)
        .background(PanelStyle.mutedFill, in: RoundedRectangle(cornerRadius: 7))
        // Clicking the icon or padding focuses the field too.
        .contentShape(RoundedRectangle(cornerRadius: 7))
        .onTapGesture { searchIsFocused = true }
        // A thin tinted outline instead of the thick system focus ring.
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(
                    searchIsFocused ? Color.accentColor.opacity(0.5) : Color.primary.opacity(0.08),
                    lineWidth: 1
                )
        }
    }

    private var entryList: some View {
        let selectedItemID = store.selectedItemID

        return ScrollViewReader { proxy in
            List(store.visibleItems) { item in
                switch item {
                case .section(let section):
                    SectionHeaderRow(
                        title: section.title,
                        fontSize: CGFloat(sectionTitleFontSize),
                        fonts: fonts
                    )
                    .background(
                        SelectedRowAnchor(
                            store: store,
                            isSelected: item.id == selectedItemID
                        )
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        store.selectItem(item)
                    }
                    .listRowBackground(
                        item.id == selectedItemID
                            ? Color.accentColor.opacity(0.12)
                            : item.id == hoveredItemID ? Color.accentColor.opacity(0.05) : Color.clear
                    )
                    .onHover { hovering in
                        if hovering { hoveredItemID = item.id }
                        else if hoveredItemID == item.id { hoveredItemID = nil }
                    }
                    .contextMenu {
                        ForEach(Array(store.actions(for: section).enumerated()), id: \.offset) { _, action in
                            Button(action.title) {
                                store.perform(action, for: section)
                            }
                        }
                    }

                case .entry(let entry):
                    EntryRow(
                        entry: entry,
                        values: store.effectiveValues(for: entry),
                        titleFontSize: CGFloat(titleFontSize),
                        descriptionFontSize: CGFloat(descriptionFontSize),
                        noteFontSize: CGFloat(noteFontSize),
                        payloadFontSize: CGFloat(payloadFontSize),
                        fonts: fonts,
                        isSelected: item.id == selectedItemID,
                        wasCopied: store.copiedEntryIDs.contains(entry.id),
                        onSelect: { store.selectItem(item) }
                    )
                    .equatable()
                    .background(
                        SelectedRowAnchor(
                            store: store,
                            isSelected: item.id == selectedItemID
                        )
                    )
                    .contentShape(Rectangle())
                    // No double-click action: it would swallow the double-click
                    // that selects a word in the selectable text below.
                    .onTapGesture {
                        store.selectItem(item)
                    }
                    .contextMenu {
                        actionButtons(for: entry)
                    }
                    .listRowBackground(
                        store.copiedEntryIDs.contains(entry.id)
                            ? Color.green.opacity(0.24)
                            : item.id == selectedItemID
                                ? Color.accentColor.opacity(0.12)
                                : item.id == hoveredItemID ? Color.accentColor.opacity(0.05) : Color.clear
                    )
                    .onHover { hovering in
                        if hovering { hoveredItemID = item.id }
                        else if hoveredItemID == item.id { hoveredItemID = nil }
                    }
                    .listRowSeparator(.hidden)
                    .overlay(alignment: .bottom) {
                        Divider()
                            .opacity(0.45)
                            .padding(.leading, 16)
                    }
                }
            }
            .listStyle(.inset)
            .overlay {
                if store.visibleItems.isEmpty {
                    ContentUnavailableView.search(text: store.query)
                }
            }
            .onChange(of: store.selectedItemIndex) { oldIndex, newIndex in
                let source = store.consumeEntrySelectionSource()
                // A clicked row is already under the pointer; scrolling would
                // slide it away.
                guard source != .pointer, let itemID = store.selectedItem?.id else { return }
                let duration = scrollDuration(for: source, rowDistance: abs(newIndex - oldIndex))

                let scroll = {
                    if !animateListScroll(toItemID: itemID, duration: duration) {
                        proxy.scrollTo(itemID, anchor: .center)
                    }
                }

                if duration == 0 {
                    // Jump in the same frame as the highlight moves. Deferred,
                    // the highlight and the jump land in separate frames, and
                    // a held key makes them flicker.
                    scroll()
                } else {
                    // Start the slide once SwiftUI finishes this update.
                    // Started from inside it, the slide loses its first
                    // frames to the rest of the update.
                    DispatchQueue.main.async(execute: scroll)
                }
            }
            .onChange(of: store.query) {
                guard let entry = store.visibleEntries.first else { return }

                // The selected index may already point at the first entry, in
                // which case its onChange handler does not fire. Wait for the filtered rows
                // to be laid out, then center the first result explicitly.
                DispatchQueue.main.async {
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(CheatSheetItem.entry(entry).id, anchor: .center)
                    }
                }
            }
        }
    }

    /// Returns 0 when the scroll should be instant.
    private func scrollDuration(
        for source: CheatSheetStore.EntrySelectionSource,
        rowDistance: Int
    ) -> TimeInterval {
        // Keyboard moves are one row at a time, so a longer jump is a wrap
        // between the last and first entries, which would race through the
        // whole list if animated.
        guard source == .keyboard || source == .keyboardRepeat,
              rowDistance <= 1,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            return 0
        }
        // Held keys repeat faster than any animation can finish, so each
        // repeat would interrupt the previous scroll and the list would
        // stutter. Follow the selection instantly instead.
        return source == .keyboardRepeat ? 0 : 0.22
    }

    /// The List ignores `withAnimation` when scrolling on macOS, so animate
    /// its backing table view directly. A zero duration still goes through
    /// the animator so it replaces any scroll animation in flight. Returns
    /// false when the table view cannot be found or does not match the
    /// visible items.
    private func animateListScroll(toItemID itemID: String, duration: TimeInterval) -> Bool {
        let items = store.visibleItems
        guard let row = items.firstIndex(where: { $0.id == itemID }),
              let scrollView = store.selectedRowAnchorView?.enclosingScrollView,
              let tableView = scrollView.documentView as? NSTableView,
              tableView.numberOfRows == items.count else {
            return false
        }

        let clipView = scrollView.contentView
        guard let estimatedTarget = edgeScrollBounds(ofRow: row, in: tableView, clipView: clipView) else {
            return true
        }
        // Rows that come into view mid-slide would be built and measured on
        // the fly, dropping frames. Build every row the slide passes first.
        tableView.prepareContent(in: clipView.bounds.union(estimatedTarget))
        // Measuring those rows can move the selected row, so aim again.
        guard let origin = edgeScrollBounds(ofRow: row, in: tableView, clipView: clipView)?.origin else {
            return true
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            clipView.animator().setBoundsOrigin(origin)
        }
        return true
    }

    /// How close the selected row may come to the top or bottom edge before
    /// the list scrolls, so a little of what comes next stays visible.
    private static let edgeScrollMargin: CGFloat = 60

    /// The bounds that bring the row back to `edgeScrollMargin` inside the
    /// visible area, or nil when it is already there. Scrolling only near the
    /// edges keeps the list still while the selection moves through the
    /// visible rows.
    private func edgeScrollBounds(
        ofRow row: Int,
        in tableView: NSTableView,
        clipView: NSClipView
    ) -> NSRect? {
        let bounds = clipView.bounds
        let rowRect = tableView.rect(ofRow: row)
        let margin = min(Self.edgeScrollMargin, bounds.height / 4)
        let isAboveMargin = rowRect.minY < bounds.minY + margin
        let isBelowMargin = rowRect.maxY > bounds.maxY - margin
        guard isAboveMargin || isBelowMargin else { return nil }

        var target = bounds
        if isAboveMargin || rowRect.height > bounds.height - 2 * margin {
            // Moving up, or a row too tall to fit: show its top.
            target.origin.y = rowRect.minY - margin
        } else {
            target.origin.y = rowRect.maxY + margin - bounds.height
        }
        target = clipView.constrainBoundsRect(target)
        // At either end of the list there may be nowhere left to scroll.
        return target.origin == bounds.origin ? nil : target
    }

    @ViewBuilder
    private func actionButtons(for entry: CheatSheetEntry) -> some View {
        Button(entry.actions.primary.title) {
            store.perform(entry.actions.primary, for: entry)
        }

        if !entry.actions.secondary.isEmpty {
            Divider()

            ForEach(Array(entry.actions.secondary.enumerated()), id: \.offset) { _, action in
                Button(action.title) {
                    store.perform(action, for: entry)
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
            switch store.selectedItem {
            case .entry(let entry):
                footerShortcut("↩", label: returnVerb(for: entry))
                footerShortcut("⌥↩", label: "options")
                if entry.hasVariables {
                    footerShortcut("⌘↩", label: "skip form")
                }
            case .section:
                // Return already opens the options menu on a section.
                footerShortcut("↩", label: "options")
            case nil:
                EmptyView()
            }
            footerShortcut("⌘E", label: "edit")
            footerShortcut("⌘⇧N", label: "new")
            Spacer()
            footerShortcut("⌘⇧M", label: "more")
        }
        .font(.system(size: chromeSize * 0.85))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .frame(height: max(38, chromeSize * 2.6))
    }

    private func footerShortcut(_ keys: String, label: String) -> some View {
        HStack(spacing: 8) {
            Text(keys)
                .font(.system(size: chromeSize * 0.8, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(PanelStyle.mutedFill, in: RoundedRectangle(cornerRadius: 4))
                .overlay {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
                }
            Text(label)
                .foregroundStyle(.secondary.opacity(0.85))
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
    }

    private func returnVerb(for entry: CheatSheetEntry) -> String {
        switch entry.actions.primary {
        case .openURL, .openFile, .revealInFinder:
            return "open"
        default:
            return "copy"
        }
    }
}

private struct SelectedRowAnchor: NSViewRepresentable {
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

private struct MoreOptionsButton: NSViewRepresentable {
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

/// Equatable so a selection change re-renders only the rows whose selection
/// or copied state changed. Otherwise the `onSelect` closure, which SwiftUI
/// cannot compare, makes every row re-parse its Markdown on each key press.
private struct EntryRow: View, Equatable {
    let entry: CheatSheetEntry
    let values: [String: String]
    let titleFontSize: CGFloat
    let descriptionFontSize: CGFloat
    let noteFontSize: CGFloat
    let payloadFontSize: CGFloat
    let fonts: EntryFonts
    let isSelected: Bool
    let wasCopied: Bool
    let onSelect: () -> Void

    /// `onSelect` is left out: it always selects `entry`, which is compared.
    static func == (lhs: EntryRow, rhs: EntryRow) -> Bool {
        lhs.entry == rhs.entry
            && lhs.values == rhs.values
            && lhs.titleFontSize == rhs.titleFontSize
            && lhs.descriptionFontSize == rhs.descriptionFontSize
            && lhs.noteFontSize == rhs.noteFontSize
            && lhs.payloadFontSize == rhs.payloadFontSize
            && lhs.fonts == rhs.fonts
            && lhs.isSelected == rhs.isSelected
            && lhs.wasCopied == rhs.wasCopied
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                SelectableText(
                    attributedString: EntryTextStyle.title(entry.title, size: titleFontSize, fonts: fonts),
                    maximumNumberOfLines: 1,
                    onMouseDown: onSelect
                )
                .fixedSize()
                if entry.hasVariables {
                    EntryBadge(
                        title: entry.variables.count == 1 ? "1 field" : "\(entry.variables.count) fields",
                        symbol: "square.and.pencil",
                        titleFontSize: titleFontSize,
                        fonts: fonts
                    )
                }
                if case .url = entry {
                    EntryBadge(title: "URL", symbol: "link", titleFontSize: titleFontSize, fonts: fonts)
                }
                if case .file = entry {
                    EntryBadge(title: "File", symbol: "doc", titleFontSize: titleFontSize, fonts: fonts)
                }
                Spacer()
                if wasCopied {
                    Label("Copied", systemImage: "checkmark")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            switch entry {
            case .note(let note):
                noteText(note.rawContent)
            case .command(let command):
                if let rawDescription = command.rawDescription {
                    descriptionText(rawDescription)
                }
                payloadText(command.rawCommand, language: command.language)
            case .url(let url):
                if let rawDescription = url.rawDescription {
                    descriptionText(rawDescription)
                }
                payloadText(url.rawURL)
            case .file(let file):
                if let rawDescription = file.rawDescription {
                    descriptionText(rawDescription)
                }
                payloadText(file.rawPath)
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .overlay(alignment: .leading) {
            if isSelected {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.accentColor)
                    .frame(width: 3)
                    .padding(.vertical, 8)
                    .padding(.leading, 4)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }

    private func descriptionText(_ raw: String) -> some View {
        MarkdownDescriptionView(
            raw: raw,
            values: values,
            fontSize: descriptionFontSize,
            fonts: fonts,
            onSelect: onSelect
        )
    }

    private func noteText(_ raw: String) -> some View {
        MarkdownDescriptionView(
            raw: raw,
            values: values,
            fontSize: noteFontSize,
            fonts: fonts,
            textColor: EntryTextStyle.noteBodyColor,
            usesExpandedParagraphLayout: true,
            onSelect: onSelect
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func payloadText(_ raw: String, language: String? = nil) -> some View {
        SelectableText(
            attributedString: EntryTextStyle.payload(
                TextVariables.segments(of: raw, values: values),
                language: language,
                size: payloadFontSize,
                fonts: fonts
            ),
            onMouseDown: onSelect
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(
            PanelStyle.mutedFill,
            in: RoundedRectangle(cornerRadius: 6)
        )
    }
}

private struct MarkdownDescriptionView: View {
    let raw: String
    let values: [String: String]
    let fontSize: CGFloat
    let fonts: EntryFonts
    var textColor: NSColor = .secondaryLabelColor
    var usesExpandedParagraphLayout = false
    let onSelect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: usesExpandedParagraphLayout ? 14 : 6) {
            ForEach(Array(renderBlocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .text(let text):
                    renderedText(text, baseColor: textColor)
                case .quote(let quote):
                    renderedQuote(quote)
                case .table(let table):
                    renderedTable(table)
                case .list(let items):
                    renderedList(items)
                }
            }
        }
    }

    private var renderBlocks: [MarkdownText.Block] {
        let blocks = MarkdownText.blocks(in: raw)
        guard usesExpandedParagraphLayout else { return blocks }

        return blocks.flatMap { block -> [MarkdownText.Block] in
            guard case .text(let text) = block else { return [block] }
            return text.components(separatedBy: "\n\n").compactMap { paragraph in
                let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : .text(trimmed)
            }
        }
    }

    private func renderedText(
        _ raw: String,
        emphasized: Bool = false,
        baseColor: NSColor = .secondaryLabelColor
    ) -> some View {
        SelectableText(
            attributedString: EntryTextStyle.markdownRenderedDescription(
                TextVariables.segments(of: raw, values: values),
                size: fontSize,
                fonts: fonts,
                emphasized: emphasized,
                baseColor: baseColor,
                lineSpacing: EntryTextStyle.lineSpacing
            ),
            onMouseDown: onSelect
        )
    }

    private func renderedTable(_ table: MarkdownText.Table) -> some View {
        ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(Array(table.header.enumerated()), id: \.offset) { column, cell in
                        tableCell(
                            cell,
                            emphasized: true,
                            background: Color.gray.opacity(0.22),
                            drawsTrailingRule: column < table.columnCount - 1
                        )
                    }
                }

                Divider()
                    .gridCellColumns(table.columnCount)

                ForEach(Array(table.rows.enumerated()), id: \.offset) { rowIndex, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { column, cell in
                            tableCell(
                                cell,
                                background: rowIndex.isMultiple(of: 2)
                                    ? Color.clear
                                    : Color(nsColor: .controlBackgroundColor).opacity(0.35),
                                drawsTrailingRule: column < table.columnCount - 1
                            )
                        }
                    }

                    if rowIndex < table.rows.count - 1 {
                        Divider()
                            .gridCellColumns(table.columnCount)
                    }
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.8), lineWidth: 1)
            }
            .padding(.vertical, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func renderedList(_ items: [MarkdownText.ListItem]) -> some View {
        SelectableText(
            attributedString: EntryTextStyle.markdownRenderedList(
                items.map { item in
                    EntryTextStyle.ListItemSegments(
                        item: item,
                        segments: TextVariables.segments(of: item.text, values: values)
                    )
                },
                size: fontSize,
                fonts: fonts,
                baseColor: textColor,
                lineSpacing: EntryTextStyle.lineSpacing
            ),
            onMouseDown: onSelect
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func renderedQuote(_ raw: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(Color(nsColor: .tertiaryLabelColor))
                .frame(width: 3)

            renderedText(raw, baseColor: .secondaryLabelColor)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 3)
        .padding(.leading, 2)
    }

    private func tableCell(
        _ raw: String,
        emphasized: Bool = false,
        background: Color,
        drawsTrailingRule: Bool
    ) -> some View {
        renderedText(raw, emphasized: emphasized, baseColor: .labelColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(background)
            .background {
                if isInlineCodeOnly(raw) {
                    Color.primary.opacity(0.035)
                }
            }
            .overlay(alignment: .trailing) {
                if drawsTrailingRule {
                    Rectangle()
                        .fill(Color(nsColor: .separatorColor).opacity(0.65))
                        .frame(width: 1)
                }
            }
    }

    private func isInlineCodeOnly(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2,
              trimmed.hasPrefix("`"),
              trimmed.hasSuffix("`") else { return false }
        return !trimmed.dropFirst().dropLast().contains("`")
    }
}

private struct SectionHeaderRow: View {
    let title: String
    let fontSize: CGFloat
    let fonts: EntryFonts

    var body: some View {
        // Uppercase and a trailing rule mark a heading, so a large gray
        // title is not mistaken for a disabled entry.
        HStack(spacing: 8) {
            Text(title.uppercased())
                .font(Font(fonts.text(size: fontSize * 0.8, weight: .semibold)))
                .tracking(fontSize * 0.06)
                .foregroundStyle(.primary)
                .lineLimit(1)
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(height: 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(PanelStyle.mutedFill, in: RoundedRectangle(cornerRadius: 6))
        .padding(.top, 10)
        .padding(.bottom, 4)
        .listRowSeparator(.hidden)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isHeader)
    }
}

private struct EntryBadge: View {
    let title: String
    let symbol: String
    let titleFontSize: CGFloat
    let fonts: EntryFonts

    private var badgeFontSize: CGFloat { max(9, titleFontSize * 0.8) }

    var body: some View {
        Label(title, systemImage: symbol)
        .font(Font(fonts.text(size: badgeFontSize, weight: .medium)))
        .foregroundStyle(.tint)
        .fixedSize()
        .padding(.horizontal, badgeFontSize * 0.6)
        .padding(.vertical, badgeFontSize * 0.2)
        .background(Color.accentColor.opacity(0.14), in: Capsule())
    }
}
