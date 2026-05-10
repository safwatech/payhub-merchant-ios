import SwiftUI

/// "Forgot password?" — collects merchant code + username (+ optional shop code)
/// and asks the server to send a reset link. Always shows a generic confirmation
/// (the API doesn't reveal whether the account exists).
struct ForgotPasswordSheet: View {
    @EnvironmentObject private var repository: MerchantRepository
    @Environment(\.dismiss) private var dismiss

    @State private var merchantCode: String
    @State private var username: String
    @State private var subCode: String
    @State private var isSubmitting = false
    @State private var sent = false
    @State private var error: AppError?

    init(initialMerchantCode: String = "", initialUsername: String = "", initialSubCode: String = "") {
        _merchantCode = State(initialValue: initialMerchantCode)
        _username = State(initialValue: initialUsername)
        _subCode = State(initialValue: initialSubCode)
    }

    var body: some View {
        NavigationStack {
            Form {
                if sent {
                    Section {
                        Label {
                            Text("If that account exists, we've sent a password-reset link to its email address. Check your inbox.")
                        } icon: {
                            Image(systemName: "envelope.badge").foregroundStyle(Brand.amber)
                        }
                    }
                } else {
                    Section {
                        TextField("Merchant code", text: $merchantCode)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        TextField("Username", text: $username)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        TextField("Shop code (optional)", text: $subCode)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                    } footer: {
                        Text("Shop code is only needed for sub-merchant (shop) accounts.")
                    }
                    Section {
                        Button {
                            submit()
                        } label: {
                            if isSubmitting { ProgressView() } else { Text("Send reset link") }
                        }
                        .disabled(merchantCode.trimmed.isEmpty || username.trimmed.isEmpty || isSubmitting)
                    }
                }
            }
            .navigationTitle("Reset password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(sent ? "Done" : "Cancel") { dismiss() }
                }
            }
            .alert(item: $error) { err in
                Alert(title: Text(err.title), message: Text(err.message), dismissButton: .default(Text("OK")))
            }
        }
    }

    private func submit() {
        isSubmitting = true
        Task {
            defer { isSubmitting = false }
            do {
                try await repository.forgotPassword(merchantCode: merchantCode.trimmed, username: username.trimmed,
                                                    subCode: subCode.trimmed.isEmpty ? nil : subCode.trimmed)
            } catch {
                // Even on an error, we typically still show the generic success to
                // avoid enumeration — but surface transport errors so the user can retry.
                let app = AppError.from(error)
                if app.isRetryable { self.error = app; return }
            }
            withAnimation { sent = true }
        }
    }
}
