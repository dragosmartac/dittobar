import SwiftUI

struct NewEntryFormView: View {
    @ObservedObject var store: CheatSheetStore
    @ObservedObject var form: NewEntryFormState
    @FocusState private var titleFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Entry")
                .font(.title2.bold())

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    destinations
                    if form.section == .newSection {
                        TextField("New section name", text: $form.newSectionName)
                            .textFieldStyle(.roundedBorder)
                    }
                    Picker("Type", selection: $form.draft.kind) {
                        Text("Note").tag(NewEntryDraft.Kind.note)
                        Text("Command").tag(NewEntryDraft.Kind.command)
                        Text("URL").tag(NewEntryDraft.Kind.url)
                        Text("File").tag(NewEntryDraft.Kind.file)
                    }
                    .fixedSize()
                    variablesSummary(form.draft.variables)
                    TextField("Title", text: $form.draft.title)
                        .textFieldStyle(.roundedBorder)
                        .focused($titleFocused)
                    entryFields($form.draft)
                }
                .padding(2)
            }

            if let error = form.errorMessage {
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
        .frame(width: 600, height: 580)
        .defaultFocus($titleFocused, true)
        .onAppear { titleFocused = true }
    }

    private var destinations: some View {
        let destination = store.sheets.first { $0.sourceURL == form.sheetURL }
        let sections = destination?.items.compactMap(\.section) ?? []
        return HStack(spacing: 16) {
            Picker("Sheet", selection: $form.sheetURL) {
                if destination == nil {
                    Text("Unavailable sheet").tag(form.sheetURL)
                }
                ForEach(store.sheets) { sheet in
                    Text(sheet.title).tag(sheet.sourceURL)
                }
            }
            Picker("Section", selection: $form.section) {
                Text("No section").tag(EntrySectionChoice.unsectioned)
                if case .existing(let section) = form.section, !sections.contains(section) {
                    Text("Unavailable section").tag(EntrySectionChoice.existing(section))
                }
                ForEach(sections) { section in
                    Text(section.title).tag(EntrySectionChoice.existing(section))
                }
                Divider()
                Text("New section…").tag(EntrySectionChoice.newSection)
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
        VStack(alignment: .leading, spacing: 4) {
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
            GroupBox {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 24, verticalSpacing: 6) {
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
                .padding(.top, 8)
            } label: {
                Label("Variables", systemImage: "curlybraces")
                    .font(.headline)
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
