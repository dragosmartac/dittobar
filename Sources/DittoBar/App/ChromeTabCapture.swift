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
        let window = try CaptureAppleEvent.specifier(want: cWindow, form: formAbsolutePosition,
                                                     key: .init(int32: 1), container: .null())
        let tab = try CaptureAppleEvent.property(activeTab, of: window)
        let properties = try CaptureAppleEvent.property(OSType(pProperties), of: tab)
        let record = try CaptureAppleEvent(processID: processID).get(properties)
        return try draft(from: record)
    }

    static func draft(from record: NSAppleEventDescriptor) throws -> EntryDraft {
        guard let url = record.forKeyword(tabURL)?.stringValue, !url.isEmpty else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(errAENoSuchObject))
        }
        let title = record.forKeyword(AEKeyword(pName))?.stringValue ?? ""
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
}
