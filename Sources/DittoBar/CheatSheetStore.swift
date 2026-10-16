import AppKit
import Foundation
import SwiftUI

@MainActor
final class CheatSheetStore: ObservableObject {
    @Published private(set) var sheets: [CheatSheet] = [] {
        didSet { updateVisibleItems() }
    }
    @Published var selectedSheetIndex = 0 {
        didSet { updateVisibleItems() }
    }
    /// Indexes `selectableItems`.
    @Published var selectedItemIndex = 0
    @Published var query = "" {
        didSet { updateVisibleItems() }
    }
    /// The selected sheet's items that match `query`. Stored rather than
    /// computed: a single key press reads it several times, and each read
    /// would filter the whole sheet again.
    @Published private(set) var visibleItems: [CheatSheetItem] = []
    private(set) var visibleEntries: [CheatSheetEntry] = []
    /// The visible entries, plus each section that has visible entries for
    /// its actions to act on.
    private(set) var selectableItems: [CheatSheetItem] = []
    @Published private(set) var copiedEntryIDs: Set<String> = []
    @Published var editorErrorMessage: String?
    @Published var isNewSheetPromptPresented = false
    @Published var newSheetName = ""
    @Published var variableForm: VariableFormState?
    @Published var isSettingsPresented = false
    @Published private var pinnedItemID: String?

    let folderURL: URL
    var onRequestClose: (() -> Void)?
    weak var selectedRowAnchorView: NSView?

    /// An in-memory copy of `EntryVariableStorage`, which every row reads on
    /// every update. Reloaded with the sheets and updated when values are saved.
    private var rememberedValues: [String: [String: String]] = [:]

    /// What caused the latest change to `selectedItemIndex`, so the list can
    /// decide how to scroll to the new selection.
    enum EntrySelectionSource {
        case keyboard
        case keyboardRepeat
        case pointer
        case other
    }

    private var entrySelectionSource = EntrySelectionSource.other

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
        selectFirstEntry()

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

    private func updateVisibleItems() {
        if let sheet = selectedSheet {
            visibleItems = CheatSheetSearch.filteredItems(in: sheet, matching: query) { entry in
                effectiveValues(for: entry)
            }
        } else {
            visibleItems = []
        }
        visibleEntries = visibleItems.compactMap(\.entry)
        selectableItems = visibleItems.indices.compactMap { index in
            let item = visibleItems[index]
            guard item.section != nil else { return item }
            let nextIndex = visibleItems.index(after: index)
            let hasEntries = visibleItems.indices.contains(nextIndex)
                && visibleItems[nextIndex].entry != nil
            return hasEntries ? item : nil
        }
    }

    var selectedItem: CheatSheetItem? {
        if let pinnedItemID,
           let item = selectableItems.first(where: { $0.id == pinnedItemID }) {
            return item
        }
        guard selectableItems.indices.contains(selectedItemIndex) else { return nil }
        return selectableItems[selectedItemIndex]
    }

    var selectedItemID: String? {
        pinnedItemID ?? selectedItem?.id
    }

    var selectedEntry: CheatSheetEntry? { selectedItem?.entry }

    func selectItem(_ item: CheatSheetItem) {
        guard let index = selectableItems.firstIndex(where: { $0.id == item.id }) else {
            return
        }
        setSelectedItemIndex(index, source: .pointer)
    }

    /// Lands on the first entry rather than its section, so Return copies
    /// the top search result.
    func selectFirstEntry() {
        selectedItemIndex = selectableItems.firstIndex { $0.entry != nil } ?? 0
    }

    /// Returns what caused the latest selection change and resets it, so
    /// index changes made elsewhere are reported as `.other`.
    func consumeEntrySelectionSource() -> EntrySelectionSource {
        defer { entrySelectionSource = .other }
        return entrySelectionSource
    }

    private func setSelectedItemIndex(_ index: Int, source: EntrySelectionSource) {
        // An unchanged index fires no onChange, which would leave the source
        // set for an unrelated later change.
        guard index != selectedItemIndex else { return }
        entrySelectionSource = source
        selectedItemIndex = index
    }

    /// Native menu tracking can temporarily disturb SwiftUI list selection.
    /// Keep both rendering and item lookup tied to the item that opened it.
    func pinSelection(_ item: CheatSheetItem) {
        pinnedItemID = item.id
    }

    func restorePinnedSelection() {
        guard let pinnedItemID else { return }
        if let index = selectableItems.firstIndex(where: { $0.id == pinnedItemID }) {
            selectedItemIndex = index
        }
        self.pinnedItemID = nil
    }

    func selectSheet(at index: Int) {
        guard sheets.indices.contains(index) else { return }
        selectedSheetIndex = index
        selectFirstEntry()
    }

    func moveSheetSelection(by offset: Int) {
        guard !sheets.isEmpty else { return }
        let index = (selectedSheetIndex + offset + sheets.count) % sheets.count
        selectSheet(at: index)
    }

    func moveSelection(by offset: Int, isRepeat: Bool = false) {
        let count = selectableItems.count
        guard count > 0 else {
            selectedItemIndex = 0
            return
        }
        setSelectedItemIndex(
            (selectedItemIndex + offset + count) % count,
            source: isRepeat ? .keyboardRepeat : .keyboard
        )
    }

    // MARK: - Variables

    var isVariableFormPresented: Bool { variableForm != nil }

    /// The values an entry starts with: its Markdown defaults, overridden by
    /// whatever was last entered for the variables it still declares.
    func effectiveValues(for entry: CheatSheetEntry) -> [String: String] {
        var values = entry.defaultValues
        let remembered = rememberedValues[entry.storageKey] ?? [:]
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
        let remembered = rememberedValues[form.storageKey] ?? [:]
        let values = remembered.merging(form.values) { _, newValue in newValue }
        EntryVariableStorage.save(values, for: form.storageKey)
        rememberedValues[form.storageKey] = values
        // Search also matches variable values.
        updateVisibleItems()
        variableForm = nil
        complete(form.action, output: form.output, entryID: form.entryID)
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
            writeToPasteboard(entry.title, flashing: [entry.id])

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

        case (.copyDescription(let textForm), .file(let file)):
            guard let rawDescription = file.rawDescription else { return }
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

        case (.openFile, .file(let file)), (.copyPath, .file(let file)), (.revealInFinder, .file(let file)):
            performTextAction(
                action,
                for: entry,
                raw: file.rawPath,
                variables: file.variables,
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

        complete(action, output: output(raw, for: entry, textForm: textForm), entryID: entry.id)
    }

    /// Finishes an action once its text is resolved, with or without the
    /// variable form.
    private func complete(_ action: EntryAction, output: String, entryID: String) {
        switch action {
        case .openURL:
            openURL(output)
        case .openFile:
            openFile(atPath: output)
        case .copyPath:
            writeToPasteboard(copiedPath(for: output), flashing: [entryID])
        case .revealInFinder:
            guard let fileURL = existingFileURL(forPath: output) else { return }
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
            onRequestClose?()
        default:
            writeToPasteboard(output, flashing: [entryID])
        }
    }

    private func output(_ raw: String, for entry: CheatSheetEntry, textForm: EntryTextForm) -> String {
        let resolved = TextVariables.resolve(raw, values: effectiveValues(for: entry))
        return textForm == .markdownStripped ? MarkdownText.stripped(resolved) : resolved
    }

    private func openURL(_ value: String) {
        if openURLWithoutClosing(value) {
            onRequestClose?()
        }
    }

    /// Reports a failure through `editorErrorMessage` and returns false.
    private func openURLWithoutClosing(_ value: String) -> Bool {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedValue), url.scheme != nil else {
            editorErrorMessage = "\"\(trimmedValue)\" is not a valid URL."
            return false
        }

        guard NSWorkspace.shared.open(url) else {
            editorErrorMessage = "The URL could not be opened."
            return false
        }
        return true
    }

    private func openFile(atPath path: String) {
        if openFileWithoutClosing(atPath: path) {
            onRequestClose?()
        }
    }

    /// Opens the file in its default application, as Finder would, so a PDF
    /// or image does not land in a text editor. Reports a failure through
    /// `editorErrorMessage` and returns false.
    private func openFileWithoutClosing(atPath path: String) -> Bool {
        guard let fileURL = existingFileURL(forPath: path) else { return false }
        guard NSWorkspace.shared.open(fileURL) else {
            editorErrorMessage = "No application could open \"\(fileURL.path)\"."
            return false
        }
        return true
    }

    /// Reports a missing file, or a folder, through `editorErrorMessage`
    /// and returns nil.
    private func existingFileURL(forPath path: String) -> URL? {
        let fileURL = Self.fileURL(forPath: path, relativeTo: folderURL)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory) else {
            editorErrorMessage = "\"\(fileURL.path)\" does not exist."
            return nil
        }
        guard !isDirectory.boolValue else {
            editorErrorMessage = "\"\(fileURL.path)\" is a folder. File entries can only open files."
            return nil
        }
        return fileURL
    }

    /// The full path, ready to paste into a shell.
    private func copiedPath(for path: String) -> String {
        Self.shellEscapedPath(Self.fileURL(forPath: path, relativeTo: folderURL).path)
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

    private func writeToPasteboard(_ value: String, flashing entryIDs: Set<String>) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
        copiedEntryIDs = entryIDs

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            if self?.copiedEntryIDs == entryIDs {
                self?.copiedEntryIDs = []
            }
        }
    }

    // MARK: - Section actions

    /// The visible entries under a section heading, up to the next heading.
    /// While searching, only the entries that match are included.
    func entries(in section: CheatSheetSection) -> [CheatSheetEntry] {
        guard let start = visibleItems.firstIndex(of: .section(section)) else { return [] }
        return Array(
            visibleItems[(start + 1)...]
                .prefix { $0.section == nil }
                .compactMap(\.entry)
        )
    }

    func actions(for section: CheatSheetSection) -> [SectionAction] {
        let entries = entries(in: section)
        var actions: [SectionAction] = []
        if entries.contains(where: { if case .url = $0 { true } else { false } }) {
            actions.append(.openAllURLs)
        }
        if entries.contains(where: { if case .file = $0 { true } else { false } }) {
            actions.append(.openAllFiles)
        }
        if !entries.isEmpty {
            actions.append(contentsOf: [.copyAllEntries, .copyAsMarkdown])
        }
        return actions
    }

    /// Uses each entry's current values without showing the variable form.
    func perform(_ action: SectionAction, for section: CheatSheetSection) {
        let entries = entries(in: section)

        switch action {
        case .openAllURLs:
            let urls = entries.compactMap { entry -> String? in
                guard case .url(let url) = entry else { return nil }
                return output(url.rawURL, for: entry, textForm: .resolved)
            }
            // Open every URL even if one fails, then close only if all opened.
            let failures = urls.filter { !openURLWithoutClosing($0) }
            if failures.isEmpty, !urls.isEmpty {
                onRequestClose?()
            }

        case .openAllFiles:
            let paths = entries.compactMap { entry -> String? in
                guard case .file(let file) = entry else { return nil }
                return output(file.rawPath, for: entry, textForm: .resolved)
            }
            // Open every file even if one fails, then close only if all opened.
            let failures = paths.filter { !openFileWithoutClosing(atPath: $0) }
            if failures.isEmpty, !paths.isEmpty {
                onRequestClose?()
            }

        case .copyAllEntries:
            guard !entries.isEmpty else { return }
            writeToPasteboard(
                Self.joinedEntryTexts(entries.map(primaryText(for:))),
                flashing: Set(entries.map(\.id))
            )

        case .copyAsMarkdown:
            guard !entries.isEmpty else { return }
            writeToPasteboard(markdown(for: section), flashing: Set(entries.map(\.id)))
        }
    }

    /// The section and its visible entries in cheat-sheet Markdown, with
    /// each text resolved. URLs become bare lines, which most Markdown
    /// renderers turn into links, rather than `url` fences. Paths keep
    /// their `file` fences, since no renderer would link a bare path.
    func markdown(for section: CheatSheetSection) -> String {
        let blocks = entries(in: section).map { entry -> String in
            var parts = ["### \(entry.title)"]
            switch entry {
            case .note(let note):
                parts.append(output(note.rawContent, for: entry, textForm: .resolved))
            case .command(let command):
                if let rawDescription = command.rawDescription {
                    parts.append(output(rawDescription, for: entry, textForm: .resolved))
                }
                parts.append(Self.fenced(
                    output(command.rawCommand, for: entry, textForm: .resolved),
                    language: command.language
                ))
            case .url(let url):
                if let rawDescription = url.rawDescription {
                    parts.append(output(rawDescription, for: entry, textForm: .resolved))
                }
                parts.append(output(url.rawURL, for: entry, textForm: .resolved))
            case .file(let file):
                if let rawDescription = file.rawDescription {
                    parts.append(output(rawDescription, for: entry, textForm: .resolved))
                }
                parts.append(Self.fenced(
                    output(file.rawPath, for: entry, textForm: .resolved),
                    language: "file"
                ))
            }
            return parts
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .joined(separator: "\n\n")
        }
        return (["## \(section.title)"] + blocks).joined(separator: "\n\n")
    }

    /// Uses a fence longer than any backtick run in the code.
    private static func fenced(_ code: String, language: String?) -> String {
        var fence = "```"
        while code.contains(fence) {
            fence += "`"
        }
        let trimmed = code.trimmingCharacters(in: .newlines)
        return "\(fence)\(language ?? "")\n\(trimmed)\n\(fence)"
    }

    /// The text an entry's primary action copies or, for a URL, opens. For a
    /// file, what Copy Path copies.
    private func primaryText(for entry: CheatSheetEntry) -> String {
        switch entry {
        case .command(let command):
            return output(command.rawCommand, for: entry, textForm: .resolved)
        case .note(let note):
            return output(note.rawContent, for: entry, textForm: .markdownStripped)
        case .url(let url):
            return output(url.rawURL, for: entry, textForm: .resolved)
        case .file(let file):
            return copiedPath(for: output(file.rawPath, for: entry, textForm: .resolved))
        }
    }

    /// One text per line when every text fits on one line, so commands paste
    /// as a script and URLs as a list. Otherwise a blank line between texts.
    static func joinedEntryTexts(_ texts: [String]) -> String {
        let trimmed = texts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let separator = trimmed.contains { $0.contains("\n") } ? "\n\n" : "\n"
        return trimmed.joined(separator: separator)
    }

    func openFolder() {
        NSWorkspace.shared.open(folderURL)
    }

    func copyFolderPath() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(Self.shellEscapedPath(folderURL.path), forType: .string)
    }

    func copySelectedSheetPath() {
        guard let sourceURL = selectedSheet?.sourceURL else {
            NSSound.beep()
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(Self.shellEscapedPath(sourceURL.path), forType: .string)
    }

    static func shellEscapedPath(_ path: String) -> String {
        path.replacingOccurrences(of: " ", with: "\\ ")
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
        // Before the sheets, whose filtering reads the values.
        rememberedValues = EntryVariableStorage.allValues()
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
        selectedItemIndex = min(selectedItemIndex, max(0, selectableItems.count - 1))
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
