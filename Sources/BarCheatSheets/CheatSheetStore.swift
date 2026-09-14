import AppKit
import Foundation

@MainActor
final class CheatSheetStore: ObservableObject {
    @Published private(set) var sheets: [CheatSheet] = []
    @Published var selectedSheetIndex = 0
    @Published var selectedCommandIndex = 0
    @Published var query = ""
    @Published private(set) var copiedCommandID: String?
    @Published var editorErrorMessage: String?

    let folderURL: URL
    var onRequestClose: (() -> Void)?

    private var watcher: DirectoryWatcher?

    init(fileManager: FileManager = .default) {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        folderURL = applicationSupport
            .appendingPathComponent("Bar Cheat Sheets", isDirectory: true)
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
            $0.title.localizedCaseInsensitiveContains(trimmedQuery)
                || $0.detail.localizedCaseInsensitiveContains(trimmedQuery)
                || $0.command.localizedCaseInsensitiveContains(trimmedQuery)
        }
    }

    var selectedCommand: CheatCommand? {
        let commands = visibleCommands
        guard commands.indices.contains(selectedCommandIndex) else { return nil }
        return commands[selectedCommandIndex]
    }

    func selectSheet(at index: Int) {
        guard sheets.indices.contains(index) else { return }
        selectedSheetIndex = index
        selectedCommandIndex = 0
    }

    func moveSelection(by offset: Int) {
        let count = visibleCommands.count
        guard count > 0 else {
            selectedCommandIndex = 0
            return
        }
        selectedCommandIndex = (selectedCommandIndex + offset + count) % count
    }

    func copySelectedCommand() {
        guard let selectedCommand else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(selectedCommand.command, forType: .string)
        copiedCommandID = selectedCommand.id

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            if self?.copiedCommandID == selectedCommand.id {
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

    func openSelectedSheetInVSCode() {
        guard let sourceURL = selectedSheet?.sourceURL else {
            NSSound.beep()
            return
        }

        let bundleIdentifiers = [
            "com.facebook.fbvscode",
            "com.facebook.fbvscode-dev",
            "com.facebook.fbvscode-insiders",
            "com.microsoft.VSCode",
            "com.microsoft.VSCodeInsiders"
        ]
        let applicationURL = bundleIdentifiers.compactMap({
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
        }).first ?? knownVSCodeLocations().first(where: {
            FileManager.default.fileExists(atPath: $0.path)
        })

        guard let applicationURL else {
            editorErrorMessage = "VS Code could not be found in Applications."
            return
        }

        NSWorkspace.shared.open(
            [sourceURL],
            withApplicationAt: applicationURL,
            configuration: NSWorkspace.OpenConfiguration()
        ) { [weak self] _, error in
            guard let error else { return }
            DispatchQueue.main.async {
                self?.editorErrorMessage = error.localizedDescription
            }
        }
    }

    private func knownVSCodeLocations() -> [URL] {
        let applications = URL(fileURLWithPath: "/Applications", isDirectory: true)
        return [
            "VS Code @ FB.app",
            "VS Code @ FB - Dev.app",
            "VS Code @ FB - Insiders.app",
            "Visual Studio Code.app",
            "Visual Studio Code - Insiders.app"
        ].map { applications.appendingPathComponent($0, isDirectory: true) }
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

        let vimSample = """
        # Vim

        ## Move left, down, up, right
        Basic Normal-mode movement.

        ```text
        h  j  k  l
        ```

        ## Move by word
        Next word, previous word, and end of word.

        ```text
        w  b  e
        ```

        ## Move within a line
        Start, first non-blank character, and end of line.

        ```text
        0  ^  $
        ```

        ## Jump through the file
        First line, last line, or a specific line.

        ```text
        gg  G  :{line}
        ```

        ## Enter Insert mode
        Before/after the cursor, or on a new line below/above.

        ```text
        i  a  o  O
        ```

        ## Delete, change, or yank a motion
        Combine an operator with a motion; double it for the whole line.

        ```text
        d{motion}  c{motion}  y{motion}  dd  cc  yy
        ```

        ## Paste
        Paste after or before the cursor.

        ```text
        p  P
        ```

        ## Undo, redo, and repeat

        ```text
        u  Ctrl-r  .
        ```

        ## Search and repeat
        Search forward/backward, then move to the next/previous match.

        ```text
        /pattern  ?pattern  n  N
        ```

        ## Replace throughout the file
        Confirm each replacement.

        ```vim
        :%s/old/new/gc
        ```

        ## Select text visually
        Character, line, or block selection.

        ```text
        v  V  Ctrl-v
        ```

        ## Save and quit

        ```vim
        :w  :q  :wq  :q!
        ```

        ## Switch buffers
        Next, previous, list, or choose a buffer.

        ```vim
        :bn  :bp  :ls  :b {name}
        ```

        ## Record and replay a macro
        Record into register a, stop, then replay it.

        ```text
        qa  q  @a  @@
        ```
        """

        try? vimSample.write(
            to: folderURL.appendingPathComponent("vim.md"),
            atomically: true,
            encoding: .utf8
        )

        let gitSample = """
        # Git

        ## See repository status
        Show the current branch and staged, unstaged, and untracked files.

        ```sh
        git status --short --branch
        ```

        ## Review unstaged changes
        Inspect changes in the working tree before staging them.

        ```sh
        git diff
        ```

        ## Review staged changes
        Inspect exactly what will be included in the next commit.

        ```sh
        git diff --staged
        ```

        ## Stage selected changes
        Interactively choose individual hunks to stage.

        ```sh
        git add --patch
        ```

        ## Commit staged changes
        Create a commit with a concise message.

        ```sh
        git commit -m "message"
        ```

        ## Amend the latest commit
        Add staged changes without changing the commit message.

        ```sh
        git commit --amend --no-edit
        ```

        ## View compact history
        Show a decorated branch graph for all local and remote branches.

        ```sh
        git log --oneline --graph --decorate --all
        ```

        ## Create and switch to a branch

        ```sh
        git switch -c <branch>
        ```

        ## Switch branches

        ```sh
        git switch <branch>
        ```

        ## Update the current branch
        Fetch from its remote and replay local commits on top.

        ```sh
        git pull --rebase
        ```

        ## Push a new branch
        Publish the branch and remember its upstream.

        ```sh
        git push -u origin HEAD
        ```

        ## Temporarily stash changes
        Include untracked files and label the stash for easier recovery.

        ```sh
        git stash push -u -m "work in progress"
        ```

        ## Restore the latest stash
        Apply the most recent stash and remove it from the stash list.

        ```sh
        git stash pop
        ```

        ## Unstage a file
        Keep the working-tree changes while removing the file from the index.

        ```sh
        git restore --staged <file>
        ```

        ## Discard a file's changes
        Replace an unstaged file with its last committed version. This cannot be undone by Git.

        ```sh
        git restore <file>
        ```

        ## Revert a published commit
        Make a new commit that safely reverses an earlier commit.

        ```sh
        git revert <commit>
        ```

        ## Find a lost commit
        Inspect recent HEAD movements after a reset, rebase, or deleted branch.

        ```sh
        git reflog
        ```

        ## Show who changed each line

        ```sh
        git blame <file>
        ```

        ## Search commit messages

        ```sh
        git log --grep="text" --oneline
        ```
        """

        try? gitSample.write(
            to: folderURL.appendingPathComponent("git.md"),
            atomically: true,
            encoding: .utf8
        )
    }
}
