import AppKit
import SwiftUI

struct EntryListView: View {
    @ObservedObject var store: CheatSheetStore
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

    var body: some View {
        let selectedItemID = store.selectedItemID

        return ScrollViewReader { proxy in
            List(store.visibleItems) { item in
                switch item {
                case .section(let section):
                    SectionHeaderRow(
                        title: section.title,
                        isCollapsed: store.isCollapsed(section),
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
                        store.toggleSection(section)
                    }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityValue(store.isCollapsed(section) ? "Collapsed" : "Expanded")
                    .accessibilityAction { store.toggleSection(section) }
                    .listRowBackground(
                        item.id == selectedItemID
                            ? Color.dittoAccent.opacity(0.12)
                            : item.id == hoveredItemID ? Color.dittoAccent.opacity(0.05) : Color.clear
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
                                ? Color.dittoAccent.opacity(0.12)
                                : item.id == hoveredItemID ? Color.dittoAccent.opacity(0.05) : Color.clear
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
                let query = store.query

                let scroll = {
                    // A newer key press or search can overtake this queued update.
                    guard store.selectedItemID == itemID, store.query == query else { return }
                    if !animateListScroll(toItemID: itemID, duration: duration) {
                        proxy.scrollTo(itemID)
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
                let query = store.query
                let itemID = CheatSheetItem.entry(entry).id

                // The selected index may already point at the first entry, in
                // which case its onChange handler does not fire. Wait for the filtered rows
                // to be laid out, then show the first result at the top.
                DispatchQueue.main.async {
                    guard store.query == query, store.selectedItemID == itemID else { return }
                    proxy.scrollTo(itemID, anchor: .top)
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
        // A single tall entry can put even an adjacent selection a screen
        // away. Jump there rather than animating through and measuring a
        // potentially large stretch of content.
        let travel = abs(estimatedTarget.minY - clipView.bounds.minY)
        let effectiveDuration = travel > clipView.bounds.height ? 0 : duration
        // Only animated slides need the intervening rows. Preparing the
        // entire span of an instant wrap would eagerly build the whole list.
        let preparationBounds = effectiveDuration > 0
            ? clipView.bounds.union(estimatedTarget)
            : estimatedTarget
        tableView.prepareContent(in: preparationBounds)
        // Measuring those rows can move the selected row, so aim again.
        guard let origin = edgeScrollBounds(ofRow: row, in: tableView, clipView: clipView)?.origin else {
            return true
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = effectiveDuration
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

}
