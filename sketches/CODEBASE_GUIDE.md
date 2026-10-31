# DittoBar codebase guide

This guide describes the refactored source tree. DittoBar is a macOS menu-bar app built with SwiftUI for content and AppKit for its floating panel, menus, and selectable text. It reads Markdown cheat sheets from a configurable folder and offers copy/open actions, search, and variable forms.

## Start here

Read these files in order to follow the app:

1. `Sources/DittoBar/App/Main.swift` starts `NSApplication` and its delegate.
2. `Sources/DittoBar/App/AppDelegate.swift` wires the menu-bar icon, panel, global hotkey, and keyboard routing.
3. `Sources/DittoBar/Main/MainView.swift` composes the header, search, entry list, footer, and presented forms/settings.
4. `Sources/DittoBar/Sheets/CheatSheetStore.swift` owns observable sheet, selection, search, variable-form, and feedback state.
5. `Sources/DittoBar/Sheets/Models.swift` defines entries, sections, sheets, and available actions.

The main interface is hosted in `CheatSheetPanel`, an `NSPanel`. It is not an `NSPopover`: the nonactivating panel can receive keyboard focus without activating the app, including over fullscreen applications.

## Project layout

```text
Package.swift                    Swift package definition
Sources/DittoBar/
  App/                           Startup, panel, menu, and keyboard integration
  Main/                          Main interface and entry list
  Sheets/                        Models, store, parsing, search, file access, actions
  Text/                          Markdown processing, rendering, fonts, selectable text
  Variables/                     Variable parsing, persistence, and form
  Settings/                      Settings tabs, preferences, editor launching
Tests/DittoBarTests/
  Sheets/                        Sheet logic, store integration, exports, execution
  Text/                          Markdown, syntax tokens, rendered text
  Variables/                     Variable resolution and saved values
  Settings/                      Preference defaults and ranges
Support/Info.plist               App bundle metadata
scripts/build-app.sh              Release build, bundle assembly, ad-hoc signing
README.md                        User-facing behavior and supported syntax
docs/GLOSSARY.md                 Definitions of the text forms
docs/MARKDOWN.md                 Markdown support
sketches/REFACTORING_PLAN.md      Refactoring sequence and validation record
```

All source subdirectories belong to the same `DittoBar` Swift module. SwiftPM discovers their files recursively; directory names do not introduce namespaces or separate targets. `Package.swift` specifies macOS 14+, Swift language mode 5, and the AppKit and Carbon frameworks. The package manifest uses Swift tools version 6.

The default sheet folder is `~/Library/Application Support/DittoBar/CheatSheets/`. A selected custom folder is used as-is. Starter content is created only for the default folder when it has no Markdown files.

## Ownership and dependencies

```text
AppDelegate
  ├─ CheatSheetPanel → MainView
  │                     ├─ EntryListView → EntryRow / SectionHeaderRow
  │                     ├─ VariableFormView
  │                     └─ SettingsView → individual settings tabs
  ├─ CopyOptionsMenuController
  ├─ HotKeyManager
  └─ CheatSheetStore
       ├─ DirectoryWatcher
       ├─ SheetFiles → CheatSheetParser → Models
       ├─ CheatSheetSearch
       ├─ TextVariables / EntryVariableStorage
       ├─ SectionMarkdownExporter
       ├─ EntryActionExecutor
       └─ EditorLauncher → EditorPreferences
```

`CheatSheetStore` remains the single owner of observable application state. Extracted collaborators accept explicit inputs and return data, errors, or outcomes. They do not share mutable selection state. View-local state, such as hover, search focus, selected settings tab, and picker presentation, stays with its view.

### App

| File | Responsibility |
| --- | --- |
| `Main.swift` | Entry point and application lifetime. |
| `AppDelegate.swift` | Status item, startup/shutdown, panel placement and visibility, focus restoration, local/global event-monitor lifetime, keyboard routing. |
| `CheatSheetPanel.swift` | Nonactivating floating window and SwiftUI hosting view. |
| `CopyOptionsMenuController.swift` | Entry/section action-menu construction, selection pinning, row-relative presentation, and menu action dispatch. |
| `HotKeyManager.swift` | Carbon registration and cleanup for global Option-Space. |
| `AppNotifications.swift` | Shared notification names for focusing search and opening More Options. |

The delegate owns the menu controller; the controller holds a weak panel reference. Menu presentation state prevents the delegate from closing the panel merely because a menu took keyboard focus.

### Main interface

| File | Responsibility |
| --- | --- |
| `MainView.swift` | Header and sheet tabs, search, footer, empty state, form/settings overlays, creation/error alerts. |
| `EntryListView.swift` | Rows, context menus, hover state, selection-driven scrolling, and scroll geometry. |
| `EntryRow.swift` | One entry's title, description, payload, copied state, and private badge helper. |
| `SectionHeaderRow.swift` | Section heading and collapsed indicator. |
| `MoreOptionsButton.swift` | Native menu for sheet/editor/folder commands, settings, and quit. |
| `SelectedRowAnchor.swift` | AppKit anchor view for row-relative menus and scroll-view lookup. |

`EntryRow` is equatable so changes to selection do not force every row to parse and render its text again. Its selection closure is deliberately excluded from equality: the compared entry determines what that closure selects.

`EntryListView` distinguishes pointer selection, keyboard selection, and held-key repeats. Pointer selection does not move the row under the pointer; repeat scrolling is immediate. Queued scroll work checks the selected item and query before acting, so newer input can supersede it.

### Sheets and actions

| File | Responsibility |
| --- | --- |
| `Models.swift` | Entry metadata, variables, note/command/URL/file entries, action enums, sections, items, and sheets. |
| `CheatSheetStore.swift` | Published state, filtering/collapse/selection, effective values, variable-form lifecycle, action coordination, reload orchestration, copied feedback, and errors. |
| `CheatSheetParser.swift` | Markdown source to sheet models. |
| `CheatSheetSearch.swift` | Matching and retention of relevant section headings. |
| `DirectoryWatcher.swift` | Filesystem event monitoring and debounced reload notification. |
| `SheetFiles.swift` | Markdown file enumeration/loading, new-sheet validation/writing, and initial starter files. |
| `StarterContent.swift` | Embedded starter sheets and new-sheet templates. |
| `SectionMarkdownExporter.swift` | Section export with resolved values and preserved Markdown formatting. |
| `EntryActionExecutor.swift` | Clipboard writes, URL/file opening, Finder reveal, path resolution, and joined copied texts. |

`SheetFiles.load` ignores hidden/non-Markdown files, sorts names naturally, and skips files it cannot read. Creating a sheet trims the proposed name, removes a trailing `.md` case-insensitively, rejects empty names and slashes, and refuses to overwrite an existing file.

The store chooses which entries belong to a section action, including search and collapse semantics. The exporter receives those entries and their effective values. It writes URL values as bare lines, file paths in `file` fences, and command fences longer than any backtick run in the content.

`EntryActionExecutor` returns `.copied`, `.opened`, or `.failed(message)`. The store decides whether to flash copied entries, close the panel, or show an error. Bulk opens attempt every item and close only when all succeeded; the last failure is retained. The executor accepts opening/reveal closures, a pasteboard, and a file manager so tests can verify outcomes without launching external applications or replacing the user's clipboard.

### Text processing and rendering

| File | Responsibility |
| --- | --- |
| `MarkdownText.swift` | Markdown stripping and block/inline interpretation. |
| `MarkdownDescriptionView.swift` | SwiftUI composition of descriptions, notes, tables, lists, and quotes. |
| `EntryTextStyle.swift` | Attributed strings for titles, Markdown, payloads, variables, syntax colors, and rendering caches. |
| `SelectableText.swift` | Selectable AppKit label, text-field sizing, click notification, and inline-code background drawing. |
| `InlineCodeStyle.swift` | Shared inline-code attribute key, insets, and minimum line spacing. |
| `EntryFonts.swift` | Font resolution, fallbacks, and installed-family lists. |
| `SyntaxHighlighter.swift` | Language-aware tokenization and UTF-16 ranges. |
| `Theme.swift` | App accent and shared panel fill. |

Use the terms from `docs/GLOSSARY.md`:

- **raw**: the source text, including Markdown and variable placeholders.
- **resolved**: variable placeholders replaced by effective values.
- **markdownStripped**: resolved text with Markdown syntax removed.
- **markdownRendered**: resolved text displayed with Markdown formatting.

Copy actions select the appropriate text form; rendering is not the source of copied text. Variables retain the app's orange accent even where syntax highlighting would otherwise assign a token color.

`SelectableText` uses `NSTextField` because text selection needs a real first responder for Command-C. Its private subclasses notify the row before AppKit processes the click and draw rounded inline-code backgrounds without inserting characters into copied content. `InlineCodeStyle` keeps measurement and rendering constants aligned.

### Variables

| File | Responsibility |
| --- | --- |
| `TextVariables.swift` | Parse `{{name=default}}`, resolve values, and retain variable provenance in segments. |
| `EntryVariableStorage.swift` | Persist remembered values by stable entry storage key. |
| `VariableFormState.swift` | Form data, output, preview segments, and default comparison. |
| `VariableFormView.swift` | Variable fields, preview, reset, cancel, and confirmation UI. |

The store caches remembered values for repeated row reads and refreshes them during reload. Closing the main panel keeps an unfinished variable form; cancelling it explicitly clears it. Confirming saves values and resumes the pending action.

### Settings and editor integration

| File | Responsibility |
| --- | --- |
| `SettingsView.swift` | Sidebar navigation and the shared `SettingsPane` detail/footer layout. |
| `LayoutSettingsView.swift` | Panel width preference and reset. |
| `TextSettingsView.swift` | Font families/sizes, private font controls, and reset. |
| `SheetsSettingsView.swift` | Folder picker, folder errors, and default-folder reset. |
| `EditorSettingsView.swift` | Editor preferences, application picker, new-sheet instruction preference, and reset. |
| `ShortcutsSettingsView.swift` | Shortcut data and private keycap rendering helpers. |
| `DisplayPreferences.swift` | Display preference keys, defaults, and ranges. |
| `EditorPreferences.swift` | Editor options, preference keys, and selected values. |
| `EditorLauncher.swift` | Application lookup, configured-editor launching, and launch errors. |

Each settings tab owns its preference wrappers and local picker state. `SettingsPane` provides consistent spacing and Reset/Done controls; tabs provide their default comparison and reset action.

Persisted keys are compatibility boundaries. The Swift identifier `panelWidthFractionKey` still stores `display.popoverWidthFraction`; `payloadFontSizeKey` still stores `display.commandFontSize`. Renaming a Swift property must not reset a user's saved preferences.

`EditorLauncher.open` throws if no editor can be found and reports later launch errors through a main-actor callback. The store captures itself weakly when displaying that error. A successfully launched editor is activated, matching the original behavior.

## Swift concepts for Python readers

- `struct` is a value type, suitable for models and SwiftUI views. `class` has reference identity, suitable for the store, delegate, and native controls.
- `enum` can hold associated values: `CheatSheetEntry.command(CommandEntry)` is a typed variant, not just a string label. `switch` makes handling variants explicit.
- `@Published` exposes changes from an observable object. `@ObservedObject` lets a view follow that object; the view does not own a duplicate model.
- `@State` holds local view state. `@Binding` connects a child to an existing value. `@AppStorage` bridges a preference to `UserDefaults`.
- `@MainActor` serializes UI-related access on the main actor. Filesystem results and asynchronous callbacks must update UI state there.
- `[weak self]` prevents an escaping callback from keeping its owner alive unnecessarily.
- A `private` declaration is intentionally restricted. The refactor makes extracted component types internal only where other files need them; private store state stays private.
- SwiftUI's `body` describes a view tree. AppKit owns imperative window/menu/control behavior. `NSViewRepresentable` bridges the two.

## Follow an action through the code

1. The delegate receives Return and calls `performPrimaryActionForSelectedEntry`.
2. The store identifies the selected entry and action. For a section, Return toggles collapse.
3. If the entry requires variables, the store presents `VariableFormState` and `MainView` shows `VariableFormView`.
4. Confirmation saves effective values and resolves the requested text form.
5. The executor performs the copy/open/reveal operation and returns an outcome.
6. The store applies copied feedback, close requests, or error state. Views observe these changes.

For loading: the watcher or panel opening requests a store reload; `SheetFiles` reads/parses the folder; the store restores selection and recomputes visible items. Search and collapse state remain store concerns.

## Verification and development

```sh
swift test
./scripts/build-app.sh
open dist/DittoBar.app
```

The build script creates an ad-hoc-signed release app under `dist/`. SwiftPM's build products are under `.build/`. Neither directory belongs in source control.

The test directories mirror responsibilities. Store tests cover search, collapse, selection, directory switching, and export integration. Dedicated file/export/executor tests cover their extracted boundaries. `EntryTextStyleTests` owns the variable-tint rendering assertion; tokenizer tests remain in `SyntaxHighlighterTests`.

After changing views or AppKit integration, also check search and sheet navigation, key-repeat scrolling, selected text copy, row-relative menus, variable forms, settings tabs/pickers, panel focus/dismissal, and fullscreen behavior. Unit tests do not establish those visual and responder-chain behaviors.

Keep mechanical moves separate from behavior changes. Prefer collaborators with explicit inputs and outcomes; avoid scattering store methods across extensions that require exposing private state. Cohesive files such as the parser, tokenizer, and starter content do not need splitting just to meet a line-count target.
