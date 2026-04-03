import SwiftUI

struct CreateCodeView: View {
    @State private var code: String?
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 32) {
            Text("Share this code with your person")
                .font(.headline)

            if isGenerating {
                ProgressView()
            } else if let code {
                // Display code with large, spaced-out digits
                Text(code)
                    .font(.system(size: 48, weight: .bold, design: .monospaced))
                    .kerning(8)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)

                Text("Expires in 24 hours")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button("Copy Code") {
                    UIPasteboard.general.string = code
                }
                .buttonStyle(.bordered)
            }

            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }
        }
        .padding()
        .task {
            await generateCode()
        }
    }

    private func generateCode() async {
        isGenerating = true
        errorMessage = nil
        do {
            code = try await ContactManager.shared.generateInviteCode()
        } catch {
            errorMessage = error.localizedDescription
        }
        isGenerating = false
    }
}
