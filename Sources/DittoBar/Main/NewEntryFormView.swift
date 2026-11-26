import SwiftUI

struct NewEntryFormView: View {
    @ObservedObject var store: CheatSheetStore
    @FocusState private var titleFocused: Bool

    var body: some View {
        if let form = Binding($store.newEntryForm) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Add Entry")
                    .font(.title2.bold())

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        destinations(form)
                        Picker("Type", selection: form.draft.kind) {
                            Text("Note").tag(NewEntryDraft.Kind.note)
                            Text("Command").tag(NewEntryDraft.Kind.command)
                            Text("URL").tag(NewEntryDraft.Kind.url)
                            Text("File").tag(NewEntryDraft.Kind.file)
                        }
                        .fixedSize()
                        TextField("Title", text: form.draft.title)
                            .textFieldStyle(.roundedBorder)
                            .focused($titleFocused)
                        entryFields(form.draft)
                        variablesSummary(form.wrappedValue.draft.variables)
                    }
                    .padding(2)
                }

                if let error = form.wrappedValue.errorMessage {
                    Text(error).foregroundStyle(.red)
                }
                Divider()
                HStack {
                    Spacer()
                    Button("Cancel", role: .cancel) { store.cancelNewEntry() }
                        .keyboardShortcut(.cancelAction)
                    Button("Add Entry") { store.saveNewEntry() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(20)
            .frame(width: 520, height: 520)
            .defaultFocus($titleFocused, true)
            .onAppear { titleFocused = true }
        }
    }

    private func destinations(_ form: Binding<NewEntryFormState>) -> some View {
        let destination = store.sheets.first { $0.sourceURL == form.wrappedValue.sheetURL }
        let sections = destination?.items.compactMap(\.section) ?? []
        return HStack(spacing: 16) {
            Picker("Sheet", selection: form.sheetURL) {
                if destination == nil {
                    Text("Unavailable sheet").tag(form.wrappedValue.sheetURL)
                }
                ForEach(store.sheets) { sheet in
                    Text(sheet.title).tag(sheet.sourceURL)
                }
            }
            Picker("Section", selection: form.section) {
                Text("No section").tag(CheatSheetSection?.none)
                if let section = form.wrappedValue.section, !sections.contains(section) {
                    Text("Unavailable section").tag(Optional(section))
                }
                ForEach(sections) { section in
                    Text(section.title).tag(Optional(section))
                }
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
            TextField("URL", text: draft.rawContent)
                .textFieldStyle(.roundedBorder)
        case .file:
            TextField("File path", text: draft.rawContent)
                .textFieldStyle(.roundedBorder)
        }
        if draft.wrappedValue.kind != .note {
            editor("Description (optional)", text: draft.rawDescription)
        }
    }

    private func editor(_ label: String, text: Binding<String>, monospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
            TextEditor(text: text)
                .font(monospaced ? .system(.body, design: .monospaced) : .body)
                .accessibilityLabel(label)
                .frame(height: 74)
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
            VStack(alignment: .leading, spacing: 6) {
                Text("Variables").font(.headline)
                Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 4) {
                    GridRow {
                        Text("Name")
                        Text("Default value")
                    }
                    .foregroundStyle(.secondary)
                    ForEach(variables) { variable in
                        GridRow {
                            Text(verbatim: variable.name)
                            Text(verbatim: variable.defaultValue.isEmpty ? "—" : variable.defaultValue)
                        }
                    }
                }
            }
        }
    }
}
