import SwiftUI

/// Parent-OWNER-only (aggregator entitlement) list of sub-merchants. Tap → detail;
/// `+` mints a new one. Reached from More → Business → Sub-merchants.
struct SubMerchantsView: View {
    @EnvironmentObject private var repository: MerchantRepository
    @StateObject private var vm = SubMerchantsViewModel()

    var body: some View {
        content
            .navigationTitle(LocalizedStringKey("subs.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toast($vm.toast)
            .alert(item: $vm.error) { err in
                Alert(title: Text(err.title), message: Text(err.message), dismissButton: .default(Text(LocalizedStringKey("common.ok"))))
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { vm.startCreate() } label: { Image(systemName: "plus") }
                        .accessibilityLabel(Text(LocalizedStringKey("subs.add")))
                }
            }
            .sheet(isPresented: $vm.showCreate) { createSheet }
            .onAppear {
                vm.bind(repository: repository)
                vm.onAppear()
            }
    }

    @ViewBuilder private var content: some View {
        if vm.isLoading && vm.subs.isEmpty {
            LoadingView(caption: NSLocalizedString("common.loading", value: "Loading…", comment: ""))
        } else if let error = vm.error, vm.subs.isEmpty {
            ErrorStateView(error: error) { Task { await vm.load() } }
        } else if vm.subs.isEmpty {
            EmptyStateView(
                title: NSLocalizedString("subs.empty", value: "No sub-merchants yet", comment: ""),
                systemImage: "building.2",
                description: nil,
                actionTitle: NSLocalizedString("subs.add", value: "Add sub-merchant", comment: ""),
                action: { vm.startCreate() })
        } else {
            List {
                ForEach(vm.subs) { sub in
                    NavigationLink(value: SubMerchantsRoute.detail(id: sub.id)) {
                        SubMerchantRow(sub: sub)
                    }
                }
            }
            .listStyle(.plain)
            .refreshable { await vm.load() }
        }
    }

    private var createSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(LocalizedStringKey("subs.name"), text: $vm.newName)
                        .textInputAutocapitalization(.words)
                }
                Section {
                    TextField(LocalizedStringKey("subs.code"), text: $vm.newCode)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                } footer: {
                    Text(LocalizedStringKey("subs.codeHint"))
                }
                Section {
                    TextField(LocalizedStringKey("subs.codePrefix"), text: $vm.newPrefix)
                        .textInputAutocapitalization(.characters).autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                } footer: {
                    Text(LocalizedStringKey("subs.prefixHint"))
                }
                Section {
                    Toggle(LocalizedStringKey("subs.statusActive"), isOn: $vm.newActive)
                }
                if let err = vm.createError {
                    Section { Text(err.message).foregroundStyle(.red).font(.footnote) }
                }
            }
            .navigationTitle(LocalizedStringKey("subs.add"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(LocalizedStringKey("common.cancel")) { vm.showCreate = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if vm.isCreating { ProgressView() }
                    else {
                        Button(LocalizedStringKey("common.done")) {
                            vm.submitCreate { vm.showCreate = false }
                        }
                        .disabled(!vm.canCreate)
                    }
                }
            }
            .interactiveDismissDisabled(vm.isCreating)
        }
    }
}

private struct SubMerchantRow: View {
    let sub: SubMerchant

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(sub.name).font(.subheadline.weight(.medium)).lineLimit(1)
                Spacer(minLength: 6)
                statusBadge
            }
            HStack(spacing: 8) {
                Text(sub.code)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text(sub.codePrefix)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.14), in: Capsule())
                Spacer(minLength: 4)
                Text(String(format: NSLocalizedString("subs.paymentsCount", value: "%d payments", comment: ""), sub.paymentsCount))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var statusBadge: some View {
        let active = sub.isActive
        return Text(sub.status.replacingOccurrences(of: "_", with: " "))
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .foregroundStyle(active ? Color.green : Color.secondary)
            .background((active ? Color.green : Color.secondary).opacity(0.14), in: Capsule())
    }
}
