import AppKit
import Foundation
import SwiftUI

@MainActor
final class CheatSheetStore: ObservableObject {
    @Published private(set) var sheets: [CheatSheet] = []
    @Published var selectedSheetIndex = 0
    @Published var selectedEntryIndex = 0
    @Published var query = ""
    @Published private(set) var copiedEntryID: String?
    @Published var editorErrorMessage: String?
    @Published var isNewSheetPromptPresented = false
    @Published var newSheetName = ""
    @Published var variableForm: VariableFormState?
    @Published var isSettingsPresented = false
    @Published private var pinnedEntryID: String?

    let folderURL: URL
    var onRequestClose: (() -> Void)?
    weak var selectedRowAnchorView: NSView?

    private var watcher: DirectoryWatcher?

    init(fileManager: FileManager = .default) {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        folderURL = applicationSupport
            .appendingPathComponent("DittoBar", isDirectory: true)
            .appendingPathComponent("CheatSheets", isDirectory: true)

        createInitialFilesIfNeeded(fileManager: fileManager)
        reload(fileManager: fileManager)

        watcher = DirectoryWatcher(path: folderURL.path) { [weak self] in
            DispatchQueue.main.async {
                self?.reload()
            }
        }
    }

    var selectedSheet: CheatSheet? {
        guard sheets.indices.contains(selectedSheetIndex) else { return nil }
        return sheets[selectedSheetIndex]
    }

    var visibleItems: [CheatSheetItem] {
        guard let sheet = selectedSheet else { return [] }
        return CheatSheetSearch.filteredItems(in: sheet, matching: query) { entry in
            effectiveValues(for: entry)
        }
    }

    var visibleEntries: [CheatSheetEntry] {
        visibleItems.compactMap { item in
            guard case .entry(let entry) = item else { return nil }
            return entry
        }
    }

    var visibleRows: [CheatSheetRow] {
        var visibleEntryIndex = 0
        return visibleItems.map { item in
            switch item {
            case .section(let section):
                return .section(section)
            case .entry(let entry):
                defer { visibleEntryIndex += 1 }
                return .entry(entry, visibleIndex: visibleEntryIndex)
            }
        }
    }

    var selectedEntry: CheatSheetEntry? {
        let entries = visibleEntries
        if let pinnedEntryID,
           let entry = entries.first(where: { $0.id == pinnedEntryID }) {
            return entry
        }
        guard entries.indices.contains(selectedEntryIndex) else { return nil }
        return entries[selectedEntryIndex]
    }

    func isEntrySelected(_ entry: CheatSheetEntry, at index: Int) -> Bool {
        if let pinnedEntryID {
            return entry.id == pinnedEntryID
        }
        return index == selectedEntryIndex
    }

    /// Native menu tracking can temporarily disturb SwiftUI list selection.
    /// Keep both rendering and entry lookup tied to the entry that opened it.
    func pinEntrySelection(_ entry: CheatSheetEntry) {
        pinnedEntryID = entry.id
    }

    func restorePinnedEntrySelection() {
        guard let pinnedEntryID else { return }
        if let index = visibleEntries.firstIndex(where: { $0.id == pinnedEntryID }) {
            selectedEntryIndex = index
        }
        self.pinnedEntryID = nil
    }

    func selectSheet(at index: Int) {
        guard sheets.indices.contains(index) else { return }
        selectedSheetIndex = index
        selectedEntryIndex = 0
    }

    func moveSheetSelection(by offset: Int) {
        guard !sheets.isEmpty else { return }
        let index = (selectedSheetIndex + offset + sheets.count) % sheets.count
        selectSheet(at: index)
    }

    func moveSelection(by offset: Int) {
        let count = visibleEntries.count
        guard count > 0 else {
            selectedEntryIndex = 0
            return
        }
        selectedEntryIndex = (selectedEntryIndex + offset + count) % count
    }

    // MARK: - Variables

    var isVariableFormPresented: Bool { variableForm != nil }

    /// The values an entry starts with: its Markdown defaults, overridden by
    /// whatever was last entered for the variables it still declares.
    func effectiveValues(for entry: CheatSheetEntry) -> [String: String] {
        var values = entry.defaultValues
        let remembered = EntryVariableStorage.values(for: entry.storageKey)
        for variable in entry.variables {
            if let value = remembered[variable.name] {
                values[variable.name] = value
            }
        }
        return values
    }

    private func presentVariableForm(
        for entry: CheatSheetEntry,
        raw: String,
        variables: [EntryVariable],
        textForm: EntryTextForm,
        action: EntryAction
    ) {
        guard !variables.isEmpty else { return }
        variableForm = VariableFormState(
            entryID: entry.id,
            storageKey: entry.storageKey,
            title: entry.title,
            raw: raw,
            textForm: textForm,
            action: action,
            variables: variables,
            values: effectiveValues(for: entry)
        )
    }

    func cancelVariableForm() {
        variableForm = nil
    }

    func resetVariableFormToDefaults() {
        guard var form = variableForm else { return }
        form.values = Dictionary(
            uniqueKeysWithValues: form.variables.map { ($0.name, $0.defaultValue) }
        )
        variableForm = form
    }

    func confirmVariableForm() {
        guard let form = variableForm else { return }
        let remembered = EntryVariableStorage.values(for: form.storageKey)
        EntryVariableStorage.save(
            remembered.merging(form.values) { _, newValue in newValue },
            for: form.storageKey
        )
        variableForm = nil
        if form.action == .openURL {
            openURL(form.output)
        } else {
            writeToPasteboard(form.output, flashing: form.entryID)
        }
    }

    func binding(forVariable name: String) -> Binding<String> {
        Binding(
            get: { [weak self] in self?.variableForm?.values[name] ?? "" },
            set: { [weak self] newValue in self?.variableForm?.values[name] = newValue }
        )
    }

    // MARK: - Entry actions

    func performPrimaryActionForSelectedEntry(skippingVariableForm: Bool = false) {
        guard let selectedEntry else { return }
        perform(
            selectedEntry.actions.primary,
            for: selectedEntry,
            skippingVariableForm: skippingVariableForm
        )
    }

    func perform(
        _ action: EntryAction,
        for entry: CheatSheetEntry,
        skippingVariableForm: Bool = false
    ) {
        guard entry.actions.all.contains(action) else {
            assertionFailure("Unavailable action \(action) for entry \(entry.id)")
            return
        }

        switch (action, entry) {
        case (.copyTitle, _):
            writeToPasteboard(entry.title, flashing: entry.id)

        case (.copyCommand, .command(let command)):
            performTextAction(
                action,
                for: entry,
                raw: command.rawCommand,
                variables: command.variables,
                textForm: .resolved,
                skippingVariableForm: skippingVariableForm
            )

        case (.copyNoteContent(let textForm), .note(let note)):
            performTextAction(
                action,
                for: entry,
                raw: note.rawContent,
                variables: note.variables,
                textForm: textForm,
                skippingVariableForm: skippingVariableForm
            )

        case (.copyURL, .url(let url)):
            performTextAction(
                action,
                for: entry,
                raw: url.rawURL,
                variables: url.variables,
                textForm: .resolved,
                skippingVariableForm: skippingVariableForm
            )

        case (.copyDescription(let textForm), .command(let command)):
            guard let rawDescription = command.rawDescription else { return }
            performTextAction(
                action,
                for: entry,
                raw: rawDescription,
                variables: TextVariables.variables(in: rawDescription),
                textForm: textForm,
                skippingVariableForm: skippingVariableForm
            )

        case (.copyDescription(let textForm), .url(let url)):
            guard let rawDescription = url.rawDescription else { return }
            performTextAction(
                action,
                for: entry,
                raw: rawDescription,
                variables: TextVariables.variables(in: rawDescription),
                textForm: textForm,
                skippingVariableForm: skippingVariableForm
            )

        case (.openURL, .url(let url)):
            performTextAction(
                action,
                for: entry,
                raw: url.rawURL,
                variables: url.variables,
                textForm: .resolved,
                skippingVariableForm: skippingVariableForm
            )

        default:
            assertionFailure("Mismatched action \(action) for entry \(entry.id)")
        }
    }

    private func performTextAction(
        _ action: EntryAction,
        for entry: CheatSheetEntry,
        raw: String,
        variables: [EntryVariable],
        textForm: EntryTextForm,
        skippingVariableForm: Bool
    ) {
        if !skippingVariableForm, !variables.isEmpty {
            presentVariableForm(
                for: entry,
                raw: raw,
                variables: variables,
                textForm: textForm,
                action: action
            )
            return
        }

        let resolved = TextVariables.resolve(raw, values: effectiveValues(for: entry))
        let output = textForm == .markdownStripped
            ? MarkdownText.stripped(resolved)
            : resolved
        if action == .openURL {
            openURL(output)
        } else {
            writeToPasteboard(output, flashing: entry.id)
        }
    }

    private func openURL(_ value: String) {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedValue), url.scheme != nil else {
            editorErrorMessage = "\"\(trimmedValue)\" is not a valid URL."
            return
        }

        guard NSWorkspace.shared.open(url) else {
            editorErrorMessage = "The URL could not be opened."
            return
        }
        onRequestClose?()
    }

    private func writeToPasteboard(_ value: String, flashing entryID: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
        copiedEntryID = entryID

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            if self?.copiedEntryID == entryID {
                self?.copiedEntryID = nil
            }
        }
    }

    func openFolder() {
        NSWorkspace.shared.open(folderURL)
    }

    func copyFolderPath() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(folderURL.path, forType: .string)
    }

    func openSelectedSheetInEditor() {
        guard let sourceURL = selectedSheet?.sourceURL else {
            NSSound.beep()
            return
        }

        if openInConfiguredEditor(sourceURL) {
            onRequestClose?()
        }
    }

    func requestNewSheetCreation() {
        newSheetName = ""
        isNewSheetPromptPresented = true
    }

    func createNewSheetInEditor(named proposedName: String, fileManager: FileManager = .default) {
        var name = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.lowercased().hasSuffix(".md") {
            name = String(name.dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard !name.isEmpty else {
            editorErrorMessage = "Enter a name for the new cheat sheet."
            return
        }

        guard !name.contains("/") else {
            editorErrorMessage = "Cheat sheet names cannot contain a slash (/)."
            return
        }

        let fileURL = folderURL.appendingPathComponent(name).appendingPathExtension("md")
        guard !fileManager.fileExists(atPath: fileURL.path) else {
            editorErrorMessage = "A cheat sheet named \"\(name)\" already exists."
            return
        }

        let template = StarterContent.newSheet(named: name)

        do {
            try template.write(to: fileURL, atomically: true, encoding: .utf8)
            reload(fileManager: fileManager)
            if let index = sheets.firstIndex(where: { $0.sourceURL == fileURL }) {
                selectSheet(at: index)
            }
            if openInConfiguredEditor(fileURL) {
                onRequestClose?()
            }
        } catch {
            editorErrorMessage = "The new cheat sheet could not be created: \(error.localizedDescription)"
        }
    }

    @discardableResult
    private func openInConfiguredEditor(_ sourceURL: URL) -> Bool {
        let editor = EditorPreferences.selectedEditor()
        let applicationURL = editor == .systemDefault
            ? NSWorkspace.shared.urlForApplication(toOpen: sourceURL)
            : EditorPreferences.applicationURL(for: editor)

        guard let applicationURL else {
            editorErrorMessage = editor == .systemDefault
                ? "No default Markdown editor could be found. Choose an editor in Settings."
                : "\(editor.title) could not be found. Choose another editor in Settings."
            return false
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(
            [sourceURL],
            withApplicationAt: applicationURL,
            configuration: configuration
        ) { [weak self] application, error in
            DispatchQueue.main.async {
                if let error {
                    self?.editorErrorMessage = error.localizedDescription
                } else {
                    application?.activate(options: [.activateAllWindows])
                }
            }
        }
        return true
    }

    func reload(fileManager: FileManager = .default) {
        let previousSheetID = selectedSheet?.id
        let urls = (try? fileManager.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        sheets = urls
            .filter { $0.pathExtension.lowercased() == "md" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .compactMap { url in
                guard let source = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                return CheatSheetParser.parse(source, fileURL: url)
            }

        if let previousSheetID,
           let index = sheets.firstIndex(where: { $0.id == previousSheetID }) {
            selectedSheetIndex = index
        } else {
            selectedSheetIndex = min(selectedSheetIndex, max(0, sheets.count - 1))
        }
        selectedEntryIndex = min(selectedEntryIndex, max(0, visibleEntries.count - 1))
    }

    private func createInitialFilesIfNeeded(fileManager: FileManager) {
        try? fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let hasMarkdown = ((try? fileManager.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: nil
        )) ?? []).contains { $0.pathExtension.lowercased() == "md" }

        guard !hasMarkdown else { return }

        try? StarterContent.vimSheet.write(
            to: folderURL.appendingPathComponent("vim.md"),
            atomically: true,
            encoding: .utf8
        )

        try? StarterContent.gitSheet.write(
            to: folderURL.appendingPathComponent("git.md"),
            atomically: true,
            encoding: .utf8
        )
    }
}
