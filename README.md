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
| `Tab` / `Shift-Tab` | Select the next or previous command |
| `Up` / `Down` | Select the previous or next command |
| `Command-C` | Copy the selected command |
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
