# Bar Cheat Sheets

A keyboard-first macOS menu-bar utility for commands stored in Markdown files.

## Run it

Requires macOS 14 or newer and Xcode command-line tools.

```sh
swift run --disable-sandbox
```

The menu-bar icon and global `Option-Space` shortcut both toggle the popover.

To build a standalone application:

```sh
./scripts/build-app.sh
open "dist/Bar Cheat Sheets.app"
```

## Keyboard controls

| Key | Action |
| --- | --- |
| `Option-Space` | Open or close the popover globally |
| `Command-1` … `Command-9` | Select a cheat-sheet tab |
| `Command-Option-Left` / `Command-Option-Right` | Select the previous or next cheat-sheet tab |
| `Tab` / `Shift-Tab` | Select the next or previous command |
| `Up` / `Down` | Select the previous or next command |
| `Return` | Copy the selected command, or open its variable form |
| `Command-Return` | Copy the selected command without opening the variable form |
| `Command-C` | Copy the text you have selected (titles, descriptions, and commands are all selectable) |
| `Command-E` | Open the current Markdown file in VS Code |
| `Command-F` | Focus search |
| `Command-Shift-N` | Create a new cheat sheet and open it in VS Code |
| `Command-Shift-M` | Open the More Options menu |
| `C` | Copy the full cheat-sheets directory path while More Options is open |
| `Escape` | Close the popover |

## Edit cheat sheets

Use the More Options menu to open the folder or copy its full path. Files live at:

```text
~/Library/Application Support/Bar Cheat Sheets/CheatSheets/
```

Each Markdown file becomes a tab. Use an H1 for the tab name and an H2 followed by a fenced code block for every command:

````markdown
# Git

## Amend the latest commit
An optional description can go here.

```sh
git commit --amend --no-edit
```
````

Changes reload automatically. Two example files are created on first launch.

## Variables

Write `{{name=default}}` anywhere inside a code block to turn that part of the command
into an editable field:

````markdown
## Run the pipeline locally

```sh
dataswarm-cli daemon execute -- tester --verbose pipeline.py \
  {{date=2026-09-15}} --local-run -b "test_{{diff=D120155593}}_"
```
````

Copying that command with `Return` opens a form instead of copying straight away:

| Key | Action |
| --- | --- |
| `Tab` / `Shift-Tab` | Move between fields |
| `Return` | Copy the filled-in command and close the form |
| `Escape` | Close the form without copying |

The live preview tints every substituted value, and the command list shows each command
with its current values already filled in.

Other details:

- `{{name}}` without an `=` declares a field that starts empty.
- Repeating a name reuses one field, so `{{branch}}` twice in a command is edited once.
- Values you enter are remembered per command and pre-fill the form next time.
  **Reset to Defaults** restores what the Markdown says.
- `Command-Return` skips the form and copies using the current values.

## Comments

Anything inside an HTML comment is ignored, including headings and code fences, so a
file can carry its own instructions:

```markdown
<!--
Notes to self. Nothing in here becomes a command.
-->
```

New cheat sheets are created with a comment at the top explaining the format, the
variable syntax, and the keyboard shortcuts.
