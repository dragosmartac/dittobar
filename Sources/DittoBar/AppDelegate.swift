import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var panel: CheatSheetPanel!
    private let store = CheatSheetStore()
    private var statusItem: NSStatusItem!
    private var statusItemMenu: NSMenu!
    private var copyOptionsMenu: NSMenu!
    /// Run by the copy options menu's items, indexed by their tags.
    private var displayedActions: [() -> Void] = []
    private var hotKeyManager: HotKeyManager?
    private var keyMonitor: Any?
    private var outsideClickMonitor: Any?
    private var previouslyActiveApplication: NSRunningApplication?
    private var isCopyOptionsPresented = false
    private var copyOptionsItem: CheatSheetItem?

    private static let panelScreenHeightFraction: CGFloat = 0.85

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureMainMenu()
        configurePanel()
        configureStatusItem()
        configureCopyOptionsMenu()

        hotKeyManager = HotKeyManager { [weak self] in
            DispatchQueue.main.async {
                self?.togglePanel(restoringFocusOnClose: true)
            }
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Not `self?.handleKeyEvent(event) ?? event`: optional chaining
            // flattens the result, so a handled key's `nil` would fall back to
            // `event` and be delivered anyway, making AppKit beep.
            guard let self else { return event }
            return self.handleKeyEvent(event)
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(displayPreferencesDidChange),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        stopMonitoringOutsideClicks()
        NotificationCenter.default.removeObserver(self)
    }

    /// An accessory app displays no menu bar, but `NSApplication` still routes
    /// key equivalents through the main menu. Without an Edit menu there is
    /// nothing binding ⌘C/⌘V/⌘X/⌘A to the responder chain, so those shortcuts
    /// do nothing in any text field — including the variable form's.
    private func configureMainMenu() {
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(
            withTitle: "Select All",
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a"
        )

        let editItem = NSMenuItem()
        editItem.submenu = editMenu

        let mainMenu = NSMenu()
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
    }

    private func configurePanel() {
        panel = CheatSheetPanel(rootView: PopoverView(store: store))
        panel.delegate = self
        store.onRequestClose = { [weak self] in
            self?.closePanel(restoringFocus: false)
        }
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else { return }
        button.image = NSImage(
            systemSymbolName: "note.text",
            accessibilityDescription: "DittoBar"
        )
        button.toolTip = "DittoBar (⌥Space)"
        button.target = self
        button.action = #selector(statusItemClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        let menu = NSMenu()
        let quitItem = NSMenuItem(
            title: "Quit DittoBar",
            action: #selector(quitApplication),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
        statusItemMenu = menu
    }

    private func configureCopyOptionsMenu() {
        let menu = NSMenu(title: "Copy Options")
        menu.autoenablesItems = false
        copyOptionsMenu = menu
    }

    @objc private func statusItemClicked() {
        if let event = NSApp.currentEvent, event.type == .rightMouseUp,
           let button = statusItem.button {
            NSMenu.popUpContextMenu(statusItemMenu, with: event, for: button)
            return
        }

        togglePanel(restoringFocusOnClose: false)
    }

    @objc private func quitApplication() {
        NSApp.terminate(nil)
    }

    @objc private func performDisplayedAction(_ sender: NSMenuItem) {
        guard copyOptionsItem != nil,
              displayedActions.indices.contains(sender.tag) else { return }
        displayedActions[sender.tag]()
    }

    private func presentCopyOptionsMenu(for item: CheatSheetItem) {
        copyOptionsItem = item
        store.pinSelection(item)
        isCopyOptionsPresented = true
        DispatchQueue.main.async { [weak self] in
            self?.showCopyOptionsMenu(for: item)
        }
    }

    private func showCopyOptionsMenu(for item: CheatSheetItem) {
        guard panel.isVisible,
              let fallbackView = panel.contentView else {
            isCopyOptionsPresented = false
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
        isCopyOptionsPresented = false
        copyOptionsItem = nil
    }

    private func rebuildCopyOptionsMenu(for item: CheatSheetItem) {
        copyOptionsMenu.removeAllItems()
        let titledActions: [(title: String, perform: () -> Void)]
        // An entry's primary action stands apart from its secondary ones.
        let separatorIndex: Int?
        switch item {
        case .entry(let entry):
            titledActions = store.actions(for: entry).all.map { action in
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

    private func togglePanel(restoringFocusOnClose: Bool) {
        if panel.isVisible {
            closePanel(restoringFocus: restoringFocusOnClose)
            return
        }

        guard let button = statusItem.button else { return }
        let frontmostApplication = NSWorkspace.shared.frontmostApplication
        if frontmostApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previouslyActiveApplication = frontmostApplication
        }
        store.reload()
        panel.setFrame(panelFrame(below: button), display: false)

        // The panel takes keyboard focus without activating the app, so the
        // previous app stays frontmost, including a fullscreen one.
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
        startMonitoringOutsideClicks()
    }

    /// Places the panel just below the status item, kept on screen.
    private func panelFrame(below button: NSStatusBarButton) -> NSRect {
        let screen = button.window?.screen ?? NSScreen.main
        let size = preferredPanelSize(for: screen)
        guard let screen else { return NSRect(origin: .zero, size: size) }

        let visibleFrame = screen.visibleFrame
        let buttonFrame = button.window?.frame
            ?? NSRect(x: visibleFrame.midX, y: visibleFrame.maxY, width: 0, height: 0)
        let margin: CGFloat = 8
        let x = min(
            max(buttonFrame.midX - size.width / 2, visibleFrame.minX + margin),
            visibleFrame.maxX - size.width - margin
        )
        let top = min(buttonFrame.minY, visibleFrame.maxY) - 4
        return NSRect(x: x, y: top - size.height, width: size.width, height: size.height)
    }

    private func preferredPanelSize(for screen: NSScreen?) -> NSSize {
        guard let screen else {
            return NSSize(width: 900, height: 800)
        }

        let widthFraction = DisplayPreferences.popoverWidthFraction()
        return NSSize(
            width: floor(screen.visibleFrame.width * widthFraction),
            height: floor(screen.visibleFrame.height * Self.panelScreenHeightFraction)
        )
    }

    @objc private func displayPreferencesDidChange() {
        guard panel.isVisible, let button = statusItem.button else { return }
        panel.setFrame(panelFrame(below: button), display: true)
    }

    /// Clicks in other apps close the panel, as they would a transient
    /// popover. Clicks on the status item reach `statusItemClicked` instead.
    private func startMonitoringOutsideClicks() {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.closePanel(restoringFocus: false)
            }
        }
    }

    private func stopMonitoringOutsideClicks() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
        }
        outsideClickMonitor = nil
    }

    func windowDidResignKey(_ notification: Notification) {
        // The panel's own sheets and alerts take key too, so wait until focus
        // settles and close only if it moved somewhere else, such as another
        // app after ⌘Tab.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.panel.isVisible, !self.panel.isKeyWindow,
                  self.panel.attachedSheet == nil, !self.isCopyOptionsPresented else { return }
            self.closePanel(restoringFocus: false)
        }
    }

    private func closePanel(restoringFocus: Bool) {
        guard panel.isVisible else { return }
        stopMonitoringOutsideClicks()
        panel.orderOut(nil)

        // Keep any in-progress variable form alive while the panel is hidden.
        // This lets someone switch to another app to look up or copy a value,
        // then reopen the panel and continue exactly where they left off.
        // The form's own Cancel button and Escape handling still discard it.
        store.restorePinnedSelection()
        isCopyOptionsPresented = false
        copyOptionsItem = nil

        defer { previouslyActiveApplication = nil }

        // The panel never activates the app, but its sheets and alerts can.
        guard restoringFocus, NSApp.isActive else { return }
        previouslyActiveApplication?.activate(options: [])
    }

    private func handleKeyEvent(_ event: NSEvent) -> NSEvent? {
        guard panel.isVisible else { return event }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Alerts bring their own Return and Escape handling.
        if store.isNewSheetPromptPresented || store.editorErrorMessage != nil
            || isCopyOptionsPresented {
            return event
        }

        // Let the settings sheet handle its own fields and key equivalents.
        if store.isSettingsPresented {
            return event
        }

        // The variable form owns the keyboard while it is open: Tab moves
        // between its fields and Return confirms via their onSubmit.
        if store.isVariableFormPresented {
            if event.keyCode == 53 {
                store.cancelVariableForm()
                return nil
            }
            return event
        }

        if event.keyCode == 53 {
            closePanel(restoringFocus: true)
            return nil
        }

        if modifiers.contains(.command),
           let characters = event.charactersIgnoringModifiers,
           let number = Int(characters),
           (0...9).contains(number) {
            store.selectSheet(shortcutNumber: number)
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
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .openCheatSheetMoreOptions, object: nil)
            }
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
            if event.keyCode == 123 {
                store.moveSheetSelection(by: -1)
                return nil
            }
            if event.keyCode == 124 {
                store.moveSheetSelection(by: 1)
                return nil
            }
        }

        if event.keyCode == 48 {
            store.moveSelection(by: modifiers.contains(.shift) ? -1 : 1, isRepeat: event.isARepeat)
            return nil
        }

        if event.keyCode == 125 {
            store.moveSelection(by: 1, isRepeat: event.isARepeat)
            return nil
        }

        if event.keyCode == 126 {
            store.moveSelection(by: -1, isRepeat: event.isARepeat)
            return nil
        }

        // Return copies, leaving ⌘C to the system so text in the list stays
        // selectable and copyable. ⌥Return opens copy options, while ⌘Return
        // copies without opening the variable form. A section has no primary
        // action, so any Return opens its menu.
        if event.keyCode == 36 || event.keyCode == 76 {
            if let item = store.selectedItem, modifiers == .option || item.section != nil {
                presentCopyOptionsMenu(for: item)
            } else if modifiers.contains(.command) {
                store.performPrimaryActionForSelectedEntry(skippingVariableForm: true)
            } else {
                store.performPrimaryActionForSelectedEntry()
            }
            return nil
        }

        return event
    }
}

/// A floating panel that takes keyboard focus without activating the app.
///
/// An `NSPopover` only works while its app is active. Over a fullscreen app,
/// macOS hands activation straight back to that app, and the popover closes
/// as soon as it opens.
final class CheatSheetPanel: NSPanel {
    init<Content: View>(rootView: Content) {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true

        let hostingView = NSHostingView(rootView: rootView)
        // The app sizes the panel from the screen, not from its content.
        hostingView.sizingOptions = []
        hostingView.wantsLayer = true
        hostingView.layer?.cornerRadius = 10
        hostingView.layer?.masksToBounds = true
        contentView = hostingView
    }

    // Borderless windows refuse key status by default, which would leave the
    // search field unable to receive typing.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
