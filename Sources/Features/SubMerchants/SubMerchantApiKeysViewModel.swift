import Foundation
import Combine
import Payhub

/// Drives [SubMerchantApiKeysView]. Holds the masked-key list, the create
/// form's state, and the post-create reveal sheet that surfaces the plaintext
/// `secret` exactly once. Mirrors the Android `SubMerchantApiKeysViewModel`.
@MainActor
final class SubMerchantApiKeysViewModel: ObservableObject {
    let subID: String

    @Published private(set) var keys: [MerchantApiKey] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isCreating = false
    @Published private(set) var revokingId: String?
    @Published var error: AppError?
    @Published var toast: Toast?

    // Create-sheet state.
    @Published var showCreate = false
    @Published var createScopesText: String = "payments.write"
    @Published var createAllowedIpsText: String = ""
    @Published var createRateLimitTier: String = "standard"

    // Reveal-sheet state — non-nil ⇒ the SwiftUI `Sheet(item:)` presents.
    // Cleared via `dismissReveal` (the only legitimate exit so the secret
    // isn't left dangling in memory after the user taps "I've saved it").
    @Published var revealedKey: RevealedKey?

    /// Whether the form is valid enough to POST.
    var canCreate: Bool {
        !isCreating && !scopes.isEmpty
    }

    /// Tokenised scopes — split on whitespace / commas, trimmed.
    var scopes: [String] {
        createScopesText
            .split { c in c.isWhitespace || c == "," }
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var allowedIps: [String] {
        createAllowedIpsText
            .split { c in c.isWhitespace || c == "," }
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

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
        do { keys = try await repository.listSubApiKeys(subID: subID) }
        catch { self.error = AppError.from(error) }
    }

    func startCreate() {
        createScopesText = "payments.write"
        createAllowedIpsText = ""
        createRateLimitTier = "standard"
        showCreate = true
    }

    func submitCreate() {
        guard canCreate, let repository else { return }
        isCreating = true
        Task {
            defer { Task { @MainActor in self.isCreating = false } }
            do {
                let created = try await repository.createSubApiKey(
                    subID: subID, scopes: scopes,
                    allowedIps: allowedIps, rateLimitTier: createRateLimitTier)
                showCreate = false
                revealedKey = RevealedKey(
                    id: created.id, keyId: created.keyId, secret: created.secret)
                await load()
            } catch {
                self.error = AppError.from(error)
            }
        }
    }

    func revoke(_ key: MerchantApiKey) {
        guard let repository, revokingId == nil else { return }
        revokingId = key.id
        Task {
            defer { Task { @MainActor in self.revokingId = nil } }
            do {
                _ = try await repository.revokeSubApiKey(subID: subID, keyID: key.keyId)
                toast = Toast(message: NSLocalizedString("sub.apiKeys.revoked",
                                                          value: "Revoked", comment: ""))
                await load()
            } catch {
                self.error = AppError.from(error)
            }
        }
    }

    /// Clear the revealed-secret sheet. The struct is dropped from memory once
    /// the SwiftUI sheet's `Sheet(item:)` binding releases it.
    func dismissReveal() { revealedKey = nil }

    /// The plaintext API key + its identifier. Lives only inside
    /// `revealedKey` while the reveal sheet is visible.
    struct RevealedKey: Identifiable, Equatable {
        let id: String
        let keyId: String
        let secret: String
        /// Wire format the server expects: `phk_<key_id>.<secret>`.
        var wireFormat: String { "\(keyId).\(secret)" }
    }
}
