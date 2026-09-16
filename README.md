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
| `Option-Return` | Open entry options (including **Open Link** for URL entries) |
| `Command-Return` | Copy the selected command without opening the variable form |
| `Command-C` | Copy the text you have selected (titles, descriptions, and commands are all selectable) |
| `Command-E` | Open the current Markdown file in the configured editor |
| `Command-F` | Focus search |
| `Command-,` | Open text-size settings |
| `Command-Shift-N` | Create a new cheat sheet and open it in the configured editor |
| `Command-Shift-M` | Open the More Options menu |
| `C` | Copy the full cheat-sheets directory path while More Options is open |
| `Escape` | Close the popover |

Popover width, editor, and the title, description, and command font sizes can be changed
from **More Options → Settings**. The choices are saved automatically. The editor can use
the system default, Visual Studio Code, TextEdit, or any custom application.

Right-click any entry to copy its title, its rendered plain-text description, or its
description with the original Markdown formatting. The same choices are available with
`Option-Return`. URL entries also offer **Open Link** in both menus.

## Edit cheat sheets

Use the More Options menu to open the folder or copy its full path. Files live at:

```text
~/Library/Application Support/Bar Cheat Sheets/CheatSheets/
```

Each Markdown file becomes a tab. Use an H1 for the tab name and H3 headings followed
by fenced code blocks for entries. Optional H2 headings divide entries into sections:

````markdown
# Git

### Amend the latest commit
An optional description can go here.

```sh
git commit --amend --no-edit
```
````

To divide a page into visual sections, use an H2 for each section and H3 headings for
the entries inside it. Section headings are not selectable commands:

````markdown
# Dashboards

## Trunk Validation dashboards

### TBwB

```url
https://dashboards.example.com/trunk/tbwb
```

## Service dashboards

### Production health

```url
https://dashboards.example.com/services/production
```
````

An H3 with description text but no fenced code block is also shown as an entry. Pressing
Return on that entry copies its description as plain text (with Markdown formatting removed).

Descriptions support inline Markdown, including `` `code` ``, `**bold**`, `*italic*`,
`~~strikethrough~~`, and `[links](https://example.com)`.

Use a `url` fence for a link entry. It supports a description and variables just like a
command. Return copies the URL; Option-Return offers to open it in the default application:

````markdown
## Service dashboards

### Production dashboard
Traffic, errors, and latency for the production service.

```url
https://dashboards.example.com/services/{{service=payments}}
```
````

Changes reload automatically. Two example files are created on first launch.

## Variables

Write `{{name=default}}` inside a code block — or in a description — to turn that part
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
| `Command-Return` | The same, and works even when no field has focus |
| `Escape` | Close the form without copying |

The live preview tints every substituted value, and the command list shows each command
with its current values already filled in.

Other details:

- `{{name}}` without an `=` declares a field that starts empty.
- Repeating a name reuses one field, so `{{branch}}` twice in a command is edited once.
  This spans the description and the command: the same `{{diff}}` in both is one field.
- Only the command is copied. A variable in a description keeps the note in step with
  the command — useful for recording the output dataset a run will produce.
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
