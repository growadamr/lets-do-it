import SwiftUI
import FirebaseFirestore

struct SetContactNameSheet: View {
    let contact: ContactManager.Contact
    @State private var name = ""
    @State private var isSaving = false
    @State private var theirSetName: String = ""
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var contactManager = ContactManager.shared

    var body: some View {
        VStack(spacing: 24) {
            Text("Name this contact")
                .font(.headline)

            if !theirSetName.isEmpty {
                Text("This person goes by \"\(theirSetName)\". You can change it below.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("Only you will see this name")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            TextField("Enter a name", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 240)
                .textInputAutocapitalization(.words)

            Button("Save") {
                Task { await saveName() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)

            if isSaving {
                ProgressView()
            }

            Spacer()
        }
        .padding()
        .task {
            // Fetch the contact's own display name (set by them on first launch)
            let doc = try? await Firestore.firestore()
                .collection("users").document(contact.uid)
                .getDocument()
            if let data = doc?.data(),
               let theirName = data["displayName"] as? String,
               !theirName.isEmpty {
                theirSetName = theirName
                name = theirName
            }
        }
    }

    private func saveName() async {
        isSaving = true
        await contactManager.saveContactName(contactUid: contact.uid, name: name.trimmingCharacters(in: .whitespaces))
        await contactManager.refreshContacts()
        isSaving = false
        dismiss()
    }
}
