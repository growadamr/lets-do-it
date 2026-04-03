import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct SetNameView: View {
    @State private var name = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 24) {
            Text("What should we call you?")
                .font(.headline)

            TextField("Your name", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 240)

            Button("Save") {
                Task { await saveName() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)

            if isSaving {
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

    private func saveName() async {
        isSaving = true
        errorMessage = nil
        do {
            guard let uid = Auth.auth().currentUser?.uid else { return }
            try await Firestore.firestore()
                .collection("users").document(uid)
                .updateData(["displayName": name])
            // Update AuthManager's displayName
            try await AuthManager.shared.updateDisplayName(name)
            isPresented = false
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}
