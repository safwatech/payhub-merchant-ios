import SwiftUI
import Payhub

/// Organisation profile — `code`/`status`/`created_at` are always read-only;
/// the rest is editable for a parent OWNER (`PATCH /merchant/org`, dirty fields
/// only), read-only for everyone else.
struct OrgProfileView: View {
    @EnvironmentObject private var repository: MerchantRepository
    @StateObject private var vm = OrgProfileViewModel()

    var body: some View {
        Group {
            if vm.isLoading && vm.org == nil {
                LoadingView(caption: NSLocalizedString("common.loading", value: "Loading…", comment: ""))
            } else if let error = vm.error, vm.org == nil {
                ErrorStateView(error: error) { Task { await vm.refresh() } }
            } else if vm.org != nil {
                form
            } else {
                Color.clear
            }
        }
        .navigationTitle(LocalizedStringKey("org.profile.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toast($vm.toast)
        .alert(item: $vm.error) { err in
            Alert(title: Text(err.title), message: Text(err.message), dismissButton: .default(Text(LocalizedStringKey("common.ok"))))
        }
        .toolbar {
            if vm.canEdit {
                ToolbarItem(placement: .confirmationAction) {
                    Button(LocalizedStringKey("org.profile.save")) { vm.save() }
                        .disabled(!vm.canSave)
                }
            }
        }
        .task {
            vm.bind(repository: repository)
            await vm.load()
        }
        .refreshable { await vm.refresh() }
    }

    @ViewBuilder private var form: some View {
        Form {
            if let o = vm.org {
                Section {
                    LabeledContent(LocalizedStringKey("org.profile.code"), value: o.code)
                    if !o.status.isEmpty { LabeledContent(LocalizedStringKey("org.profile.status"), value: o.status) }
                    if let created = ISO.date(from: o.createdAt) {
                        LabeledContent(LocalizedStringKey("payment.detail.created"),
                                       value: created.formatted(date: .abbreviated, time: .shortened))
                    }
                }
            }

            Section(LocalizedStringKey("org.profile.sectionIdentity")) {
                field(LocalizedStringKey("org.profile.name"), $vm.name, caps: .words)
                if vm.canEdit {
                    Picker(LocalizedStringKey("org.profile.type"), selection: $vm.type) {
                        Text(LocalizedStringKey("org.profile.typePerson")).tag("person")
                        Text(LocalizedStringKey("org.profile.typeCompany")).tag("company")
                    }
                } else {
                    LabeledContent(LocalizedStringKey("org.profile.type"),
                                   value: NSLocalizedString(vm.type == "person" ? "org.profile.typePerson" : "org.profile.typeCompany",
                                                            value: vm.type == "person" ? "Individual" : "Company", comment: ""))
                }
                field(LocalizedStringKey("org.profile.legalName"), $vm.legalName, caps: .words)
                field(LocalizedStringKey("org.profile.taxNumber"), $vm.taxNumber)
                field(LocalizedStringKey("org.profile.commercialRegisterNo"), $vm.commercialRegisterNo)
            } footer: {
                if vm.canEdit && vm.nameInvalid { Text(LocalizedStringKey("org.profile.name")).foregroundStyle(.red) }
            }

            Section(LocalizedStringKey("org.profile.sectionContact")) {
                field(LocalizedStringKey("org.profile.billingEmail"), $vm.billingEmail, keyboard: .emailAddress)
                if vm.canEdit && vm.billingEmailInvalid { Text(LocalizedStringKey("org.profile.errEmail")).font(.caption).foregroundStyle(.red) }
                field(LocalizedStringKey("org.profile.supportEmail"), $vm.supportEmail, keyboard: .emailAddress)
                if vm.canEdit && vm.supportEmailInvalid { Text(LocalizedStringKey("org.profile.errEmail")).font(.caption).foregroundStyle(.red) }
                field(LocalizedStringKey("org.profile.phone"), $vm.phone, keyboard: .phonePad)
                field(LocalizedStringKey("org.profile.website"), $vm.website, keyboard: .URL)
                if vm.canEdit && vm.websiteInvalid { Text(LocalizedStringKey("org.profile.errHTTPS")).font(.caption).foregroundStyle(.red) }
            }

            Section(LocalizedStringKey("org.profile.sectionAddress")) {
                field(LocalizedStringKey("org.profile.addressLine1"), $vm.addressLine1, caps: .words)
                field(LocalizedStringKey("org.profile.addressLine2"), $vm.addressLine2, caps: .words)
                field(LocalizedStringKey("org.profile.city"), $vm.city, caps: .words)
                field(LocalizedStringKey("org.profile.country"), $vm.country)
                if vm.canEdit && vm.countryInvalid { Text(LocalizedStringKey("org.profile.errCountry")).font(.caption).foregroundStyle(.red) }
                field(LocalizedStringKey("org.profile.logoURL"), $vm.logoURL, keyboard: .URL)
                if vm.canEdit && vm.logoURLInvalid { Text(LocalizedStringKey("org.profile.errHTTPS")).font(.caption).foregroundStyle(.red) }
            }

            if !vm.canEdit {
                Section {
                    InfoBanner(text: NSLocalizedString("org.profile.readOnly",
                                                       value: "You can view but not edit these — ask an owner to make changes.",
                                                       comment: ""),
                               systemImage: "lock")
                }
            }
        }
    }

    private enum Caps { case never, words }

    /// Editable `TextField` when `canEdit`, a `LabeledContent` (or em-dash) otherwise.
    @ViewBuilder
    private func field(_ label: LocalizedStringKey, _ text: Binding<String>,
                       keyboard: UIKeyboardType = .default,
                       caps: Caps = .never) -> some View {
        if vm.canEdit {
            TextField(label, text: text)
                .keyboardType(keyboard)
                .textInputAutocapitalization(caps == .words ? .words : .never)
                .autocorrectionDisabled(caps == .never)
        } else {
            LabeledContent(label, value: text.wrappedValue.isEmpty ? "—" : text.wrappedValue)
        }
    }
}
