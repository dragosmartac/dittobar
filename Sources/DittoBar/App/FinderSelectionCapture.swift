import AppKit
import Carbon

enum FinderSelectionCapture {
    static let bundleID = "com.apple.finder"

    enum SelectionError: LocalizedError {
        case selectOneItem
        case unavailable

        var errorDescription: String? {
            switch self {
            case .selectOneItem: "Select one file or folder in Finder, then try Quick Capture again."
            case .unavailable: "The selected Finder item has no available file path."
            }
        }
    }

    static func read(processID: pid_t) async throws -> EntryDraft {
        try readSelection(using: CaptureAppleEvent(processID: processID).get)
    }

    static func readSelection(using get: (NSAppleEventDescriptor) throws -> NSAppleEventDescriptor) throws -> EntryDraft {
        let selection = try get(CaptureAppleEvent.property(OSType(pSelection)))
        let item = try selectedItem(in: selection)
        // Ask for the URL of this specific item even if Finder's selection changes.
        let address = try get(CaptureAppleEvent.property(OSType(pURL), of: item))
        guard let string = address.stringValue, let url = URL(string: string), url.isFileURL else {
            throw SelectionError.unavailable
        }
        return try draft(for: url)
    }

    private static func selectedItem(in selection: NSAppleEventDescriptor) throws -> NSAppleEventDescriptor {
        if selection.descriptorType == typeObjectSpecifier { return selection }
        guard selection.descriptorType == typeAEList, selection.numberOfItems == 1,
              let item = selection.atIndex(1) else { throw SelectionError.selectOneItem }
        return item
    }

    private static func draft(for url: URL) throws -> EntryDraft {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw SelectionError.unavailable
        }
        let isPackage = isDirectory.boolValue && NSWorkspace.shared.isFilePackage(atPath: url.path)
        let kind: EntryDraft.Kind = isDirectory.boolValue && !isPackage ? .directory : .file
        let name = url.lastPathComponent.components(separatedBy: .newlines).joined(separator: " ")
        return EntryDraft(kind: kind, title: name.isEmpty ? url.path : name, rawContent: url.path)
    }

    static func message(for error: Error) -> String {
        if let selectionError = error as? SelectionError { return selectionError.localizedDescription }
        if (error as NSError).code == Int(errAEEventNotPermitted) {
            return "To capture Finder items, allow DittoBar to control Finder in System Settings → Privacy & Security → Automation."
        }
        return "Couldn’t read the Finder selection. Browse for a path or try Quick Capture again."
    }
}
