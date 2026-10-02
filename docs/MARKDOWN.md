# Markdown in descriptions and notes

Some text components support Markdown rendering (e.g. descriptions in Command or URL entries or the content of a Note). The current document highlights the supported behaviour.

## Supported formatting

| Type | Or | What you get |
| --- | --- | --- |
| `*Italic*` | `_Italic_` | *Italic* |
| `**Bold**` | `__Bold__` | **Bold** |
| `***Bold italic***` | `___Bold italic___` | ***Bold italic*** |
| `~~Strikethrough~~` | | ~~Strikethrough~~ |
| `` `Inline code` `` | | `Inline code` |
| `[Link](https://example.com)` | | [Link](https://example.com) |
| `<https://example.com>` | bare `https://example.com` | https://example.com |
| `` `\*Not italic\*` `` | | \*Not italic\* |

Additional notes:

- Styles can nest and combine: `**bold with *italic* inside**`, `` **bold with `code` inside** ``,
  and `**[bold link](https://example.com)**` all render as expected.
- Formatting inside `` `code` `` stays literal: `` `**not bold**` `` renders as `**not bold**`.
- `*...*` applies inside words (`foo*bar*baz`), but `_..._` never does (`foo_bar_baz` stays
  literal). This matches CommonMark.
- HTML entities such as `&amp;` are decoded (`&`).

## Links

- `[Text](https://example.com)` renders `Text` as a clickable link. An optional link title
  (`[Text](url "title")`) is accepted and ignored.
- Destinations without a scheme get `https://` prepended: `[Text](www.example.com)` opens
  `https://www.example.com`. This also applies to relative destinations, so prefer full URLs.
- Bare `https://example.com`, bare `www.example.com`, and email addresses (`user@example.com`,
  `<user@example.com>`) become links automatically.
- `[Text](#fragment)` and `[Text]()` render as plain text with no link.
- Copying as text keeps only the link text (`[Text](url)` copies as `Text`); copying as
  Markdown keeps the full `[Text](url)` syntax. Autolinks keep their text either way.

## Variables

Placeholders are resolved before Markdown is parsed, so formatting can wrap a placeholder
(`Deploy **{{service=api}}**`) and formatting inside a substituted value is interpreted.

## Not supported

Only inline formatting is rendered. The following have no effect as formatting:

- `> quote`, `- item`, `1. item`, and `---` are ordinary description text, shown literally.
- Headings (`#`, `##`, `###`) and fenced code blocks (```` ``` ````) cannot appear inside a
  description or note at all: they close the current entry and start a sheet title, section,
  entry, or payload instead.
- Reference links (`[text][ref]`) are shown literally; use inline `[text](url)` links.
- Images (`![alt](url)`) render as their alt text only: no image and no link.
- Inline HTML (`<b>hi</b>`) is shown literally.

## Copying

- Command and URL entries offer **Copy Description** (markdownStripped) and
  **Copy Description as Markdown** (resolved).
- Note entries offer **Copy Content** (markdownStripped, the `Return` key action) and
  **Copy Content as Markdown** (resolved).
- markdownStripped drops the markers: `**bold**` copies as `bold`, `` `code` `` as `code`,
  `[Text](url)` as `Text`, and `![alt](url)` as `alt`.
- Unclosed or invalid markers (`**oops`) are copied literally in both forms.
