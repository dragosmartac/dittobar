import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct TextSettingsView: View {
    @AppStorage(DisplayPreferences.sectionTitleFontSizeKey)
    private var sectionTitleFontSize = DisplayPreferences.defaultSectionTitleFontSize
    @AppStorage(DisplayPreferences.titleFontSizeKey)
    private var titleFontSize = DisplayPreferences.defaultTitleFontSize
    @AppStorage(DisplayPreferences.descriptionFontSizeKey)
    private var descriptionFontSize = DisplayPreferences.defaultDescriptionFontSize
    @AppStorage(DisplayPreferences.noteFontSizeKey)
    private var noteFontSize = DisplayPreferences.defaultNoteFontSize
    @AppStorage(DisplayPreferences.payloadFontSizeKey)
    private var payloadFontSize = DisplayPreferences.defaultPayloadFontSize
    @AppStorage(DisplayPreferences.textFontFamilyKey)
    private var textFontFamily = ""
    @AppStorage(DisplayPreferences.codeFontFamilyKey)
    private var codeFontFamily = ""

    var body: some View {
        SettingsPane(isUsingDefaults: isUsingDefaults, reset: reset) {
            text
        }
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Text")
                .font(.title2.bold())

            ScrollView(.vertical) {
                VStack(spacing: 14) {
                    FontFamilyPicker(
                        title: "Text Font",
                        families: EntryFonts.installedFamilies,
                        selection: $textFontFamily
                    )
                    FontFamilyPicker(
                        title: "Code Font",
                        families: EntryFonts.installedMonospacedFamilies,
                        selection: $codeFontFamily
                    )

                    Divider()

                    textSizes
                }
                .padding(.trailing, 12)
            }
        }
    }

    private var textSizes: some View {
        VStack(spacing: 14) {
            FontSizeControl(
                title: "Section Title",
                value: $sectionTitleFontSize,
                range: DisplayPreferences.sectionTitleFontSizeRange
            )
            FontSizeControl(
                title: "Entry Title",
                value: $titleFontSize,
                range: DisplayPreferences.titleFontSizeRange
            )
            FontSizeControl(
                title: "Entry Description",
                value: $descriptionFontSize,
                range: DisplayPreferences.descriptionFontSizeRange
            )
            FontSizeControl(
                title: "Note Entry Content",
                value: $noteFontSize,
                range: DisplayPreferences.noteFontSizeRange
            )
            FontSizeControl(
                title: "Entry Payload",
                value: $payloadFontSize,
                range: DisplayPreferences.payloadFontSizeRange,
                description: "Commands, URLs, and file paths shown in entries."
            )
        }
    }

    private var isUsingDefaults: Bool {
        textFontFamily.isEmpty
            && codeFontFamily.isEmpty
            && sectionTitleFontSize == DisplayPreferences.defaultSectionTitleFontSize
            && titleFontSize == DisplayPreferences.defaultTitleFontSize
            && descriptionFontSize == DisplayPreferences.defaultDescriptionFontSize
            && noteFontSize == DisplayPreferences.defaultNoteFontSize
            && payloadFontSize == DisplayPreferences.defaultPayloadFontSize
    }

    private func reset() {
        textFontFamily = ""
        codeFontFamily = ""
        sectionTitleFontSize = DisplayPreferences.defaultSectionTitleFontSize
        titleFontSize = DisplayPreferences.defaultTitleFontSize
        descriptionFontSize = DisplayPreferences.defaultDescriptionFontSize
        noteFontSize = DisplayPreferences.defaultNoteFontSize
        payloadFontSize = DisplayPreferences.defaultPayloadFontSize
    }
}

private struct FontSizeControl: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var description: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value)) pt")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            if let description {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Slider(value: $value, in: range, step: 1)
                .accessibilityLabel("\(title) text size")
                .accessibilityValue("\(Int(value)) points")
        }
    }
}


/// Lists installed families, with an empty selection meaning the system font.
private struct FontFamilyPicker: View {
    let title: String
    let families: [String]
    @Binding var selection: String

    var body: some View {
        Picker(title, selection: $selection) {
            Text("System").tag("")
            if !selection.isEmpty, !families.contains(selection) {
                Text("\(selection) (not installed)").tag(selection)
            }
            Divider()
            ForEach(families, id: \.self) { family in
                Text(family).tag(family)
            }
        }
    }
}
