import SwiftUI

/// Second-factor entry. Pushed onto the login `NavigationStack` after a login
/// that returned `requires_mfa`.
struct MFAView: View {
    @EnvironmentObject private var repository: MerchantRepository
    @StateObject private var vm: MFAViewModel
    @FocusState private var codeFocused: Bool

    init(challengeToken: String) {
        _vm = StateObject(wrappedValue: MFAViewModel(challengeToken: challengeToken))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 56))
                    .foregroundStyle(Brand.amber)
                    .padding(.top, 24)
                VStack(spacing: 6) {
                    Text("Two-factor authentication")
                        .font(.title2.weight(.bold))
                    Text("Enter the 6-digit code from your authenticator app.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                TextField("000000", text: $vm.code)
                    .font(.system(.largeTitle, design: .monospaced).weight(.semibold))
                    .multilineTextAlignment(.center)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .focused($codeFocused)
                    .padding(.vertical, 14)
                    .background(Brand.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .onChange(of: vm.code) { newValue in
                        vm.code = String(newValue.filter(\.isNumber).prefix(8))
                    }

                Button {
                    codeFocused = false
                    vm.submit()
                } label: {
                    if vm.isSubmitting {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text("Verify").frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!vm.canSubmit)
            }
            .padding(20)
            .frame(maxWidth: 420)
            .frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Verify")
        .navigationBarTitleDisplayMode(.inline)
        .alert(item: $vm.error) { err in
            Alert(title: Text(err.title), message: Text(err.message), dismissButton: .default(Text("OK")))
        }
        .onAppear {
            vm.bind(repository: repository)
            codeFocused = true
        }
    }
}
