import SwiftUI

struct GardenTodoSheet: View {
    let artistName: String
    let albumName: String
    let onSubmit: (String) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var todoBody = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Time to tend the garden 🌱")
                        .font(.headline)
                    Text("\(artistName) — \(albumName)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section("What needs fixing?") {
                    TextEditor(text: $todoBody)
                        .frame(minHeight: 100)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("Garden Todo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Button("Submit") {
                            Task { await submit() }
                        }
                        .disabled(todoBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .interactiveDismissDisabled(isSubmitting)
        }
    }

    private func submit() async {
        isSubmitting = true
        errorMessage = nil
        do {
            try await onSubmit(todoBody.trimmingCharacters(in: .whitespacesAndNewlines))
            dismiss()
        } catch {
            if let gardenError = error as? LunaraError {
                errorMessage = gardenError.userMessage
            } else {
                errorMessage = error.localizedDescription
            }
        }
        isSubmitting = false
    }
}
