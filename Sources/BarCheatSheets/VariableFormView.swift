import SwiftUI

/// The fill-in-the-variables form, shown over the command list.
/// Return copies the rendered command and dismisses; Escape cancels.
struct VariableFormView: View {
    @ObservedObject var store: CheatSheetStore
    @FocusState private var focusedVariable: String?

    var body: some View {
        if let form = store.variableForm {
            ZStack {
                Color.black.opacity(0.32)
                    .ignoresSafeArea()
                    .onTapGesture { store.cancelVariableForm() }

                card(for: form)
                    .frame(maxWidth: 620)
                    .padding(24)
            }
            .task {
                // The fields only exist after the overlay lays out.
                try? await Task.sleep(for: .milliseconds(40))
                focusedVariable = form.variables.first?.name
            }
        }
    }

    private func card(for form: VariableFormState) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            header(for: form)
            Divider()
            fields(for: form)
            preview(for: form)
            Divider()
            actions(for: form)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(radius: 24, y: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.primary.opacity(0.12))
        )
    }

    private func header(for form: VariableFormState) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Fill in variables")
                .font(.headline)
            Text(form.title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func fields(for form: VariableFormState) -> some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 8) {
            ForEach(form.variables) { variable in
                GridRow {
                    Text(variable.name)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.trailing)

                    TextField(
                        variable.defaultValue.isEmpty ? variable.name : variable.defaultValue,
                        text: store.binding(forVariable: variable.name)
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .focused($focusedVariable, equals: variable.name)
                    .onSubmit { store.confirmVariableForm() }
                }
            }
        }
    }

    private func preview(for form: VariableFormState) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Preview")
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView(.vertical) {
                previewText(for: form)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(maxHeight: 160)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.primary.opacity(0.1))
            )
        }
    }

    private func previewText(for form: VariableFormState) -> Text {
        form.segments
            .reduce(Text(verbatim: "")) { partial, segment in
                partial + Text(verbatim: segment.text)
                    .foregroundStyle(segment.isVariable ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                    .bold(segment.isVariable)
            }
            .font(.system(.body, design: .monospaced))
    }

    private func actions(for form: VariableFormState) -> some View {
        HStack {
            Button("Reset to Defaults") {
                store.resetVariableFormToDefaults()
            }
            .disabled(form.matchesDefaults)

            Spacer()

            Button("Cancel", role: .cancel) {
                store.cancelVariableForm()
            }
            .keyboardShortcut(.cancelAction)

            Button("Copy") {
                store.confirmVariableForm()
            }
            .keyboardShortcut(.defaultAction)
        }
    }
}
