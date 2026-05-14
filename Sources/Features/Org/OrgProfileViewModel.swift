import Foundation
import Combine
import Payhub

@MainActor
final class OrgProfileViewModel: ObservableObject {
    @Published private(set) var org: OrgInfo?
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published var error: AppError?
    @Published var toast: Toast?

    // Editable mirrors of the server fields (empty string == cleared / unset).
    @Published var name = ""
    @Published var type = "company"            // "person" | "company"
    @Published var legalName = ""
    @Published var taxNumber = ""
    @Published var commercialRegisterNo = ""
    @Published var billingEmail = ""
    @Published var supportEmail = ""
    @Published var phone = ""
    @Published var website = ""
    @Published var addressLine1 = ""
    @Published var addressLine2 = ""
    @Published var city = ""
    @Published var country = ""
    @Published var logoURL = ""

    private weak var repository: MerchantRepository?
    private var didLoad = false

    var canEdit: Bool { repository?.me?.isParentOwner ?? false }

    func bind(repository: MerchantRepository) { self.repository = repository }

    func load() async {
        guard !didLoad, let repository else { return }
        didLoad = true
        isLoading = true
        defer { isLoading = false }
        do { apply(try await repository.getOrg()) }
        catch { self.error = AppError.from(error) }
    }

    func refresh() async {
        guard let repository else { return }
        do { apply(try await repository.getOrg()) }
        catch { self.error = AppError.from(error) }
    }

    private func apply(_ info: OrgInfo) {
        org = info
        name = info.name
        type = (info.type == "person") ? "person" : "company"
        legalName = info.legalName ?? ""
        taxNumber = info.taxNumber ?? ""
        commercialRegisterNo = info.commercialRegisterNo ?? ""
        billingEmail = info.billingEmail ?? ""
        supportEmail = info.supportEmail ?? ""
        phone = info.phone ?? ""
        website = info.website ?? ""
        addressLine1 = info.addressLine1 ?? ""
        addressLine2 = info.addressLine2 ?? ""
        city = info.city ?? ""
        country = info.country ?? ""
        logoURL = info.logoURL ?? ""
    }

    // MARK: - Validation (mirrors the server's UpdateOrgBody)

    private func looksLikeURL(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        return t.isEmpty || (t.lowercased().hasPrefix("https://") && !t.contains(" "))
    }
    private func looksLikeEmail(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        return t.isEmpty || (t.contains("@") && !t.contains(" ") && t.count >= 3)
    }
    private func looksLikeCountry(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        return t.isEmpty || (t.count == 2 && t.allSatisfy { $0.isUppercase && $0.isLetter })
    }

    var websiteInvalid: Bool { !looksLikeURL(website) }
    var logoURLInvalid: Bool { !looksLikeURL(logoURL) }
    var billingEmailInvalid: Bool { !looksLikeEmail(billingEmail) }
    var supportEmailInvalid: Bool { !looksLikeEmail(supportEmail) }
    var countryInvalid: Bool { !looksLikeCountry(country) }
    var nameInvalid: Bool { name.trimmingCharacters(in: .whitespaces).isEmpty }

    var hasValidationErrors: Bool {
        nameInvalid || websiteInvalid || logoURLInvalid || billingEmailInvalid || supportEmailInvalid || countryInvalid
    }

    /// `true` when any editable field diverges from what the server returned.
    var isDirty: Bool { patch().isEmpty == false }

    var canSave: Bool { canEdit && !isSaving && !hasValidationErrors && isDirty }

    // MARK: - Save

    /// Build the sparse PATCH: a field is included only when it changed. An
    /// editable that was originally non-nil and is now empty is sent as `""`
    /// (the server coerces empty → null); `name` is never cleared.
    private func patch() -> OrgPatch {
        guard let original = org else { return OrgPatch() }
        var built = OrgPatch()
        func diff(_ current: String, _ orig: String?) -> String? {
            let cur = current.trimmingCharacters(in: .whitespaces)
            return cur == (orig ?? "") ? nil : cur
        }
        if name.trimmingCharacters(in: .whitespaces) != original.name {
            built.name = name.trimmingCharacters(in: .whitespaces)
        }
        let normalisedType = (type == "person") ? "person" : "company"
        if normalisedType != original.type { built.type = normalisedType }
        built.legalName = diff(legalName, original.legalName)
        built.taxNumber = diff(taxNumber, original.taxNumber)
        built.commercialRegisterNo = diff(commercialRegisterNo, original.commercialRegisterNo)
        built.billingEmail = diff(billingEmail, original.billingEmail)
        built.supportEmail = diff(supportEmail, original.supportEmail)
        built.phone = diff(phone, original.phone)
        built.website = diff(website, original.website)
        built.addressLine1 = diff(addressLine1, original.addressLine1)
        built.addressLine2 = diff(addressLine2, original.addressLine2)
        built.city = diff(city, original.city)
        built.country = diff(country, original.country)
        built.logoURL = diff(logoURL, original.logoURL)
        return built
    }

    func save() {
        guard canSave, let repository else { return }
        let body = patch()
        guard !body.isEmpty else { return }
        error = nil
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                let updated = try await repository.updateOrg(body)
                apply(updated)
                toast = Toast(message: NSLocalizedString("org.profile.savedToast", value: "Saved", comment: ""))
            } catch {
                self.error = AppError.from(error)
            }
        }
    }
}
