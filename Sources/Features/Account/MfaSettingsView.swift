import SwiftUI
import CoreImage.CIFilterBuiltins

/// In-app two-factor management: enable (scan QR / type setup key → confirm a
/// 6-digit code) or disable (re-enter the account password). Mirrors the admin
/// console's three-step enrol flow.
struct MfaSettingsView: View {
    @EnvironmentObject private var repository: MerchantRepository
    @StateObject private var vm = MfaSettingsViewModel()

    var body: some View {
        Form {
            statusSection
            if vm.mfaEnabled {
                disableSection
            } else if let enrol = vm.enrol {
                enrolSection(enrol)
            } else {
                enableSection
            }
        }
        .navigationTitle(LocalizedStringKey("account.mfa.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toast($vm.toast)
        .alert(item: $vm.error) { err in
            Alert(title: Text(err.title), message: Text(err.message), dismissButton: .default(Text(LocalizedStringKey("common.ok"))))
        }
        .onAppear { vm.bind(repository: repository) }
    }

    // MARK: - Sections

    private var statusSection: some View {
        Section {
            HStack {
                Image(systemName: vm.mfaEnabled ? "lock.shield.fill" : "lock.open")
                    .foregroundStyle(vm.mfaEnabled ? .green : .secondary)
                Text(LocalizedStringKey(vm.mfaEnabled ? "account.mfa.statusOn" : "account.mfa.statusOff"))
                Spacer()
            }
        }
    }

    private var enableSection: some View {
        Section {
            Button {
                vm.startEnrol()
            } label: {
                if vm.isWorking {
                    HStack { ProgressView(); Text(LocalizedStringKey("account.mfa.enable")) }
                } else {
                    Label(LocalizedStringKey("account.mfa.enable"), systemImage: "lock.shield")
                }
            }
            .disabled(vm.isWorking)
        } footer: {
            Text(LocalizedStringKey("account.mfa.intro"))
        }
    }

    private func enrolSection(_ enrol: MfaEnrol) -> some View {
        Group {
            Section {
                if let qr = QRImage.make(from: enrol.otpauthURI) {
                    HStack {
                        Spacer()
                        Image(uiImage: qr)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 200, height: 200)
                            .accessibilityLabel(Text(LocalizedStringKey("account.mfa.title")))
                        Spacer()
                    }
                }
                LabeledContent(LocalizedStringKey("account.mfa.secretLabel")) {
                    Text(enrol.secret)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            } footer: {
                Text(LocalizedStringKey("account.mfa.intro"))
            }

            Section {
                TextField(LocalizedStringKey("account.mfa.code"), text: $vm.code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .font(.system(.body, design: .monospaced))
                    .onChange(of: vm.code) { newValue in
                        vm.code = String(newValue.filter(\.isNumber).prefix(8))
                    }
                Button {
                    vm.confirm()
                } label: {
                    if vm.isWorking { HStack { ProgressView(); Text(LocalizedStringKey("account.mfa.confirm")) } }
                    else { Text(LocalizedStringKey("account.mfa.confirm")) }
                }
                .disabled(!vm.canConfirm)
                Button(role: .cancel) { vm.cancelEnrol() } label: { Text(LocalizedStringKey("common.cancel")) }
            }
        }
    }

    private var disableSection: some View {
        Section {
            SecureField(LocalizedStringKey("account.mfa.disablePassword"), text: $vm.disablePassword)
                .textContentType(.password)
            Button(role: .destructive) {
                vm.disable()
            } label: {
                if vm.isWorking { HStack { ProgressView(); Text(LocalizedStringKey("account.mfa.disable")) } }
                else { Label(LocalizedStringKey("account.mfa.disable"), systemImage: "lock.open") }
            }
            .disabled(!vm.canDisable)
        } header: {
            Text(LocalizedStringKey("account.mfa.disable"))
        }
    }
}

/// Renders an `otpauth://` URI as a crisp QR `UIImage` via CoreImage. Local, no
/// network — the URI never leaves the device.
enum QRImage {
    static func make(from string: String) -> UIImage? {
        let data = Data(string.utf8)
        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let context = CIContext()
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
