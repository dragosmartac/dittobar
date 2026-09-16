import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let popover = NSPopover()
    private let store = CheatSheetStore()
    private var statusItem: NSStatusItem!
    private var statusItemMenu: NSMenu!
    private var hotKeyManager: HotKeyManager?
    private var keyMonitor: Any?
    private var previouslyActiveApplication: NSRunningApplication?
    private var restoreFocusWhenPopoverCloses = false

    private static let popoverScreenFraction: CGFloat = 0.85

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureMainMenu()
        configurePopover()
        configureStatusItem()

        hotKeyManager = HotKeyManager { [weak self] in
            DispatchQueue.main.async {
                self?.togglePopover(restoringFocusOnClose: true)
            }
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event) ?? event
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
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

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = preferredPopoverSize(for: NSScreen.main)
        popover.contentViewController = NSHostingController(rootView: PopoverView(store: store))
        popover.delegate = self
        store.onRequestClose = { [weak self] in
            self?.closePopover(restoringFocus: true)
        }
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else { return }
        button.image = NSImage(
            systemSymbolName: "note.text",
            accessibilityDescription: "Bar Cheat Sheets"
        )
        button.toolTip = "Bar Cheat Sheets (⌥Space)"
        button.target = self
        button.action = #selector(statusItemClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        let menu = NSMenu()
        let quitItem = NSMenuItem(
            title: "Quit Bar Cheat Sheets",
            action: #selector(quitApplication),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
        statusItemMenu = menu
    }

    @objc private func statusItemClicked() {
        if let event = NSApp.currentEvent, event.type == .rightMouseUp,
           let button = statusItem.button {
            NSMenu.popUpContextMenu(statusItemMenu, with: event, for: button)
            return
        }

        togglePopover(restoringFocusOnClose: false)
    }

    @objc private func quitApplication() {
        NSApp.terminate(nil)
    }

    private func togglePopover(restoringFocusOnClose: Bool) {
        if popover.isShown {
            closePopover(restoringFocus: restoringFocusOnClose)
            return
        }

        guard let button = statusItem.button else { return }
        let frontmostApplication = NSWorkspace.shared.frontmostApplication
        if frontmostApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previouslyActiveApplication = frontmostApplication
        }
        popover.contentSize = preferredPopoverSize(for: button.window?.screen ?? NSScreen.main)
        store.reload()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func preferredPopoverSize(for screen: NSScreen?) -> NSSize {
        guard let screen else {
            return NSSize(width: 900, height: 800)
        }

        return NSSize(
            width: floor(screen.visibleFrame.width * Self.popoverScreenFraction),
            height: floor(screen.visibleFrame.height * Self.popoverScreenFraction)
        )
    }

    private func closePopover(restoringFocus: Bool) {
        restoreFocusWhenPopoverCloses = restoringFocus
        popover.performClose(nil)
    }

    func popoverDidClose(_ notification: Notification) {
        store.cancelVariableForm()

        defer {
            restoreFocusWhenPopoverCloses = false
            previouslyActiveApplication = nil
        }

        guard restoreFocusWhenPopoverCloses else { return }
        previouslyActiveApplication?.activate(options: [])
    }

    private func handleKeyEvent(_ event: NSEvent) -> NSEvent? {
        guard popover.isShown else { return event }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Alerts bring their own Return and Escape handling.
        if store.isNewSheetPromptPresented || store.editorErrorMessage != nil {
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
            closePopover(restoringFocus: true)
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
            store.openSelectedSheetInVSCode()
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
            store.moveSelection(by: modifiers.contains(.shift) ? -1 : 1)
            return nil
        }

        if event.keyCode == 125 {
            store.moveSelection(by: 1)
            return nil
        }

        if event.keyCode == 126 {
            store.moveSelection(by: -1)
            return nil
        }

        // Return copies, leaving ⌘C to the system so text in the list stays
        // selectable and copyable. ⌘Return copies without opening the form.
        if event.keyCode == 36 || event.keyCode == 76 {
            if modifiers.contains(.command) {
                store.copySelectedCommandSkippingForm()
            } else {
                store.copySelectedCommand()
            }
            return nil
        }

        return event
    }
}
