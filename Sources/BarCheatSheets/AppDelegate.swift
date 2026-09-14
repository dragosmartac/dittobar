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

    func applicationDidFinishLaunching(_ notification: Notification) {
        configurePopover()
        configureStatusItem()

        hotKeyManager = HotKeyManager { [weak self] in
            DispatchQueue.main.async {
                self?.togglePopover()
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

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = PopoverView.contentSize
        popover.contentViewController = NSHostingController(rootView: PopoverView(store: store))
        popover.delegate = self
        store.onRequestClose = { [weak self] in
            self?.popover.performClose(nil)
        }
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else { return }
        button.image = NSImage(
            systemSymbolName: "command.square",
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

        togglePopover()
    }

    @objc private func quitApplication() {
        NSApp.terminate(nil)
    }

    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }

        guard let button = statusItem.button else { return }
        store.reload()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func handleKeyEvent(_ event: NSEvent) -> NSEvent? {
        guard popover.isShown else { return event }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if event.keyCode == 53 {
            popover.performClose(nil)
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

        if modifiers.contains(.command),
           !modifiers.contains(.option),
           !modifiers.contains(.control),
           !modifiers.contains(.shift),
           event.charactersIgnoringModifiers?.lowercased() == "c" {
            store.copySelectedCommand()
            return nil
        }

        return event
    }
}
