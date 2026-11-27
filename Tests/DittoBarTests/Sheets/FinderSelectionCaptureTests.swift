import AppKit
import Carbon
import Testing
@testable import DittoBar

struct FinderSelectionCaptureTests {
    @Test func capturesSingleSelectionAsAnEditablePath() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("Café #1.txt")
        try Data().write(to: file)
        let item = try CaptureAppleEvent.specifier(want: cFile, form: formAbsolutePosition,
                                                   key: .init(int32: 1), container: .null())
        let selection = NSAppleEventDescriptor.list()
        selection.insert(item, at: 1)

        for (url, kind) in [(file, EntryDraft.Kind.file), (directory, .directory),
                            (URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"), .file)] {
            var properties: [OSType] = []
            let draft = try FinderSelectionCapture.readSelection { request in
                let property = try #require(request.forKeyword(AEKeyword(keyAEKeyData))).typeCodeValue
                properties.append(property)
                if property == pSelection { return selection }
                #expect(request.forKeyword(AEKeyword(keyAEContainer))?.data == item.data)
                return .init(string: url.absoluteString)
            }
            #expect(properties == [OSType(pSelection), OSType(pURL)])
            #expect(draft == EntryDraft(kind: kind, title: url.lastPathComponent, rawContent: url.path))
        }
    }

    @Test(arguments: [0, 2])
    func requiresExactlyOneSelectedItem(count: Int) {
        let selection = NSAppleEventDescriptor.list()
        for index in 0..<count { selection.insert(.null(), at: index + 1) }
        #expect(throws: FinderSelectionCapture.SelectionError.selectOneItem) {
            try FinderSelectionCapture.readSelection { _ in selection }
        }
    }
}
