import SharedKit
import SwiftUI

struct PassphrasePromptView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var passphrase = ""
    @State private var errorMessage: String?
    @State private var isUnlocked = !KeychainManager.shared.hasPassphrase

    var body: some View {
        if isUnlocked {
            SettingsView()
        } else {
            NavigationStack {
                VStack(spacing: 24) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 48))
                        .foregroundStyle(.tint)

                    Text("passphrase.title", tableName: "Localizable")
                        .font(.title.bold())

                    Text("passphrase.description", tableName: "Localizable")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)

                    SecureField(String(localized: "passphrase.field"), text: $passphrase)
                        .textContentType(.password)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .onSubmit { unlock() }

                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(BrandTint.red)
                            .font(.caption)
                    }

                    Button(String(localized: "passphrase.unlockButton")) {
                        unlock()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(passphrase.isEmpty)

                    Text(String(localized: "passphrase.unlockForgotWarning"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)

                    Spacer()
                }
                .padding(32)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "settings.cancel")) {
                            dismiss()
                        }
                    }
                }
            }
        }
    }

    private func unlock() {
        if KeychainManager.shared.verify(passphrase) {
            withAnimation { isUnlocked = true }
        } else {
            errorMessage = String(localized: "settings.wrongPassphrase")
            passphrase = ""
        }
    }
}
