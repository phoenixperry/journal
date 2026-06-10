import SwiftUI

struct LocationEditorPopover: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var location: EntryLocation?

    @State private var label: String = ""
    @State private var latText: String = ""
    @State private var lonText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Location")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("Label")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("e.g. San Francisco, CA", text: $label)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Coordinates")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    TextField("Latitude", text: $latText)
                        .textFieldStyle(.roundedBorder)
                    TextField("Longitude", text: $lonText)
                        .textFieldStyle(.roundedBorder)
                }
            }

            HStack {
                if location != nil {
                    Button("Clear", role: .destructive) {
                        location = nil
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    save()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
        }
        .padding(16)
        .frame(width: 340)
        .onAppear(perform: hydrate)
    }

    private var isValid: Bool {
        if !label.trimmingCharacters(in: .whitespaces).isEmpty {
            return true
        }
        return Double(latText) != nil && Double(lonText) != nil
    }

    private func hydrate() {
        guard let loc = location else { return }
        label = loc.label ?? ""
        latText = String(loc.latitude)
        lonText = String(loc.longitude)
    }

    private func save() {
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let lat = Double(latText) ?? 0
        let lon = Double(lonText) ?? 0
        let hasCoords = Double(latText) != nil && Double(lonText) != nil

        if trimmedLabel.isEmpty && !hasCoords {
            location = nil
        } else {
            location = EntryLocation(
                latitude: hasCoords ? lat : (location?.latitude ?? 0),
                longitude: hasCoords ? lon : (location?.longitude ?? 0),
                label: trimmedLabel.isEmpty ? nil : trimmedLabel
            )
        }
    }
}
