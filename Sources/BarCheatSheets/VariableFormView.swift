import SwiftUI

/// The fill-in-the-variables form, shown over the command list.
/// Return completes the requested action and dismisses; Escape cancels.
struct VariableFormView: View {
    @ObservedObject var store: CheatSheetStore
    @FocusState private var focusedVariable: String?
    @AppStorage(DisplayPreferences.commandFontSizeKey)
    private var commandFontSize = DisplayPreferences.defaultCommandFontSize
    @AppStorage(DisplayPreferences.descriptionFontSizeKey)
    private var descriptionFontSize = DisplayPreferences.defaultDescriptionFontSize

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
            .task(id: form.commandID) {
                // Clearing first guarantees a state change even if focus was
                // left on a field of the same name by a previous form.
                focusedVariable = nil

                // The fields only exist once the overlay has laid out.
                try? await Task.sleep(for: .milliseconds(50))

                // `try?` swallows cancellation, so check it explicitly rather
                // than moving focus for a form that has already been dismissed.
                guard !Task.isCancelled,
                      store.variableForm?.commandID == form.commandID else { return }

                focusedVariable = form.variables.first?.name
            }
            .onDisappear { focusedVariable = nil }
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
        if form.outputFormat == .plainDescription {
            return Text(verbatim: form.rendered)
                .font(.system(size: CGFloat(descriptionFontSize)))
        }

        return form.segments
            .reduce(Text(verbatim: "")) { partial, segment in
                partial + Text(verbatim: segment.text)
                    .foregroundStyle(segment.isVariable ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                    .bold(segment.isVariable)
            }
            .font(.system(size: CGFloat(commandFontSize), design: .monospaced))
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

            // Deliberately NOT .defaultAction. When this form appears, the
            // search field behind it ends editing, and AppKit replays that as
            // a Return key equivalent — which a .defaultAction button claims,
            // confirming the form before it can be typed into. Return is
            // already handled by .onSubmit on the fields; ⌘Return is a
            // distinct shortcut the replayed plain Return cannot match.
            Button(form.action == .openLink ? "Open Link" : "Copy") {
                store.confirmVariableForm()
            }
            .keyboardShortcut(.return, modifiers: .command)
            .buttonStyle(.borderedProminent)
        }
    }
}
