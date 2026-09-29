import SwiftUI

struct CommentComposerView: View {
    let title: String
    let publish: (String) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var publishing = false
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("内容") {
                    TextEditor(text: $text)
                        .frame(minHeight: 180)
                        .accessibilityIdentifier("comment-content")
                }
                if let failure {
                    Text(failure)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(publishing ? "正在发布" : "发布") {
                        Task { await submit() }
                    }
                    .disabled(publishing || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func submit() async {
        publishing = true
        defer { publishing = false }
        do {
            try await publish(text.trimmingCharacters(in: .whitespacesAndNewlines))
            dismiss()
        } catch {
            failure = error.localizedDescription
        }
    }
}
