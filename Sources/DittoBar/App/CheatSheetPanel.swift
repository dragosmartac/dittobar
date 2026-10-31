import AppKit
import SwiftUI

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
        animationBehavior = .documentWindow
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
        hostingView.layer?.cornerRadius = 14
        hostingView.layer?.cornerCurve = .continuous
        hostingView.layer?.masksToBounds = true
        contentView = hostingView
    }

    // Borderless windows refuse key status by default, which would leave the
    // search field unable to receive typing.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
