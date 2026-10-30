# DittoBar refactoring plan

## Objective

Give the source tree clear homes for related code and split files where they contain distinct responsibilities. Preserve behavior, keyboard shortcuts, rendering, saved preferences, and sheet formats. Use `MainView` for the main interface and “panel” for its hosting window and user-facing terminology.

This document proposes commits; it does not create them. The naming changes in commit 1 are already in the working tree. The remaining refactoring is planned work.

## Proposed structure

```text
Sources/DittoBar/
  App/
    Main.swift
    AppDelegate.swift
    CheatSheetPanel.swift
    CopyOptionsMenuController.swift
    HotKeyManager.swift
    AppNotifications.swift
  Main/
    MainView.swift
    EntryListView.swift
    EntryRow.swift
    SectionHeaderRow.swift
    MoreOptionsButton.swift
    SelectedRowAnchor.swift
  Sheets/
    Models.swift
    CheatSheetStore.swift
    CheatSheetParser.swift
    CheatSheetSearch.swift
    SheetFiles.swift
    SectionMarkdownExporter.swift
    EntryActionExecutor.swift
    DirectoryWatcher.swift
    StarterContent.swift
  Text/
    MarkdownText.swift
    MarkdownDescriptionView.swift
    SelectableText.swift
    EntryTextStyle.swift
    EntryFonts.swift
    InlineCodeStyle.swift
    SyntaxHighlighter.swift
    Theme.swift
  Variables/
    TextVariables.swift
    EntryVariableStorage.swift
    VariableFormState.swift
    VariableFormView.swift
  Settings/
    SettingsView.swift
    LayoutSettingsView.swift
    TextSettingsView.swift
    SheetsSettingsView.swift
    EditorSettingsView.swift
    ShortcutsSettingsView.swift
    DisplayPreferences.swift
    EditorPreferences.swift
    EditorLauncher.swift
```

Small private helpers stay with their owning component. For example, keep `EntryBadge` with `EntryRow`, shortcut models and key labels with `ShortcutsSettingsView`, and AppKit text-field subclasses with `SelectableText`. These are directories within the existing Swift package target, not new modules.

## Commit 1 — Rename the main view and panel terminology

Suggested message: `refactor: rename PopoverView to MainView`

- Rename the file and type to `MainView` and update `AppDelegate`.
- Rename width-related Swift identifiers to `panelWidthFraction`, and use “Panel Width” in Settings.
- Update current README and glossary terminology.
- Retain the persisted `display.popoverWidthFraction` key so saved widths survive.
- Retain references to the actual `NSPopover` API in the explanation of why the app uses an `NSPanel`.

Validation: run `swift test`; inspect the diff for accidental behavior changes. Confirm a previously saved panel width still loads and the settings label reads “Panel Width”.

## Commit 2 — Group existing source files by responsibility

Suggested message: `refactor: organize sources into feature directories`

- Move existing files into the directories above without extracting types yet.
- Put `MainView` in `Main/`, `DisplaySettingsView` in `Settings/`, and `Models` in `Sheets/`.
- Leave root packaging files, `Support/Info.plist`, and `scripts/build-app.sh` in their existing locations.
- Check build scripts and documentation for source-path references that need updating. SwiftPM currently discovers the target sources without an explicit file list.

Validation: run `swift test` and review rename detection. This commit should contain moves and necessary path updates only.

## Commit 3 — Extract the main interface's existing components

Suggested message: `refactor: extract main view components`

- Extract `EntryRow`, `SectionHeaderRow`, `MoreOptionsButton`, and `SelectedRowAnchor` into `Main/`.
- Move `MarkdownDescriptionView` into `Text/`.
- Move shared notification names into `App/AppNotifications.swift`.
- Keep `EntryBadge` private beside `EntryRow`. Give the small shared panel styling value a deliberate home in `Theme.swift` if multiple extracted views need it.
- Preserve `EntryRow`'s equality comparison, including its deliberate exclusion of the selection closure.
- Change visibility only for declarations that must cross file boundaries.

Validation: run `swift test`. Manually check row selection, copied feedback, section collapse, Markdown tables/lists/quotes, and the More Options menu opened by mouse and keyboard.

## Commit 4 — Give entry-list scrolling a single owner

Suggested message: `refactor: isolate entry list and scrolling behavior`

- Extract the entry list, scroll geometry, animation helpers, and related local state into `EntryListView`.
- Keep the main header, search, footer, settings presentation, and overall composition in `MainView`.
- Preserve the distinction between pointer selection, keyboard movement, and key repeat; preserve selected-row anchoring for action menus.
- Pass only state and actions required by the list. Avoid a second source of truth for selection.

Validation: run `swift test`. Manually check search changes, switching sheets, held arrow keys, first/last entries, collapsed sections, and action-menu positioning after scrolling.

## Commit 5 — Separate text rendering from selectable controls

Suggested message: `refactor: separate entry text styling from AppKit controls`

- Extract `EntryTextStyle` from `SelectableText.swift`.
- Move `EntryFonts` out of `DisplayPreferences.swift` into `Text/EntryFonts.swift`.
- Put shared inline-code attribute and layout constants in `InlineCodeStyle`; both rendering and drawing should consume the same values.
- Keep text-field subclasses private to `SelectableText.swift` where possible.
- Preserve rendering cache keys, cache limits, variable highlighting, and the raw/resolved/markdownStripped/markdownRendered distinctions from the glossary.
- Keep `MarkdownText` and `SyntaxHighlighter` intact: each already has a cohesive purpose.

Validation: run `swift test`. Manually check selectable text and Command-C, inline-code backgrounds, wrapping, links, syntax highlighting, font changes, and variable emphasis.

## Commit 6 — Split Settings into tab views

Suggested message: `refactor: extract settings tab views`

- Rename `DisplaySettingsView` to `SettingsView` and update references.
- Extract layout, text, sheets, editor, and shortcuts tabs into the corresponding views.
- Keep sidebar navigation and shared layout in `SettingsView`.
- Place font controls with `TextSettingsView` and shortcut data/key rendering with `ShortcutsSettingsView`.
- Give each tab clear ownership of its preferences, file pickers, and errors. Preserve the existing per-tab reset behavior and avoid duplicate preference state.

Validation: run `swift test`. Exercise every tab, reset-to-defaults behavior, folder selection, editor selection, cancellation, and preference persistence across relaunch.

## Commit 7 — Extract sheet file operations and editor launching

Suggested message: `refactor: extract sheet file access and editor launching`

- Add `SheetFiles` for directory enumeration, loading/parsing files, initial content creation, and new-sheet validation/writing.
- Add `EditorLauncher` for application lookup and asynchronous opening through `NSWorkspace`.
- Keep active folder selection, watcher lifecycle, published state, selected-sheet restoration, and user-facing error state in `CheatSheetStore`.
- Pass folder URLs, preferences, and `FileManager` explicitly where needed. Return results/errors so the store remains responsible for UI updates.
- Preserve ordering, existing unreadable-file handling, non-overwrite behavior, and the rule that choosing an existing folder does not populate it with starter content.
- Keep `StarterContent` as Swift content for now; converting it into bundled resources is separate work.

Validation: run the existing suite, especially sheets-directory and starter-content tests. Move or extend behavioral tests for file operations as appropriate. Manually verify watcher reloads, new-sheet creation, editor failures, and custom editor launching.

## Commit 8 — Extract section Markdown generation

Suggested message: `refactor: extract section markdown exporter`

- Move section Markdown serialization and fence selection into `SectionMarkdownExporter`.
- Supply the selected entries and effective variable values explicitly; keep visible-entry selection and collapsed/search semantics in the store.
- Preserve resolved text, bare URLs, file fences, language identifiers, and fences longer than embedded backtick runs.
- Move existing relevant assertions into focused exporter tests, adding missing edge cases only where useful.

Validation: run `swift test`; verify section export with variables, multiline content, embedded fences, URL entries, and file entries.

## Commit 9 — Separate action execution from store state

Suggested message: `refactor: extract entry action execution`

- Extract clipboard writes, URL/file opening, and path resolution into `EntryActionExecutor`.
- Keep variable-form presentation, selection, copied-entry feedback timing, close requests, and published errors in `CheatSheetStore`.
- Let the executor return meaningful outcomes so the store controls feedback and dismissal. Avoid callbacks that expose arbitrary store internals.
- Reuse execution primitives for section actions while preserving multi-entry copy/open behavior and separators.
- Move `VariableFormState` from `Models.swift` into `Variables/`.
- Preserve actor isolation, weak captures, and asynchronous UI updates.

Validation: run `swift test`. Add focused behavior tests around extracted transformations and outcomes where existing tests do not cover them. Manually verify primary/alternate actions, variable confirmation/cancellation, remembered values, relative/absolute/tilde paths, failed opens, copied feedback, and panel dismissal.

## Commit 10 — Reduce AppDelegate to application coordination

Suggested message: `refactor: extract panel and copy options menu`

- Move `CheatSheetPanel` into its own file.
- Extract copy-options menu construction, displayed action storage, and menu presentation into `CopyOptionsMenuController`.
- Keep application startup/shutdown, status-item setup, panel visibility, focus restoration, and event-monitor lifetime in `AppDelegate`.
- Preserve responder-chain behavior and menu keyboard equivalents. Keep keyboard routing together unless a further extraction has a clear, independent interface.

Validation: run `swift test`. Manually check Option-Space, outside clicks, Escape, focus restoration, fullscreen use, copy-menu selection, and editing shortcuts inside text fields.

## Commit 11 — Align tests and documentation with the final structure

Suggested message: `docs: align codebase guide and tests with refactoring`

- Group tests under matching feature directories where this improves navigation.
- Review `CheatSheetStoreSearchTests`: move assertions for extracted responsibilities into appropriately named suites, leaving store selection/search integration tests together.
- Update `sketches/CODEBASE_GUIDE.md` to describe the final ownership and paths. Check README and other maintained documentation for stale names.
- Record any deliberately retained historical terms, especially the saved width key.
- Check that the store remains the sole owner of observable application state and that extraction has not merely spread shared mutable state across files.

Validation: run the complete test suite and `scripts/build-app.sh`. Smoke-test the packaged app's main flows once all changes are integrated. Confirm no unintended package/resource changes and review the final diff.

## Implementation constraints

- Implement commits in order; each should compile and pass the existing suite independently.
- Keep directory moves separate from substantial extraction to make review and history easier.
- Prefer small collaborators with explicit inputs over cross-file extensions that require broadening private store state.
- Preserve behavior during extraction. Record unrelated bugs or feature ideas separately.
- Do not target a fixed line limit or create a separate file for every tiny helper. Stop splitting when a file has one clear responsibility.
- Use meaningful existing tests for mechanical moves; reserve new tests for behavioral boundaries and uncovered edge cases. Rendering, focus, scrolling, and menu behavior also need manual verification.
