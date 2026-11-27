import Carbon
import Foundation

final class HotKeyManager {
    enum Shortcut: UInt32, CaseIterable {
        case togglePanel = 1
        case quickCapture

        var modifiers: UInt32 {
            switch self {
            case .togglePanel: UInt32(optionKey)
            case .quickCapture: UInt32(optionKey | shiftKey)
            }
        }
    }

    private static let signature: OSType = 0x42435348
    private var hotKeys: [EventHotKeyRef] = []
    private var eventHandler: EventHandlerRef?
    private let handler: (Shortcut) -> Void

    init(handler: @escaping (Shortcut) -> Void) {
        self.handler = handler

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var id = EventHotKeyID()
                let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                               EventParamType(typeEventHotKeyID), nil,
                                               MemoryLayout.size(ofValue: id), nil, &id)
                guard status == noErr, id.signature == HotKeyManager.signature,
                      let shortcut = Shortcut(rawValue: id.id) else { return OSStatus(eventNotHandledErr) }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                manager.handler(shortcut)
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )

        for shortcut in Shortcut.allCases {
            var hotKey: EventHotKeyRef?
            let id = EventHotKeyID(signature: Self.signature, id: shortcut.rawValue)
            let status = RegisterEventHotKey(UInt32(kVK_Space), shortcut.modifiers, id,
                                             GetApplicationEventTarget(), 0, &hotKey)
            if status == noErr, let hotKey {
                hotKeys.append(hotKey)
            } else {
                NSLog("Could not register DittoBar shortcut %@ (%d)", String(describing: shortcut), status)
            }
        }
    }

    deinit {
        for hotKey in hotKeys {
            UnregisterEventHotKey(hotKey)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }
}
