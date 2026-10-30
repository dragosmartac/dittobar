import AppKit

/// Executes resolved actions without owning selection, forms, or panel state.
@MainActor
struct EntryActionExecutor {
    enum Outcome: Equatable {
        case copied
        case opened
        case failed(String)
    }

    var open: (URL) -> Bool = { NSWorkspace.shared.open($0) }
    var reveal: ([URL]) -> Void = { NSWorkspace.shared.activateFileViewerSelecting($0) }
    var pasteboard: NSPasteboard = .general
    var fileManager: FileManager = .default

    func execute(_ action: EntryAction, output: String, folderURL: URL) -> Outcome {
        switch action {
        case .openURL:
            let value = output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: value), url.scheme != nil else {
                return .failed("\"\(value)\" is not a valid URL.")
            }
            return open(url) ? .opened : .failed("The URL could not be opened.")
        case .openFile, .revealInFinder:
            let url = Self.fileURL(forPath: output, relativeTo: folderURL)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                return .failed("\"\(url.path)\" does not exist.")
            }
            guard !isDirectory.boolValue else {
                return .failed("\"\(url.path)\" is a folder. File entries can only open files.")
            }
            if action == .revealInFinder {
                reveal([url])
                return .opened
            }
            return open(url) ? .opened : .failed("No application could open \"\(url.path)\".")
        case .copyPath:
            copy(Self.copiedPath(for: output, relativeTo: folderURL))
            return .copied
        default:
            copy(output)
            return .copied
        }
    }

    func copy(_ value: String) {
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }

    /// The full path, ready to paste into a shell.
    static func copiedPath(for path: String, relativeTo folderURL: URL) -> String {
        shellEscapedPath(fileURL(forPath: path, relativeTo: folderURL).path)
    }

    /// Expands `~` and resolves a relative path against `folderURL`.
    static func fileURL(forPath path: String, relativeTo folderURL: URL) -> URL {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let expandedPath = (trimmedPath as NSString).expandingTildeInPath
        let fileURL = expandedPath.hasPrefix("/")
            ? URL(fileURLWithPath: expandedPath)
            : folderURL.appendingPathComponent(expandedPath)
        return fileURL.standardizedFileURL
    }

    static func shellEscapedPath(_ path: String) -> String {
        path.replacingOccurrences(of: " ", with: "\\ ")
    }

    /// One text per line when every text fits on one line, so commands paste
    /// as a script and URLs as a list. Otherwise a blank line between texts.
    static func joinedEntryTexts(_ texts: [String]) -> String {
        let trimmed = texts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let separator = trimmed.contains { $0.contains("\n") } ? "\n\n" : "\n"
        return trimmed.joined(separator: separator)
    }

}
