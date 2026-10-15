# Glossary

## Text processing levels

An entry has multiple text properties (e.g. description, command). Each of them can appear in multiple forms in the code, depending on where it is used. The table below describes the terms used throughout the codebase.

| Form | Name | Description example | Command example | Explanation |
|---|---|---|---|---|
| 1 | **raw** | `Deploy **{{service=api}}**` | `deploy {{env=staging}}` | The text exactly as written in the Markdown file |
| 2 | **resolved** | `Deploy **payments**` | `deploy prod` | All variables replaced by their values |
| 3 | **markdownStripped** | `Deploy payments` | — | All variables replaced by their values and Markdown syntax stripped |
| 4 | **markdownRendered** | Deploy **payments** (styled in the popover) | — | All variables replaced by their values and Markdown applied as formatting (bold, italic, code, links) |

## Todos

| Term | Meaning |
|---|---|
| **todo** | A task list item (`- [ ] Text`). Outside an entry it is an entry of its own; inside an entry's description or note it stays part of that text |
| **token** | A word in a todo's text that sets its metadata rather than being part of it: `!1`–`!3` (**priority**), `#tag` (**tag**), `due:YYYY-MM-DD`, `done:YYYY-MM-DD` |
| **rawItemText** | The text after a todo's checkbox exactly as written, tokens included |
| **rawText** | A todo's `rawItemText` without its tokens. The forms above (resolved, markdownStripped, markdownRendered) apply to it |
| **Todos tab** | The first tab, which gathers todos from every sheet. It has no file of its own |
