import SwiftUI

struct NotchUnlockSettings: View {
    @ObservedObject var manager = NotchUnlockManager.shared
    @State private var password = ""
    @State private var editingPassword = false
    @FocusState private var passwordFocused: Bool
    @State private var showingEnrollment = false

    var body: some View {
        Form {
            Section {
                Toggle("Unlock with your face", isOn: Binding(
                    get: { manager.isEnabled },
                    set: { manager.isEnabled = $0 }
                ))
                .disabled(!manager.modelAvailable)
                if !manager.modelAvailable {
                    Label("FaceEmbedding model missing: unlocking is turned off.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.callout)
                }
            } header: {
                Text("NotchUnlock")
            } footer: {
                Text("Convenience, not security: it uses the 2D camera and types the login password saved in your Keychain. It only works once you are logged in, not after a restart.")
            }

            Section("Face") {
                HStack(spacing: 12) {
                    FaceIDGlyph(state: manager.hasEnrollment ? .success : .idle, size: 28, color: .primary)
                    Text(manager.hasEnrollment ? tr("Face enrolled") : tr("No face enrolled"))
                    Spacer()
                    Button(manager.hasEnrollment ? tr("Enroll again") : tr("Set Up NotchUnlock…")) {
                        showingEnrollment = true
                    }
                    .disabled(!manager.modelAvailable)
                }
            }
            .sheet(isPresented: $showingEnrollment, onDismiss: {
                if case .running = manager.enrollPhase { manager.cancelEnrollment() }
                manager.refresh()
            }) {
                FaceEnrollmentFlow()
            }

            Section {
                if manager.hasPassword && !editingPassword {
                    HStack {
                        Label("Password saved in your Keychain", systemImage: "checkmark.circle.fill")
                        Spacer()
                        Button("Change…") {
                            editingPassword = true
                            passwordFocused = true
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Mac login password")
                            .font(.headline)
                        HStack(spacing: 8) {
                            SecureField("Type your password here", text: $password)
                                .textFieldStyle(.roundedBorder)
                                .controlSize(.large)
                                .labelsHidden()
                                .focused($passwordFocused)
                                .onSubmit(savePassword)
                            Button("Save", action: savePassword)
                                .controlSize(.large)
                                .buttonStyle(.borderedProminent)
                                .disabled(password.isEmpty)
                            if manager.hasPassword {
                                Button("Cancel") {
                                    password = ""
                                    editingPassword = false
                                }
                                .controlSize(.large)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("Login Password")
            } footer: {
                Text("The same password you use to log in to this Mac. NotchUnlock types it for you when it recognizes your face. It is stored only in your Keychain.")
            }

            Section {
                HStack {
                    Label(manager.cameraAuthorized ? tr("Camera allowed") : tr("Camera needed to recognize your face"),
                          systemImage: manager.cameraAuthorized ? "checkmark.circle.fill" : "exclamationmark.circle")
                    Spacer()
                    if !manager.cameraAuthorized { Button("Grant") { manager.requestAllPermissions() } }
                }
                HStack {
                    Label(manager.accessibilityTrusted ? tr("Accessibility allowed") : tr("Accessibility needed to type your password"),
                          systemImage: manager.accessibilityTrusted ? "checkmark.circle.fill" : "exclamationmark.circle")
                    Spacer()
                    if !manager.accessibilityTrusted { Button("Grant") { manager.requestAccessibility() } }
                }
            } header: {
                Text("Permissions")
            } footer: {
                if !manager.allPermissionsGranted {
                    Button("Grant All Permissions") { manager.requestAllPermissions() }
                }
            }

            Section {
                Button("Delete Face and Password", role: .destructive) { manager.deleteAll() }
            }
        }
        .formStyle(.grouped)
        .onAppear { manager.refresh() }
    }

    private func savePassword() {
        guard !password.isEmpty else { return }
        manager.savePassword(password)
        password = ""
        editingPassword = false
    }
}
