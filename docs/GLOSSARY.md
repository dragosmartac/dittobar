# Glossary

## Text processing levels

An entry has multiple text properties (e.g. description, command). Each of them can appear in multiple forms in the code, depending on where it is used. The table below describes the terms used throughout the codebase.

| Form | Name | Description example | Command example | Explanation |
|---|---|---|---|---|
| 1 | **raw** | `Deploy **{{service=api}}**` | `deploy {{env=staging}}` | The text exactly as written in the Markdown file |
| 2 | **resolved** | `Deploy **payments**` | `deploy prod` | All variables replaced by their values |
| 3 | **resolvedMarkdownStripped** | `Deploy payments` | — | All variables replaced by their values and Markdown syntax stripped |
| 4 | **resolvedMarkdownRendered** | Deploy **payments** (styled in the popover) | — | All variables replaced by their values and Markdown applied as formatting (bold, italic, code, links) |
