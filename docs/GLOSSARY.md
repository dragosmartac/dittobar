# Glossary

## Text processing levels

An entry has multiple text properties (e.g. description, command). Each of them can appear in multiple forms in the code, depending on where it is used. The table below describes the terms used throughout the codebase.

| Form | Name | Description example | Command example | Explanation |
|---|---|---|---|---|
| 1 | **raw** | `Deploy **{{service=api}}**` | `deploy {{env=staging}}` | The text exactly as written in the Markdown file |
| 2 | **resolved** | `Deploy **payments**` | `deploy prod` | All variables replaced by their values |
| 3 | **markdownStripped** | `Deploy payments` | — | All variables replaced by their values and Markdown syntax stripped |
| 4 | **markdownRendered** | Deploy **payments** (styled in the popover) | — | All variables replaced by their values and Markdown applied as formatting (bold, italic, code, links) |

## Entries

| Term | Meaning |
|---|---|
| **command entry** | An H3 followed by a fenced block other than `url` or `file` |
| **URL entry** | An H3 followed by a `url` fenced block. Return opens the URL |
| **file entry** | An H3 followed by a `file` fenced block holding a path: absolute, starting with `~`, or relative to the cheat-sheets folder. Return opens the file |
| **note entry** | An H3 followed by content but no fenced block |
