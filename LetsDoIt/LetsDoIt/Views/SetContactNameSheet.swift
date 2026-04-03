import SwiftUI

struct SetContactNameSheet: View {
    let contact: ContactManager.Contact
    @State private var name = ""
    @State private var isSaving = false
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var contactManager = ContactManager.shared

    var body: some View {
        VStack(spacing: 24) {
            Text("Name this contact")
                .font(.headline)

            Text("Only you will see this name")
                .font(.caption)
                .foregroundColor(.secondary)

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
    }

    private func saveName() async {
        isSaving = true
        await contactManager.saveContactName(contactUid: contact.uid, name: name.trimmingCharacters(in: .whitespaces))
        await contactManager.refreshContacts()
        isSaving = false
        dismiss()
    }
}
