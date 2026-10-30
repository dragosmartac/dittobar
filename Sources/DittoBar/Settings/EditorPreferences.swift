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

    var bundleIdentifiers: [String] {
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

    var applicationNames: [String] {
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
    static let includeInstructionsKey = "editor.includeInstructionsInNewSheets"
    static let defaultIncludeInstructions = true
    static let defaultEditor = EditorOption.visualStudioCode

    static func includeInstructions(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: includeInstructionsKey) as? Bool ?? defaultIncludeInstructions
    }

    static func selectedEditor(defaults: UserDefaults = .standard) -> EditorOption {
        guard let rawValue = defaults.string(forKey: selectedEditorKey),
              let editor = EditorOption(rawValue: rawValue) else {
            return defaultEditor
        }
        return editor
    }
}
