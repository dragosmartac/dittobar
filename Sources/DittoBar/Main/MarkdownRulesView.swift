import SwiftUI

struct MarkdownRulesView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Markdown Rules")
                .font(.title2.bold())

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Sheet structure").font(.headline)
                        example("# Sheet title\n## Section\n### Entry title")
                        Text("There are multiple types of entries. Usually you can start typing immediately after the entrie's title. For a command, URL, or file entry add a fenced block like this:")
                        example("```sh\ngit switch {{branch=main}}\n```")
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Notes and descriptions").font(.headline)
                        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 18, verticalSpacing: 10) {
                            rule("Emphasis", "**bold**   *italic*   ***both***")
                            rule("Other styles", "~~strikethrough~~   `inline code`")
                            rule("Link", "[label](https://example.com)")
                            rule("Quote", "> quoted text")
                            rule("Lists", "- bullet   1. numbered   - [x] done")
                            rule("Table", "| Name | Value |\n| --- | --- |\n| Branch | main |")
                        }
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Variables").font(.headline)
                        example("{{branch=main}}   {{branch}}")
                        Text("The default value should be set only once per variable. Reuse the variable name as much as you want in the content or description.")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 530, height: 550)
        .onExitCommand { dismiss() }
    }

    private func rule(_ label: String, _ syntax: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            example(syntax)
        }
    }

    private func example(_ syntax: String) -> some View {
        Text(verbatim: syntax).font(.system(.callout, design: .monospaced))
    }
}
