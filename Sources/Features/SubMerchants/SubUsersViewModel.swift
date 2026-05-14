import Foundation
import Combine
import Payhub

/// Roles a sub-user can hold; mirrors `SubMerchantRole` on the server
/// (`sub_owner` / `sub_operator` / `sub_viewer`).
enum SubUserRole: String, CaseIterable, Identifiable {
    case subOwner = "sub_owner"
    case subOperator = "sub_operator"
    case subViewer = "sub_viewer"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .subOwner: return NSLocalizedString("role.subOwner", value: "Shop owner", comment: "")
        case .subOperator: return NSLocalizedString("role.subOperator", value: "Shop operator", comment: "")
        case .subViewer: return NSLocalizedString("role.subViewer", value: "Shop viewer", comment: "")
        }
    }

    static func label(for raw: String) -> String {
        SubUserRole(rawValue: raw)?.label ?? roleLabel(raw)
    }
}

@MainActor
final class SubUsersViewModel: ObservableObject {
    let subID: String

    @Published private(set) var users: [SubUser] = []
    @Published private(set) var isLoading = false
    @Published var error: AppError?
    @Published var toast: Toast?

    // Invite sheet.
    @Published var showInvite = false
    @Published var inviteUsername = ""
    @Published var inviteFullName = ""
    @Published var inviteEmail = ""
    @Published var inviteMobile = ""
    @Published var invitePhone = ""
    @Published var inviteRole: SubUserRole = .subOperator
    @Published private(set) var isInviting = false
    @Published var inviteError: AppError?

    // Invite-link result (shown after a successful invite or re-issue).
    @Published var inviteResult: InviteResult?

    // Edit sheet.
    @Published var editUser: SubUser?
    @Published var editRole: SubUserRole = .subOperator
    @Published var editActive = true
    @Published private(set) var isEditing = false

    // Clear-MFA sheet.
    @Published var clearMfaUser: SubUser?
    @Published var clearMfaCode = ""
    @Published private(set) var isClearingMfa = false

    struct InviteResult: Identifiable {
        let id = UUID()
        let url: String
        let sentToChannel: String?
        /// Re-issue vs first invite — currently only used for the toast copy.
        let isReissue: Bool
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
        error = nil
        defer { isLoading = false }
        do { users = try await repository.listSubUsers(subID: subID) }
        catch { self.error = AppError.from(error) }
    }

    // MARK: - Invite

    var canInvite: Bool {
        usernameValid(inviteUsername.trimmingCharacters(in: .whitespaces))
            && !inviteFullName.trimmingCharacters(in: .whitespaces).isEmpty
            && !isInviting
    }
    func usernameValid(_ value: String) -> Bool {
        (3...64).contains(value.count)
            && value.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-" }
    }

    func startInvite() {
        inviteUsername = ""; inviteFullName = ""; inviteEmail = ""; inviteMobile = ""; invitePhone = ""
        inviteRole = .subOperator; inviteError = nil
        showInvite = true
    }

    func submitInvite() {
        guard canInvite, let repository else { return }
        inviteError = nil
        isInviting = true
        func nilIfEmpty(_ value: String) -> String? {
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? nil : trimmed
        }
        let body = SubUserCreate(
            username: inviteUsername.trimmingCharacters(in: .whitespaces),
            fullName: inviteFullName.trimmingCharacters(in: .whitespaces),
            email: nilIfEmpty(inviteEmail),
            mobile: nilIfEmpty(inviteMobile),
            phone: nilIfEmpty(invitePhone),
            role: inviteRole.rawValue)
        Task {
            defer { isInviting = false }
            do {
                let created = try await repository.createSubUser(subID: subID, body)
                users.insert(created.asSubUser, at: 0)
                showInvite = false
                inviteResult = InviteResult(url: created.inviteURL, sentToChannel: created.inviteSentToChannel, isReissue: false)
                toast = Toast(message: NSLocalizedString("subusers.invitedToast", value: "Invited", comment: ""))
            } catch {
                self.inviteError = AppError.from(error)
            }
        }
    }

    // MARK: - Edit

    func startEdit(_ user: SubUser) {
        editUser = user
        editRole = SubUserRole(rawValue: user.role) ?? .subOperator
        editActive = user.isActive
    }

    func submitEdit() {
        guard let repository, let target = editUser else { return }
        var patch = SubUserPatch()
        if editRole.rawValue != target.role { patch.role = editRole.rawValue }
        if editActive != target.isActive { patch.status = editActive ? "active" : "disabled" }
        guard !patch.isEmpty else { editUser = nil; return }
        isEditing = true
        Task {
            defer { isEditing = false }
            do {
                let updated = try await repository.updateSubUser(subID: subID, uid: target.id, patch)
                replace(updated)
                editUser = nil
                toast = Toast(message: NSLocalizedString("subusers.updatedToast", value: "Updated", comment: ""))
            } catch {
                self.error = AppError.from(error)
            }
        }
    }

    // MARK: - Disable

    func disable(_ user: SubUser) {
        guard let repository else { return }
        Task {
            do {
                try await repository.disableSubUser(subID: subID, uid: user.id)
                patchLocalUser(id: user.id) { $0.withStatus("disabled") }
                toast = Toast(message: NSLocalizedString("subusers.disabledToast", value: "Disabled", comment: ""))
            } catch {
                self.error = AppError.from(error)
            }
        }
    }

    // MARK: - Re-issue invite

    func reissue(_ user: SubUser) {
        guard let repository else { return }
        Task {
            do {
                let invite = try await repository.reissueSubUserInvite(subID: subID, uid: user.id)
                inviteResult = InviteResult(url: invite.inviteURL, sentToChannel: invite.sentToChannel, isReissue: true)
                toast = Toast(message: NSLocalizedString("subusers.reissuedToast", value: "Invite re-issued", comment: ""))
            } catch {
                self.error = AppError.from(error)
            }
        }
    }

    // MARK: - Clear MFA

    func startClearMfa(_ user: SubUser) {
        clearMfaUser = user
        clearMfaCode = ""
    }

    var canClearMfa: Bool {
        let digits = clearMfaCode.filter(\.isNumber)
        return digits.count >= 6 && digits.count <= 8 && !isClearingMfa
    }

    func submitClearMfa() {
        guard canClearMfa, let repository, let target = clearMfaUser else { return }
        isClearingMfa = true
        let digits = clearMfaCode.filter(\.isNumber)
        Task {
            defer { isClearingMfa = false }
            do {
                try await repository.clearSubUserMfa(subID: subID, uid: target.id, code: digits)
                patchLocalUser(id: target.id) { $0.withMfa(false) }
                clearMfaUser = nil
                clearMfaCode = ""
                toast = Toast(message: NSLocalizedString("subusers.mfaClearedToast", value: "Two-factor cleared", comment: ""))
            } catch {
                // Surface gracefully (e.g. owner_no_mfa, bad_mfa) and keep the sheet.
                self.error = AppError.from(error)
            }
        }
    }

    // MARK: - Helpers

    private func replace(_ updated: SubUser) {
        if let idx = users.firstIndex(where: { $0.id == updated.id }) { users[idx] = updated }
        else { users.insert(updated, at: 0) }
    }

    private func patchLocalUser(id: String, _ transform: (SubUser) -> SubUser) {
        guard let idx = users.firstIndex(where: { $0.id == id }) else { return }
        users[idx] = transform(users[idx])
    }
}

private extension SubUser {
    func withStatus(_ newStatus: String) -> SubUser {
        SubUser(id: id, subMerchantId: subMerchantId, username: username, role: role, status: newStatus,
                fullName: fullName, email: email, mobile: mobile, phone: phone,
                mfaEnabled: mfaEnabled, lastLoginAt: lastLoginAt, createdAt: createdAt)
    }
    func withMfa(_ enabled: Bool) -> SubUser {
        SubUser(id: id, subMerchantId: subMerchantId, username: username, role: role, status: status,
                fullName: fullName, email: email, mobile: mobile, phone: phone,
                mfaEnabled: enabled, lastLoginAt: lastLoginAt, createdAt: createdAt)
    }
}
