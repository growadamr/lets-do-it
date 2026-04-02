import SwiftUI

struct InviteCodeView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var pairManager = PairManager.shared
    @State private var inviteCode: String = ""
    @State private var isGenerating = false
    @State private var isScanning = false
    @State private var showSuccess = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if isScanning {
                    CameraScannerView { code in
                        validateCode(code)
                    }
                } else {
                    VStack(spacing: 20) {
                        Text("Invite Code")
                            .font(.title2)
                            .fontWeight(.medium)

                        Text("Share this code with your friend")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        if let code = pairManager.inviteCode {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.blue.opacity(0.1))
                                Text(code)
                                    .font(.system(size: 32, weight: .bold))
                                    .monospaced()
                            }
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                        } else {
                            Button(action: generateCode) {
                                Text("Generate Code")
                                    .font(.headline)
                                    .padding()
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(12)
                            }
                            .disabled(isGenerating)
                        }

                        Button(action: startScanning) {
                            Text("Scan Code")
                                .font(.headline)
                                .padding()
                                .background(Color.green)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                        .disabled(isScanning)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground))
            .navigationTitle("Invite Code")
            .alert("Invalid code", isPresented: $showSuccess) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Please enter a valid 6-digit invite code")
            }
        }
    }

    private func generateCode() {
        Task {
            isGenerating = true
            do {
                try await pairManager.generateInviteCode()
            } catch {
                print("Error generating code: \(error)")
            }
            isGenerating = false
        }
    }

    private func startScanning() {
        isScanning = true
    }

    private func validateCode(_ code: String) {
        Task {
            do {
                let inviteData = try await pairManager.validateInviteCode(code)
                if let data = inviteData {
                    try await pairManager.useInviteCode(data.code, for: Auth.auth().currentUser?.uid ?? "")
                    dismiss()
                }
            } catch {
                showSuccess = true
            }
        }
    }
}

struct CameraScannerView: View {
    let onCodeDetected: (String) -> Void

    var body: some View {
        ZStack {
            CameraView()
                .ignoresSafeArea()

            VStack {
                Spacer()

                Text("Scan invite code")
                    .font(.headline)

                Spacer()

                Image(systemName: "qr.code.viewfinder")
                    .font(.system(size: 60))
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct CameraView: UIViewRepresentable {
    func makeUIView(context: Context) -> AVCapturePreviewView {
        let session = AVCaptureSession()
        guard let captureDevice = AVCaptureDevice.default(for: .video) else {
            return UIView()
        }

        do {
            let input = try AVCaptureDeviceInput(device: captureDevice)
            if session.canAddInput(input) {
                session.addInput(input)
            }
        } catch {
            print("Error setting up camera: \(error)")
        }

        let previewView = AVCapturePreviewView(session: session,
                                               videoGravity: .resizeAspectFill,
                                               transforms: [],
                                               frame: .zero)
        previewView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        session.startRunning()

        return previewView
    }

    func updateUIView(_ uiView: AVCapturePreviewView, context: Context) {
        //
    }
}

#Preview {
    InviteCodeView()
}
