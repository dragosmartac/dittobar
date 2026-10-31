import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ShortcutsSettingsView: View {

    var body: some View {
        SettingsPane {
            shortcuts
        }
    }

    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Shortcuts")
                .font(.title2.bold())

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(ShortcutGroup.all) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.title)
                                .font(.headline)

                            ForEach(group.shortcuts) { shortcut in
                                HStack(alignment: .firstTextBaseline) {
                                    Text(shortcut.title)
                                    Spacer()
                                    ShortcutKeys(alternatives: shortcut.keys)
                                }
                            }
                        }
                    }
                }
                .padding(.trailing, 12)
            }
        }
    }
}

private struct Shortcut: Identifiable {
    let title: String
    /// Each element is one way to trigger the shortcut, e.g. `["↑", "↓"]`.
    let keys: [[String]]

    var id: String { title }
}

private struct ShortcutGroup: Identifiable {
    let title: String
    let shortcuts: [Shortcut]

    var id: String { title }

    static let all = [
        ShortcutGroup(title: "Anywhere", shortcuts: [
            Shortcut(title: "Show or hide DittoBar", keys: [["⌥", "Space"]])
        ]),
        ShortcutGroup(title: "Navigation", shortcuts: [
            Shortcut(title: "Next entry or section", keys: [["↓"], ["Tab"]]),
            Shortcut(title: "Previous entry or section", keys: [["↑"], ["⇧", "Tab"]]),
            Shortcut(title: "Previous or next sheet", keys: [["⌘", "⌥", "←"], ["⌘", "⌥", "→"]]),
            Shortcut(title: "Go to sheet 1–9", keys: [["⌘", "1–9"]]),
            Shortcut(title: "Search", keys: [["⌘", "F"]]),
            Shortcut(title: "Close", keys: [["Esc"]])
        ]),
        ShortcutGroup(title: "Entries", shortcuts: [
            Shortcut(title: "Copy or open, or fill in variables first", keys: [["↩"]]),
            Shortcut(title: "Copy or open with the current variable values", keys: [["⌘", "↩"]]),
            Shortcut(title: "Show all actions", keys: [["⌥", "↩"]])
        ]),
        ShortcutGroup(title: "Sections", shortcuts: [
            Shortcut(title: "Show section actions", keys: [["↩"]])
        ]),
        ShortcutGroup(title: "Variable Form", shortcuts: [
            Shortcut(title: "Next or previous field", keys: [["Tab"], ["⇧", "Tab"]]),
            Shortcut(title: "Copy or open", keys: [["↩"], ["⌘", "↩"]]),
            Shortcut(title: "Cancel", keys: [["Esc"]])
        ]),
        ShortcutGroup(title: "Cheat Sheets", shortcuts: [
            Shortcut(title: "Edit current sheet", keys: [["⌘", "E"]]),
            Shortcut(title: "New sheet", keys: [["⌘", "⇧", "N"]]),
            Shortcut(title: "More options", keys: [["⌘", "⇧", "M"]]),
            Shortcut(title: "Settings", keys: [["⌘", ","]])
        ])
    ]
}

/// Draws each key as a keycap, with alternatives separated by "or".
private struct ShortcutKeys: View {
    let alternatives: [[String]]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(alternatives.enumerated()), id: \.offset) { index, keys in
                if index > 0 {
                    Text("or")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                HStack(spacing: 3) {
                    ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                        Text(key)
                            .font(.system(.callout, design: .rounded).weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .frame(minWidth: 22)
                            .background(
                                Color(nsColor: .controlBackgroundColor),
                                in: RoundedRectangle(cornerRadius: 5)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .strokeBorder(Color(nsColor: .separatorColor))
                            )
                    }
                }
            }
        }
    }
}
