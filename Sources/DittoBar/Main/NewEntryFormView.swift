import SwiftUI

struct NewEntryFormView: View {
    @ObservedObject var store: CheatSheetStore
    @ObservedObject var form: NewEntryFormState
    @FocusState private var titleFocused: Bool

    private enum Spacing {
        static let section: CGFloat = 16
        static let compact: CGFloat = 8
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.section) {
            if form.isMarkdownHelpPresented {
                MarkdownRulesContent(showsSheetStructure: false)
            } else {
                entryFieldsView
            }
            Divider()
            HStack(alignment: .bottom, spacing: Spacing.compact) {
                if !form.isMarkdownHelpPresented {
                    footerHints
                }
                Spacer()
                if !form.isMarkdownHelpPresented {
                    Button("Cancel", role: .cancel) { store.cancelNewEntry() }
                        .keyboardShortcut(.cancelAction)
                }
                Button {
                    if form.isMarkdownHelpPresented {
                        form.isMarkdownHelpPresented = false
                    } else {
                        store.saveNewEntry()
                    }
                } label: {
                    Text(form.isMarkdownHelpPresented ? "Done" : "Add Entry")
                        .frame(minWidth: 60)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(form.isMarkdownHelpPresented ? .defaultAction : nil)
            }
        }
        .padding(20)
        .frame(width: 640, height: 620)
        .defaultFocus($titleFocused, true)
        .onExitCommand(perform: form.isMarkdownHelpPresented ? { form.isMarkdownHelpPresented = false } : nil)
    }

    @ViewBuilder
    private var footerHints: some View {
        FooterShortcutHint(keys: "⌘↑ / ⌘↓", label: "navigate fields", keySize: 11)
            .font(.caption)
        Button {
            form.isMarkdownHelpPresented = true
        } label: {
            FooterShortcutHint(keys: "⌘M", label: "Markdown help", keySize: 11)
                .font(.caption)
        }
        .buttonStyle(.plain)
        .keyboardShortcut("m", modifiers: .command)
    }

    @ViewBuilder
    private var entryFieldsView: some View {
        Text("Add Entry")
            .font(.title2.bold())

        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.section) {
                destinations
                if form.section == .newSection {
                    TextField("New section name", text: $form.newSectionName)
                        .textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text("Type")
                    EntryFormPicker(label: "Type", selection: $form.draft.kind, items: [
                        .option("Note", .note), .option("Command", .command),
                        .option("URL", .url), .option("File", .file)
                    ])
                }
                .fixedSize()
                variablesSummary(form.draft.variables)
                TextField("Title", text: $form.draft.title)
                    .textFieldStyle(.roundedBorder)
                    .focused($titleFocused)
                    .onAppear { titleFocused = true }
                entryFields($form.draft)
            }
            .padding(2)
        }

        if let error = form.errorMessage {
            Text(error).foregroundStyle(.red)
        }
    }

    private var destinations: some View {
        let destination = store.sheets.first { $0.sourceURL == form.sheetURL }
        let sections = destination?.items.compactMap(\.section) ?? []
        var sheets = store.sheets.map { EntryFormPicker<URL>.Item.option($0.title, $0.sourceURL) }
        if destination == nil { sheets.insert(.option("Unavailable sheet", form.sheetURL), at: 0) }

        var sectionItems: [EntryFormPicker<EntrySectionChoice>.Item] = [.option("No section", .unsectioned)]
        if case .existing(let section) = form.section, !sections.contains(section) {
            sectionItems.append(.option("Unavailable section", form.section))
        }
        sectionItems += sections.map { .option($0.title, .existing($0)) }
        sectionItems += [.divider, .option("New section…", .newSection)]

        return HStack(spacing: Spacing.section) {
            HStack {
                Text("Sheet")
                EntryFormPicker(label: "Sheet", selection: $form.sheetURL, items: sheets)
                    .frame(maxWidth: .infinity)
            }
            HStack {
                Text("Section")
                EntryFormPicker(label: "Section", selection: $form.section, items: sectionItems)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func entryFields(_ draft: Binding<NewEntryDraft>) -> some View {
        switch draft.wrappedValue.kind {
        case .note:
            editor("Content", text: draft.rawContent)
        case .command:
            editor("Command", text: draft.rawContent, monospaced: true)
            TextField("Language (optional)", text: draft.language)
                .textFieldStyle(.roundedBorder)
        case .url:
            editor("URL", text: draft.rawContent)
        case .file:
            editor("File path", text: draft.rawContent)
        }
        if draft.wrappedValue.kind != .note {
            editor("Description (optional)", text: draft.rawDescription)
        }
    }

    private func editor(_ label: String, text: Binding<String>, monospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: Spacing.compact) {
            Text(label)
            TextEditor(text: text)
                .font(monospaced ? .system(.body, design: .monospaced) : .body)
                .accessibilityLabel(label)
                .modifier(ResizableEditor())
                .overlay {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(.quaternary)
                        .allowsHitTesting(false)
                }
        }
    }

    @ViewBuilder
    private func variablesSummary(_ variables: [EntryVariable]) -> some View {
        if !variables.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.section) {
                Label("Variables", systemImage: "curlybraces")
                    .font(.headline)
                GroupBox {
                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 24, verticalSpacing: Spacing.compact) {
                        GridRow {
                            Text("Name")
                            Text("Default value")
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        Divider().gridCellUnsizedAxes(.horizontal)
                        ForEach(variables) { variable in
                            GridRow {
                                Text(verbatim: variable.name)
                                    .monospaced()
                                Text(verbatim: variable.defaultValue.isEmpty ? "—" : variable.defaultValue)
                                    .foregroundStyle(variable.defaultValue.isEmpty ? .secondary : .primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .padding(4)
                }
            }
        }
    }
}

private struct ResizableEditor: ViewModifier {
    @State private var height: CGFloat = 120
    @GestureState private var dragOffset: CGFloat = 0
    private let minimumHeight: CGFloat = 60

    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            content
            Capsule()
                .fill(.tertiary)
                .frame(width: 24, height: 3)
                .frame(maxWidth: .infinity)
                .frame(height: 12)
                .contentShape(Rectangle())
                .help("Drag to resize")
                .gesture(
                    DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .updating($dragOffset) { drag, offset, _ in
                            offset = drag.translation.height
                        }
                        .onEnded { drag in
                            height = max(minimumHeight, height + drag.translation.height)
                        }
                )
        }
        .frame(height: max(minimumHeight, height + dragOffset))
    }
}
