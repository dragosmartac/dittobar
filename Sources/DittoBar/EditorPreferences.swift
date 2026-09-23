import AppKit
import Foundation

enum EditorOption: String, CaseIterable, Identifiable {
    case systemDefault
    case visualStudioCode
    case textEdit
    case custom

    var id: Self { self }

    var title: String {
        switch self {
        case .systemDefault: "System Default"
        case .visualStudioCode: "Visual Studio Code"
        case .textEdit: "TextEdit"
        case .custom: "Custom Application"
        }
    }

    fileprivate var bundleIdentifiers: [String] {
        switch self {
        case .visualStudioCode:
            [
                "com.facebook.fbvscode",
                "com.facebook.fbvscode-dev",
                "com.facebook.fbvscode-insiders",
                "com.microsoft.VSCode",
                "com.microsoft.VSCodeInsiders"
            ]
        case .textEdit:
            ["com.apple.TextEdit"]
        case .systemDefault, .custom:
            []
        }
    }

    fileprivate var applicationNames: [String] {
        switch self {
        case .visualStudioCode:
            [
                "VS Code @ FB.app",
                "VS Code @ FB - Dev.app",
                "VS Code @ FB - Insiders.app",
                "Visual Studio Code.app",
                "Visual Studio Code - Insiders.app"
            ]
        case .textEdit:
            ["TextEdit.app"]
        case .systemDefault, .custom:
            []
        }
    }
}

enum EditorPreferences {
    static let selectedEditorKey = "editor.selected"
    static let customEditorPathKey = "editor.customApplicationPath"
    static let defaultEditor = EditorOption.visualStudioCode

    static func selectedEditor(defaults: UserDefaults = .standard) -> EditorOption {
        guard let rawValue = defaults.string(forKey: selectedEditorKey),
              let editor = EditorOption(rawValue: rawValue) else {
            return defaultEditor
        }
        return editor
    }

    static func applicationURL(
        for editor: EditorOption,
        defaults: UserDefaults = .standard,
        workspace: NSWorkspace = .shared,
        fileManager: FileManager = .default
    ) -> URL? {
        if editor == .custom {
            guard let path = defaults.string(forKey: customEditorPathKey),
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
