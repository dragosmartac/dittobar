import Carbon
import Foundation

enum ChromeTabCapture {
    static let bundleID = "com.google.Chrome"

    // Chrome's scripting dictionary uses 'acTa' for the active tab and
    // 'URL ' for its address. The title uses the standard name property.
    private static let activeTab: OSType = 0x61635461
    private static let tabURL: OSType = 0x55524C20

    /// Read the properties together so the URL and title belong to the same tab.
    static func read(processID: pid_t) async throws -> EntryDraft {
        let window = try specifier(want: cWindow, form: formAbsolutePosition,
                                   key: .init(int32: 1), container: .null())
        let tab = try specifier(want: typeProperty, form: formPropertyID,
                                key: .init(typeCode: activeTab), container: window)
        let properties = try specifier(want: typeProperty, form: formPropertyID,
                                       key: .init(typeCode: OSType(pProperties)), container: tab)
        let event = NSAppleEventDescriptor(eventClass: AEEventClass(kAECoreSuite),
                                           eventID: AEEventID(kAEGetData),
                                           targetDescriptor: .init(processIdentifier: processID),
                                           returnID: AEReturnID(kAutoGenerateReturnID),
                                           transactionID: AETransactionID(kAnyTransactionID))
        event.setParam(properties, forKeyword: AEKeyword(keyDirectObject))
        let reply = try event.sendEvent(options: [.waitForReply, .canInteract], timeout: 30)
        return try draft(from: reply)
    }

    static func draft(from reply: NSAppleEventDescriptor) throws -> EntryDraft {
        if let error = reply.paramDescriptor(forKeyword: AEKeyword(keyErrorNumber)), error.int32Value != 0 {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(error.int32Value))
        }
        let record = reply.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))
        guard let url = record?.forKeyword(tabURL)?.stringValue, !url.isEmpty else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(errAENoSuchObject))
        }
        let title = record?.forKeyword(AEKeyword(pName))?.stringValue ?? ""
        let singleLineTitle = title.split(whereSeparator: \.isNewline).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return EntryDraft(kind: .url, title: singleLineTitle.isEmpty ? url : singleLineTitle, rawContent: url)
    }

    static func message(for error: Error) -> String {
        switch (error as NSError).code {
        case Int(errAEEventNotPermitted):
            return "To capture Chrome tabs, allow DittoBar to control Google Chrome in System Settings → Privacy & Security → Automation."
        case Int(errAENoSuchObject), Int(errAEIllegalIndex):
            return "Open a Chrome tab to capture, or enter a URL below."
        default:
            return "Couldn’t read the Chrome tab. Enter its URL manually or try Quick Capture again."
        }
    }

    private static func specifier(want: OSType, form: Int, key: NSAppleEventDescriptor,
                                  container: NSAppleEventDescriptor) throws -> NSAppleEventDescriptor {
        let record = NSAppleEventDescriptor.record()
        record.setDescriptor(.init(typeCode: want), forKeyword: AEKeyword(keyAEDesiredClass))
        record.setDescriptor(.init(enumCode: OSType(form)), forKeyword: AEKeyword(keyAEKeyForm))
        record.setDescriptor(key, forKeyword: AEKeyword(keyAEKeyData))
        record.setDescriptor(container, forKeyword: AEKeyword(keyAEContainer))
        guard let object = record.coerce(toDescriptorType: DescType(typeObjectSpecifier)) else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(errAECoercionFail))
        }
        return object
    }
}
