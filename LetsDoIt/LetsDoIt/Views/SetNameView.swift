import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct SetNameView: View {
    @State private var name = ""
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 24) {
            Text("What should we call you?")
                .font(.headline)

            TextField("Your name", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 240)

            Button("Save") {
                Task {
                    guard let uid = Auth.auth().currentUser?.uid else { return }
                    try? await Firestore.firestore()
                        .collection("users").document(uid)
                        .updateData(["displayName": name])
                    isPresented = false
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding()
    }
}
