import SwiftUI

/// One sub-merchant: read-only identity, an edit section (name + active toggle),
/// "Manage users", and a delete button (disabled while any `Payment` references
/// the sub — disable it instead).
struct SubMerchantDetailView: View {
    let subID: String
    @EnvironmentObject private var repository: MerchantRepository
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm: SubMerchantDetailViewModel

    @State private var showDeleteAlert = false

    init(subID: String) {
        self.subID = subID
        _vm = StateObject(wrappedValue: SubMerchantDetailViewModel(subID: subID))
    }

    var body: some View {
        Group {
            if vm.isLoading && vm.sub == nil {
                LoadingView(caption: NSLocalizedString("common.loading", value: "Loading…", comment: ""))
            } else if let error = vm.error, vm.sub == nil {
                ErrorStateView(error: error) { Task { await vm.load() } }
            } else if let sub = vm.sub {
                form(sub)
            } else {
                Color.clear
            }
        }
        .navigationTitle(LocalizedStringKey("sub.detail.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toast($vm.toast)
        .alert(item: $vm.error) { err in
            Alert(title: Text(err.title), message: Text(err.message), dismissButton: .default(Text(LocalizedStringKey("common.ok"))))
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(LocalizedStringKey("org.profile.save")) { vm.save() }
                    .disabled(!vm.canSave)
            }
        }
        .alert(LocalizedStringKey("sub.detail.delete"), isPresented: $showDeleteAlert) {
            Button(role: .destructive) { vm.delete() } label: { Text(LocalizedStringKey("sub.detail.delete")) }
            Button(role: .cancel) {} label: { Text(LocalizedStringKey("common.cancel")) }
        }
        .onChange(of: vm.deleted) { if $0 { dismiss() } }
        .onAppear {
            vm.bind(repository: repository)
            vm.onAppear()
        }
    }

    @ViewBuilder private func form(_ sub: SubMerchant) -> some View {
        Form {
            Section {
                LabeledContent(LocalizedStringKey("subs.code"), value: sub.code)
                LabeledContent(LocalizedStringKey("subs.codePrefix"), value: sub.codePrefix)
                if let ext = sub.externalRef, !ext.isEmpty {
                    LabeledContent("external_ref", value: ext)
                }
                LabeledContent(String(format: NSLocalizedString("subs.paymentsCount", value: "%d payments", comment: ""), sub.paymentsCount),
                               value: "")
                if let created = ISO.date(from: sub.createdAt) {
                    LabeledContent(LocalizedStringKey("payment.detail.created"),
                                   value: created.formatted(date: .abbreviated, time: .shortened))
                }
            }

            Section(LocalizedStringKey("sub.detail.edit")) {
                TextField(LocalizedStringKey("subs.name"), text: $vm.name)
                    .textInputAutocapitalization(.words)
                Toggle(LocalizedStringKey("subs.statusActive"), isOn: $vm.active)
            }

            Section {
                NavigationLink(value: SubMerchantsRoute.users(subID: sub.id)) {
                    Label(LocalizedStringKey("sub.detail.users"), systemImage: "person.2")
                }
                // Sub-merchant API keys (0.4.0). Parent keys remain
                // web-portal-only — see CLAUDE.md "Native mobile apps".
                NavigationLink(value: SubMerchantsRoute.apiKeys(subID: sub.id)) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(LocalizedStringKey("sub.detail.tab.apiKeys"))
                            Text(LocalizedStringKey("sub.apiKeys.empty.body"))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                    } icon: { Image(systemName: "key.horizontal") }
                }
            }

            Section {
                Button(role: .destructive) {
                    showDeleteAlert = true
                } label: {
                    if vm.isDeleting { HStack { ProgressView(); Text(LocalizedStringKey("sub.detail.delete")) } }
                    else { Label(LocalizedStringKey("sub.detail.delete"), systemImage: "trash") }
                }
                .disabled(!vm.canDelete)
            } footer: {
                if sub.paymentsCount > 0 {
                    Text(String(format: NSLocalizedString("sub.detail.deleteBlocked",
                                                          value: "Has %d payments — disable it instead", comment: ""),
                                sub.paymentsCount))
                }
            }
        }
    }
}
