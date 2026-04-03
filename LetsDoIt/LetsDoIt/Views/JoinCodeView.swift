import SwiftUI

struct JoinCodeView: View {
    @State private var code = ""
    @State private var isJoining = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 32) {
            Text("Enter your partner's code")
                .font(.headline)

            TextField("000000", text: $code)
                .font(.system(size: 36, weight: .bold, design: .monospaced))
                .kerning(6)
                .multilineTextAlignment(.center)
                .keyboardType(.numberPad)
                .frame(maxWidth: 240)

            Button("Connect") {
                Task { await joinWithCode() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(code.count != 6 || isJoining)

            if isJoining {
                ProgressView()
            }

            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }
        }
        .padding()
    }

    private func joinWithCode() async {
        isJoining = true
        errorMessage = nil
        do {
            try await PairingManager.shared.joinWithCode(code)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isJoining = false
    }
}
