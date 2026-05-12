import Foundation
import Combine

@MainActor
final class SubMerchantDetailViewModel: ObservableObject {
    let subID: String

    @Published private(set) var sub: SubMerchant?
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published private(set) var isDeleting = false
    @Published private(set) var deleted = false
    @Published var error: AppError?
    @Published var toast: Toast?

    // Edit fields.
    @Published var name = ""
    @Published var active = true

    private weak var repository: MerchantRepository?
    private var didLoad = false

    init(subID: String) { self.subID = subID }

    func bind(repository: MerchantRepository) { self.repository = repository }

    func onAppear() {
        guard !didLoad else { return }
        didLoad = true
        Task { await load() }
    }

    func load() async {
        guard let repository else { return }
        isLoading = true
        defer { isLoading = false }
        do { apply(try await repository.getSubMerchant(id: subID)) }
        catch { self.error = AppError.from(error) }
    }

    private func apply(_ s: SubMerchant) {
        sub = s
        name = s.name
        active = s.isActive
    }

    var isDirty: Bool {
        guard let s = sub else { return false }
        return name.trimmingCharacters(in: .whitespaces) != s.name || active != s.isActive
    }
    var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && isDirty && !isSaving }
    var canDelete: Bool { (sub?.paymentsCount ?? 1) == 0 && !isDeleting }

    func save() {
        guard canSave, let repository, let s = sub else { return }
        var patch = SubMerchantPatch()
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if trimmed != s.name { patch.name = trimmed }
        if active != s.isActive { patch.status = active ? "active" : "disabled" }
        guard !patch.isEmpty else { return }
        error = nil
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                apply(try await repository.updateSubMerchant(id: subID, patch))
                toast = Toast(message: NSLocalizedString("sub.detail.updatedToast", value: "Updated", comment: ""))
            } catch {
                self.error = AppError.from(error)
            }
        }
    }

    func delete() {
        guard let repository else { return }
        error = nil
        isDeleting = true
        Task {
            defer { isDeleting = false }
            do {
                try await repository.deleteSubMerchant(id: subID)
                deleted = true
                toast = Toast(message: NSLocalizedString("sub.detail.deletedToast", value: "Deleted", comment: ""))
            } catch {
                self.error = AppError.from(error)
            }
        }
    }
}
