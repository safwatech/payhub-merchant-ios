import Foundation
import Combine

@MainActor
final class SubMerchantsViewModel: ObservableObject {
    @Published private(set) var subs: [SubMerchant] = []
    @Published private(set) var isLoading = false
    @Published var error: AppError?
    @Published var toast: Toast?

    // Create-sheet state.
    @Published var showCreate = false
    @Published var newCode = ""
    @Published var newPrefix = ""
    @Published var newName = ""
    @Published var newActive = true
    @Published private(set) var isCreating = false
    @Published var createError: AppError?

    private weak var repository: MerchantRepository?
    private var didLoad = false

    func bind(repository: MerchantRepository) { self.repository = repository }

    func onAppear() {
        guard !didLoad else { return }
        didLoad = true
        Task { await load() }
    }

    func load() async {
        guard let repository else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do { subs = try await repository.listSubMerchants() }
        catch { self.error = AppError.from(error) }
    }

    // MARK: - Create

    var canCreate: Bool {
        let code = newCode.trimmingCharacters(in: .whitespaces)
        let prefix = newPrefix.trimmingCharacters(in: .whitespaces)
        let name = newName.trimmingCharacters(in: .whitespaces)
        return codeValid(code) && prefixValid(prefix) && !name.isEmpty && !isCreating
    }
    func codeValid(_ s: String) -> Bool {
        guard let first = s.first, ("a"..."z").contains(first) || ("0"..."9").contains(first) else { return false }
        return s.count <= 64 && s.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-" || $0 == "_" }
    }
    func prefixValid(_ s: String) -> Bool {
        (2...6).contains(s.count) && s.allSatisfy { ("A"..."Z").contains($0) || ("0"..."9").contains($0) }
    }

    func startCreate() {
        newCode = ""; newPrefix = ""; newName = ""; newActive = true; createError = nil
        showCreate = true
    }

    func submitCreate(onDone: @escaping () -> Void) {
        guard canCreate, let repository else { return }
        createError = nil
        isCreating = true
        let body = SubMerchantCreate(
            code: newCode.trimmingCharacters(in: .whitespaces),
            codePrefix: newPrefix.trimmingCharacters(in: .whitespaces),
            name: newName.trimmingCharacters(in: .whitespaces),
            status: newActive ? "active" : "disabled",
            externalRef: nil)
        Task {
            defer { isCreating = false }
            do {
                let created = try await repository.createSubMerchant(body)
                subs.insert(created, at: 0)
                toast = Toast(message: NSLocalizedString("subs.createdToast", value: "Sub-merchant created", comment: ""))
                onDone()
            } catch {
                self.createError = AppError.from(error)
            }
        }
    }
}
