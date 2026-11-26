import SwiftUI

struct RemoveEntryConfirmationView: View {
    @Environment(\.dittoAccent) private var accentColor
    let removal: CheatSheetStore.EntryRemoval
    let onCancel: () -> Void
    let onRemove: () -> Void

    var body: some View {
        let entryName = Text(verbatim: removal.entry.title).foregroundStyle(accentColor)
        let sheetName = Text(verbatim: removal.sheet.title).foregroundStyle(accentColor)
        VStack(alignment: .leading, spacing: 16) {
            Text("Remove Entry")
                .font(.title2.bold())
            Text("Remove “\(entryName)” from “\(sheetName)”? This edits the Markdown file.")
                .fixedSize(horizontal: false, vertical: true)

            Divider()
            HStack(spacing: 8) {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Remove Entry", role: .destructive, action: onRemove)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 640)
        .onExitCommand(perform: onCancel)
    }
}
