import AppKit

@MainActor
enum EditorLauncher {
    struct UnavailableEditor: LocalizedError {
        let editor: EditorOption

        var errorDescription: String? {
            editor == .systemDefault
                ? "No default Markdown editor could be found. Choose an editor in Settings."
                : "\(editor.title) could not be found. Choose another editor in Settings."
        }
    }

    /// Throws for lookup failures; later launch failures are delivered on the main actor.
    static func open(
        _ sourceURL: URL,
        defaults: UserDefaults = .standard,
        workspace: NSWorkspace = .shared,
        onError: @escaping @MainActor (Error) -> Void
    ) throws {
        let editor = EditorPreferences.selectedEditor(defaults: defaults)
        let applicationURL = editor == .systemDefault
            ? workspace.urlForApplication(toOpen: sourceURL)
            : applicationURL(for: editor, defaults: defaults, workspace: workspace)
        guard let applicationURL else { throw UnavailableEditor(editor: editor) }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        workspace.open(
            [sourceURL],
            withApplicationAt: applicationURL,
            configuration: configuration
        ) { application, error in
            DispatchQueue.main.async {
                if let error {
                    onError(error)
                } else {
                    application?.activate(options: [.activateAllWindows])
                }
            }
        }
    }

    static func applicationURL(
        for editor: EditorOption,
        defaults: UserDefaults = .standard,
        workspace: NSWorkspace = .shared,
        fileManager: FileManager = .default
    ) -> URL? {
        if editor == .custom {
            guard let path = defaults.string(forKey: EditorPreferences.customEditorPathKey),
                  !path.isEmpty,
                  fileManager.fileExists(atPath: path) else { return nil }
            return URL(fileURLWithPath: path)
        }

        if let installedURL = editor.bundleIdentifiers.lazy.compactMap({
            workspace.urlForApplication(withBundleIdentifier: $0)
        }).first {
            return installedURL
        }

        let applicationFolders = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications", isDirectory: true)
        ]

        for folder in applicationFolders {
            for name in editor.applicationNames {
                let url = folder.appendingPathComponent(name, isDirectory: true)
                if fileManager.fileExists(atPath: url.path) {
                    return url
                }
            }
        }

        return nil
    }
}
