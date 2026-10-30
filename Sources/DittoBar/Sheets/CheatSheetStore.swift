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
        didSet {
            searchCollapsedSectionKeys = []
            updateVisibleItems()
        }
    }
    /// The selected sheet's items that match `query`. Stored rather than
    /// computed: a single key press reads it several times, and each read
    /// would filter the whole sheet again.
    @Published private(set) var visibleItems: [CheatSheetItem] = []
    private(set) var visibleEntries: [CheatSheetEntry] = []
    private var matchingItems: [CheatSheetItem] = []
    private var collapsedSectionKeys: Set<String> = []
    private var searchCollapsedSectionKeys: Set<String> = []
    static let collapsedSectionsKey = "collapsedSections"

    /// Visible entries and nonempty sections, including collapsed sections.
    private(set) var selectableItems: [CheatSheetItem] = []
    @Published private(set) var copiedEntryIDs: Set<String> = []
    @Published var editorErrorMessage: String?
    @Published var isNewSheetPromptPresented = false
    @Published var newSheetName = ""
    @Published var variableForm: VariableFormState?
    @Published var isSettingsPresented = false
    @Published private var pinnedItemID: String?

    @Published private(set) var folderURL: URL
    let defaultFolderURL: URL
    static let sheetsDirectoryPathKey = "sheetsDirectoryPath"
    private let defaults: UserDefaults
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

    private let actionExecutor = EntryActionExecutor()
    private var watcher: DirectoryWatcher?

    init(fileManager: FileManager = .default, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        collapsedSectionKeys = Set(defaults.stringArray(forKey: Self.collapsedSectionsKey) ?? [])
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        defaultFolderURL = applicationSupport
            .appendingPathComponent("DittoBar", isDirectory: true)
            .appendingPathComponent("CheatSheets", isDirectory: true)

        if let path = defaults.string(forKey: Self.sheetsDirectoryPathKey), !path.isEmpty {
            folderURL = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            folderURL = defaultFolderURL
            SheetFiles.createInitialFilesIfNeeded(in: folderURL, fileManager: fileManager)
        }
        reload(fileManager: fileManager)
        selectFirstEntry()

        watchFolder()
    }

    /// Switches the source without moving or adding files to the chosen folder.
    func setSheetsDirectory(_ url: URL, fileManager: FileManager = .default) throws {
        let url = url.standardizedFileURL
        // Validate before changing either the active folder or the saved preference.
        _ = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
        watcher = nil
        folderURL = url
        if url == defaultFolderURL.standardizedFileURL {
            defaults.removeObject(forKey: Self.sheetsDirectoryPathKey)
        } else {
            defaults.set(url.path, forKey: Self.sheetsDirectoryPathKey)
        }
        variableForm = nil
        pinnedItemID = nil
        copiedEntryIDs = []
        query = ""
        selectedSheetIndex = 0
        reload(fileManager: fileManager)
        selectFirstEntry()
        watchFolder()
    }

    func resetSheetsDirectory() throws {
        try FileManager.default.createDirectory(at: defaultFolderURL, withIntermediateDirectories: true)
        try setSheetsDirectory(defaultFolderURL)
    }

    private func watchFolder() {
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
            matchingItems = CheatSheetSearch.filteredItems(in: sheet, matching: query) { entry in
                effectiveValues(for: entry)
            }
        } else {
            matchingItems = []
        }
        var sectionIsCollapsed = false
        visibleItems = matchingItems.filter { item in
            if let section = item.section {
                sectionIsCollapsed = isCollapsed(section)
                return true
            }
            return !sectionIsCollapsed
        }
        visibleEntries = visibleItems.compactMap(\.entry)
        let nonemptySectionIDs = Set(matchingItems.indices.compactMap { index -> String? in
            guard let section = matchingItems[index].section,
                  matchingItems.indices.contains(index + 1),
                  matchingItems[index + 1].entry != nil else { return nil }
            return section.id
        })
        selectableItems = visibleItems.filter { item in
            item.section.map { nonemptySectionIDs.contains($0.id) } ?? true
        }
    }

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func collapseKey(for section: CheatSheetSection) -> String {
        "\(selectedSheet?.sourceURL.standardizedFileURL.path ?? "")|\(section.id)"
    }

    func isCollapsed(_ section: CheatSheetSection) -> Bool {
        let keys = isSearching ? searchCollapsedSectionKeys : collapsedSectionKeys
        return keys.contains(collapseKey(for: section))
    }

    func toggleSection(_ section: CheatSheetSection) {
        guard !entries(in: section).isEmpty else { return }
        let key = collapseKey(for: section)
        if isSearching {
            if !searchCollapsedSectionKeys.insert(key).inserted {
                searchCollapsedSectionKeys.remove(key)
            }
        } else {
            if !collapsedSectionKeys.insert(key).inserted {
                collapsedSectionKeys.remove(key)
            }
            defaults.set(collapsedSectionKeys.sorted(), forKey: Self.collapsedSectionsKey)
        }
        updateVisibleItems()
        // Keep focus on the heading after its entries disappear or reappear.
        selectItem(.section(section))
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
        if let section = selectedItem?.section {
            toggleSection(section)
            return
        }
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
        switch actionExecutor.execute(action, output: output, folderURL: folderURL) {
        case .opened:
            onRequestClose?()
        case .copied:
            flashCopiedEntries([entryID])
        case .failed(let message):
            editorErrorMessage = message
        }
    }

    private func output(_ raw: String, for entry: CheatSheetEntry, textForm: EntryTextForm) -> String {
        let resolved = TextVariables.resolve(raw, values: effectiveValues(for: entry))
        return textForm == .markdownStripped ? MarkdownText.stripped(resolved) : resolved
    }

    /// Open all values, retaining the last failure and closing only if all opened.
    private func openAll(_ action: EntryAction, values: [String]) {
        let outcomes = values.map { actionExecutor.execute(action, output: $0, folderURL: folderURL) }
        for case .failed(let message) in outcomes {
            editorErrorMessage = message
        }
        if !outcomes.isEmpty, outcomes.allSatisfy({ $0 == .opened }) {
            onRequestClose?()
        }
    }

    private func writeToPasteboard(_ value: String, flashing entryIDs: Set<String>) {
        actionExecutor.copy(value)
        flashCopiedEntries(entryIDs)
    }

    private func flashCopiedEntries(_ entryIDs: Set<String>) {
        copiedEntryIDs = entryIDs

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            if self?.copiedEntryIDs == entryIDs {
                self?.copiedEntryIDs = []
            }
        }
    }

    // MARK: - Section actions

    /// The matching entries under a section heading, even when collapsed.
    /// While searching, only the entries that match are included.
    func entries(in section: CheatSheetSection) -> [CheatSheetEntry] {
        guard let start = matchingItems.firstIndex(of: .section(section)) else { return [] }
        return Array(
            matchingItems[(start + 1)...]
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
            openAll(.openURL, values: urls)

        case .openAllFiles:
            let paths = entries.compactMap { entry -> String? in
                guard case .file(let file) = entry else { return nil }
                return output(file.rawPath, for: entry, textForm: .resolved)
            }
            openAll(.openFile, values: paths)

        case .copyAllEntries:
            guard !entries.isEmpty else { return }
            writeToPasteboard(
                EntryActionExecutor.joinedEntryTexts(entries.map(primaryText(for:))),
                flashing: Set(entries.map(\.id))
            )

        case .copyAsMarkdown:
            guard !entries.isEmpty else { return }
            writeToPasteboard(markdown(for: section), flashing: Set(entries.map(\.id)))
        }
    }

    func markdown(for section: CheatSheetSection) -> String {
        SectionMarkdownExporter.markdown(
            for: section,
            entries: entries(in: section),
            values: effectiveValues(for:)
        )
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
            return EntryActionExecutor.copiedPath(
                for: output(file.rawPath, for: entry, textForm: .resolved),
                relativeTo: folderURL
            )
        }
    }

    func openFolder() {
        _ = actionExecutor.open(folderURL)
    }

    func copyFolderPath() {
        actionExecutor.copy(EntryActionExecutor.shellEscapedPath(folderURL.path))
    }

    func copySelectedSheetPath() {
        guard let sourceURL = selectedSheet?.sourceURL else {
            NSSound.beep()
            return
        }

        actionExecutor.copy(EntryActionExecutor.shellEscapedPath(sourceURL.path))
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
        do {
            let fileURL = try SheetFiles.create(
                named: proposedName,
                in: folderURL,
                includeInstructions: EditorPreferences.includeInstructions(),
                fileManager: fileManager
            )
            reload(fileManager: fileManager)
            if let index = sheets.firstIndex(where: { $0.sourceURL == fileURL }) {
                selectSheet(at: index)
            }
            if openInConfiguredEditor(fileURL) {
                onRequestClose?()
            }
        } catch {
            editorErrorMessage = error.localizedDescription
        }
    }

    @discardableResult
    private func openInConfiguredEditor(_ sourceURL: URL) -> Bool {
        do {
            try EditorLauncher.open(sourceURL) { [weak self] error in
                self?.editorErrorMessage = error.localizedDescription
            }
            return true
        } catch {
            editorErrorMessage = error.localizedDescription
            return false
        }
    }

    func reload(fileManager: FileManager = .default) {
        let previousSheetID = selectedSheet?.id
        // Before the sheets, whose filtering reads the values.
        rememberedValues = EntryVariableStorage.allValues()
        sheets = SheetFiles.load(from: folderURL, fileManager: fileManager)

        if let previousSheetID,
           let index = sheets.firstIndex(where: { $0.id == previousSheetID }) {
            selectedSheetIndex = index
        } else {
            selectedSheetIndex = min(selectedSheetIndex, max(0, sheets.count - 1))
        }
        selectedItemIndex = min(selectedItemIndex, max(0, selectableItems.count - 1))
    }
}
