import AppKit
import Foundation
import SwiftUI

@MainActor
final class CheatSheetStore: ObservableObject {
    @Published private(set) var sheets: [CheatSheet] = []
    @Published var selectedSheetIndex = 0
    @Published var selectedCommandIndex = 0
    @Published var query = ""
    @Published private(set) var copiedCommandID: String?
    @Published var editorErrorMessage: String?
    @Published var isNewSheetPromptPresented = false
    @Published var newSheetName = ""
    @Published var variableForm: VariableFormState?
    @Published var isSettingsPresented = false
    @Published private var pinnedCommandID: String?

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

    var visibleCommands: [CheatCommand] {
        guard let commands = selectedSheet?.commands else { return [] }
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return commands }

        return commands.filter {
            ($0.sectionTitle?.localizedCaseInsensitiveContains(trimmedQuery) ?? false)
                || $0.title.localizedCaseInsensitiveContains(trimmedQuery)
                || $0.rawDescription.localizedCaseInsensitiveContains(trimmedQuery)
                || $0.rawCommand.localizedCaseInsensitiveContains(trimmedQuery)
                || copyText(for: $0).localizedCaseInsensitiveContains(trimmedQuery)
                || TextVariables.resolve($0.rawDescription, values: effectiveValues(for: $0))
                    .localizedCaseInsensitiveContains(trimmedQuery)
        }
    }

    /// Section headers and commands in display order. Headers remain independent
    /// rows, including when a section has no commands yet.
    var visibleRows: [CheatSheetRow] {
        guard let sheet = selectedSheet else { return [] }

        let commands = visibleCommands
        let visibleIndexByID = Dictionary(
            uniqueKeysWithValues: commands.enumerated().map { ($0.element.id, $0.offset) }
        )
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let isSearching = !trimmedQuery.isEmpty
        var visibleSectionIDs = Set<String>()

        for (index, section) in sheet.sections.enumerated() {
            let nextOffset = index + 1 < sheet.sections.count
                ? sheet.sections[index + 1].commandOffset
                : sheet.commands.count
            let start = min(section.commandOffset, sheet.commands.count)
            let end = min(max(start, nextOffset), sheet.commands.count)
            let containsVisibleCommand = sheet.commands[start..<end].contains {
                visibleIndexByID[$0.id] != nil
            }

            if !isSearching
                || section.title.localizedCaseInsensitiveContains(trimmedQuery)
                || containsVisibleCommand {
                visibleSectionIDs.insert(section.id)
            }
        }

        var rows: [CheatSheetRow] = []
        for commandOffset in 0...sheet.commands.count {
            for section in sheet.sections
                where section.commandOffset == commandOffset
                    && visibleSectionIDs.contains(section.id) {
                rows.append(.section(section))
            }

            guard commandOffset < sheet.commands.count else { continue }
            let command = sheet.commands[commandOffset]
            if let visibleIndex = visibleIndexByID[command.id] {
                rows.append(.command(command, visibleIndex: visibleIndex))
            }
        }
        return rows
    }

    var selectedCommand: CheatCommand? {
        let commands = visibleCommands
        if let pinnedCommandID,
           let command = commands.first(where: { $0.id == pinnedCommandID }) {
            return command
        }
        guard commands.indices.contains(selectedCommandIndex) else { return nil }
        return commands[selectedCommandIndex]
    }

    func isCommandSelected(_ command: CheatCommand, at index: Int) -> Bool {
        if let pinnedCommandID {
            return command.id == pinnedCommandID
        }
        return index == selectedCommandIndex
    }

    /// Native menu tracking can temporarily disturb SwiftUI list selection.
    /// Keep both rendering and command lookup tied to the entry that opened it.
    func pinCommandSelection(_ command: CheatCommand) {
        pinnedCommandID = command.id
    }

    func restorePinnedCommandSelection() {
        guard let pinnedCommandID else { return }
        if let index = visibleCommands.firstIndex(where: { $0.id == pinnedCommandID }) {
            selectedCommandIndex = index
        }
        self.pinnedCommandID = nil
    }

    func selectSheet(at index: Int) {
        guard sheets.indices.contains(index) else { return }
        selectedSheetIndex = index
        selectedCommandIndex = 0
    }

    func moveSheetSelection(by offset: Int) {
        guard !sheets.isEmpty else { return }
        let index = (selectedSheetIndex + offset + sheets.count) % sheets.count
        selectSheet(at: index)
    }

    func moveSelection(by offset: Int) {
        let count = visibleCommands.count
        guard count > 0 else {
            selectedCommandIndex = 0
            return
        }
        selectedCommandIndex = (selectedCommandIndex + offset + count) % count
    }

    // MARK: - Variables

    var isVariableFormPresented: Bool { variableForm != nil }

    /// The values a command starts with: its Markdown defaults, overridden by
    /// whatever was last entered for the variables it still declares.
    func effectiveValues(for command: CheatCommand) -> [String: String] {
        var values = command.defaultValues
        let remembered = CommandVariableStorage.values(for: command.storageKey)
        for variable in command.variables {
            if let value = remembered[variable.name] {
                values[variable.name] = value
            }
        }
        return values
    }

    func copyText(for command: CheatCommand) -> String {
        let resolved = TextVariables.resolve(
            command.rawCopyText,
            values: effectiveValues(for: command)
        )
        return command.isDescriptionOnly ? MarkdownText.stripped(resolved) : resolved
    }

    func resolvedCommandSegments(for command: CheatCommand) -> [TextVariables.Segment] {
        TextVariables.segments(of: command.rawCommand, values: effectiveValues(for: command))
    }

    func resolvedDescriptionSegments(for command: CheatCommand) -> [TextVariables.Segment] {
        TextVariables.segments(of: command.rawDescription, values: effectiveValues(for: command))
    }

    private func presentVariableForm(
        for command: CheatCommand,
        raw: String,
        variables: [CommandVariable],
        outputFormat: CopyOutputFormat,
        action: VariableFormAction = .copy
    ) {
        guard !variables.isEmpty else { return }
        variableForm = VariableFormState(
            commandID: command.id,
            storageKey: command.storageKey,
            title: command.title,
            raw: raw,
            outputFormat: outputFormat,
            action: action,
            variables: variables,
            values: effectiveValues(for: command)
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
        let remembered = CommandVariableStorage.values(for: form.storageKey)
        CommandVariableStorage.save(
            remembered.merging(form.values) { _, newValue in newValue },
            for: form.storageKey
        )
        variableForm = nil
        switch form.action {
        case .copy:
            writeToPasteboard(form.output, flashing: form.commandID)
        case .openLink:
            openLink(form.output)
        }
    }

    func binding(forVariable name: String) -> Binding<String> {
        Binding(
            get: { [weak self] in self?.variableForm?.values[name] ?? "" },
            set: { [weak self] newValue in self?.variableForm?.values[name] = newValue }
        )
    }

    // MARK: - Copying

    /// Commands with variables open the form; everything else copies directly.
    func copySelectedCommand() {
        guard let selectedCommand else { return }
        if selectedCommand.hasVariables {
            presentVariableForm(
                for: selectedCommand,
                raw: selectedCommand.rawCopyText,
                variables: selectedCommand.variables,
                outputFormat: selectedCommand.isDescriptionOnly
                    ? .markdownStrippedDescription
                    : .resolvedCommand
            )
            return
        }
        writeToPasteboard(copyText(for: selectedCommand), flashing: selectedCommand.id)
    }

    /// Copies straight away, using the current variable values and skipping the form.
    func copySelectedCommandSkippingForm() {
        guard let selectedCommand else { return }
        writeToPasteboard(copyText(for: selectedCommand), flashing: selectedCommand.id)
    }

    func copyTitle(of command: CheatCommand) {
        writeToPasteboard(command.title, flashing: command.id)
    }

    func copyDescription(of command: CheatCommand, asMarkdown: Bool) {
        guard !command.rawDescription.isEmpty else { return }

        let variables = TextVariables.variables(in: command.rawDescription)
        let outputFormat: CopyOutputFormat = asMarkdown
            ? .resolvedDescription
            : .markdownStrippedDescription

        if !variables.isEmpty {
            presentVariableForm(
                for: command,
                raw: command.rawDescription,
                variables: variables,
                outputFormat: outputFormat
            )
            return
        }

        let resolved = TextVariables.resolve(
            command.rawDescription,
            values: effectiveValues(for: command)
        )
        let value = asMarkdown ? resolved : MarkdownText.stripped(resolved)
        writeToPasteboard(value, flashing: command.id)
    }

    func openLink(_ command: CheatCommand) {
        guard command.isLink else { return }

        if command.hasVariables {
            presentVariableForm(
                for: command,
                raw: command.rawCommand,
                variables: command.variables,
                outputFormat: .resolvedCommand,
                action: .openLink
            )
            return
        }

        openLink(copyText(for: command))
    }

    private func openLink(_ value: String) {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedValue), url.scheme != nil else {
            editorErrorMessage = "\"\(trimmedValue)\" is not a valid URL."
            return
        }

        guard NSWorkspace.shared.open(url) else {
            editorErrorMessage = "The link could not be opened."
            return
        }
        onRequestClose?()
    }

    private func writeToPasteboard(_ value: String, flashing commandID: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
        copiedCommandID = commandID

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            if self?.copiedCommandID == commandID {
                self?.copiedCommandID = nil
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
        selectedCommandIndex = min(selectedCommandIndex, max(0, visibleCommands.count - 1))
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
