import SwiftUI
import Payhub

/// Sheet for minting a new pay-link. On success, swaps to a confirmation panel
/// with a `ShareLink` and a copy button; dismissing refreshes the list.
struct CreatePayLinkView: View {
    @EnvironmentObject private var repository: MerchantRepository
    @Environment(\.dismiss) private var dismiss

    @StateObject private var vm = CreatePayLinkViewModel()
    /// Called when the sheet closes after a successful create, with the new link.
    var onCreated: (PayLink) -> Void = { _ in }

    var body: some View {
        NavigationStack {
            Group {
                if let link = vm.created {
                    confirmation(link: link)
                } else {
                    form
                }
            }
            .navigationTitle(vm.created == nil ? "New pay-link" : "Pay-link created")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(vm.created == nil ? "Cancel" : "Done") { finish() }
                }
                if vm.created == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Create") { vm.submit() }
                            .disabled(!vm.canSubmit)
                    }
                }
            }
            .overlay {
                if vm.isSubmitting {
                    ZStack {
                        Color.black.opacity(0.05).ignoresSafeArea()
                        ProgressView()
                            .padding(20)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .alert(item: $vm.error) { err in
                Alert(title: Text(err.title), message: Text(err.message), dismissButton: .default(Text("OK")))
            }
        }
        .onAppear { vm.bind(repository: repository) }
        .interactiveDismissDisabled(vm.isSubmitting)
    }

    // MARK: - Form

    private var form: some View {
        Form {
            Section("Amount") {
                HStack {
                    TextField("0.000", text: $vm.amountText)
                        .keyboardType(.decimalPad)
                        .font(.title3.monospacedDigit())
                    Text(vm.currency).foregroundStyle(.secondary)
                }
            }

            Section("Details") {
                TextField("Description (optional)", text: $vm.description, axis: .vertical)
                    .lineLimit(1...3)
                TextField("Customer phone (optional)", text: $vm.customerPhone)
                    .keyboardType(.phonePad)
            }
            .listRowSeparator(.hidden, edges: .bottom)
            if !vm.customerPhone.trimmed.isEmpty {
                Section { EmptyView() } footer: {
                    Text("We'll send the customer a payment reminder if the link is still unpaid.")
                }
            }

            Section {
                ForEach(PSP.all, id: \.code) { psp in
                    Button {
                        toggle(psp.code)
                    } label: {
                        HStack {
                            Label(psp.label, systemImage: psp.symbol)
                                .foregroundStyle(.primary)
                            Spacer()
                            if vm.selectedPSPs.contains(psp.code) {
                                Image(systemName: "checkmark").foregroundStyle(Brand.amber)
                            }
                        }
                    }
                }
            } header: {
                Text("Payment methods")
            } footer: {
                Text(vm.selectedPSPs.isEmpty
                     ? "Leave all unticked to offer every available method — the customer chooses."
                     : "Only the ticked methods will be offered.")
            }

            Section("Expiry") {
                Stepper(value: $vm.expiryDays, in: 1...vm.maxExpiryDays) {
                    Text("\(vm.expiryDays) day\(vm.expiryDays == 1 ? "" : "s")")
                }
            }

            Section {
                HStack {
                    TextField("Order reference", text: $vm.merchantOrderRef)
                        .font(.system(.body, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button { vm.regenerateOrderRef() } label: { Image(systemName: "die.face.5") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
            } header: {
                Text("Order reference")
            } footer: {
                Text("Echoed back to your systems unchanged. Auto-generated — edit if you like.")
            }
        }
    }

    private func toggle(_ code: String) {
        if vm.selectedPSPs.contains(code) { vm.selectedPSPs.remove(code) } else { vm.selectedPSPs.insert(code) }
    }

    // MARK: - Confirmation

    private func confirmation(link: PayLink) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.green)
                    .padding(.top, 16)
                Text("Pay-link ready to share")
                    .font(.title3.weight(.semibold))

                VStack(spacing: 6) {
                    Text(Money.format(minor: link.amountMinor, currency: link.currency))
                        .font(.system(.title2, design: .rounded).weight(.bold))
                    Text(link.merchantOrderRef)
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(.secondary)
                    if let expiry = RelativeTime.expiry(link.expiresAt) {
                        Text(expiry).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity)
                .background(Brand.amberSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                Text(link.url)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                    .padding(.horizontal, 8)

                VStack(spacing: 10) {
                    if let url = URL(string: link.url) {
                        ShareLink(item: url) {
                            Label("Share link", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .simultaneousGesture(TapGesture().onEnded { vm.markSharedAfterCreate() })
                    }
                    Button {
                        UIPasteboard.general.string = link.url
                    } label: {
                        Label("Copy link", systemImage: "doc.on.doc").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                .padding(.top, 4)
            }
            .padding(20)
            .frame(maxWidth: 460)
            .frame(maxWidth: .infinity)
        }
    }

    private func finish() {
        let created = vm.created
        dismiss()
        if let created { onCreated(created) }
    }
}
