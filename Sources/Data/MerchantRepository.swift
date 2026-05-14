import Foundation
import Combine
import Payhub

/// The app's single gateway to the PayHub backend.
///
/// Owns the `PayhubMerchantClient` (rebuilt when the server URL or the token
/// pair changes), wires its `onTokensRefreshed` to the Keychain so transparent
/// refresh persists, exposes `async throws` methods that translate `PayhubError`
/// to `AppError`, and publishes an `authState` the UI watches to swap between
/// the login flow and the main tab view.
///
/// `@MainActor` so `@Published` mutations are on the main thread; the actual
/// network calls go to the `PayhubMerchantClient` actor.
@MainActor
final class MerchantRepository: ObservableObject {

    enum AuthState: Equatable {
        case undetermined          // launch: deciding from Keychain
        case unauthenticated
        case authenticated(MerchantMe)

        static func == (lhs: AuthState, rhs: AuthState) -> Bool {
            switch (lhs, rhs) {
            case (.undetermined, .undetermined), (.unauthenticated, .unauthenticated): return true
            case let (.authenticated(a), .authenticated(b)): return a.id == b.id
            default: return false
            }
        }
    }

    @Published private(set) var authState: AuthState = .undetermined

    private let tokenStore: KeychainTokenStore
    private let settings: AppSettings
    private var client: PayhubMerchantClient

    /// The merchant identity from the last `me()`. `nil` when not authenticated.
    var me: MerchantMe? {
        if case let .authenticated(m) = authState { return m }
        return nil
    }

    init(settings: AppSettings = .shared, tokenStore: KeychainTokenStore = .shared) {
        self.settings = settings
        self.tokenStore = tokenStore
        self.client = MerchantRepository.makeClient(baseURL: settings.serverURL,
                                                    tokens: tokenStore.load(),
                                                    tokenStore: tokenStore)
    }

    // MARK: - Client construction

    private static func makeClient(baseURL: URL, tokens: TokenPair?, tokenStore: KeychainTokenStore) -> PayhubMerchantClient {
        PayhubMerchantClient(
            baseURL: baseURL,
            accessToken: tokens?.accessToken,
            refreshToken: tokens?.refreshToken,
            onTokensRefreshed: { pair in
                // @Sendable closure — Keychain access is thread-safe.
                tokenStore.save(pair)
            }
        )
    }

    /// Rebuild the client against a (possibly new) server URL — used when the
    /// user edits the URL on the login screen, or after sign-out.
    private func rebuildClient(tokens: TokenPair?) {
        client = MerchantRepository.makeClient(baseURL: settings.serverURL, tokens: tokens, tokenStore: tokenStore)
    }

    // (1.2.0 removed the in-app raw HTTP shim + its bespoke refresh coalescing.
    // The SDK actor now handles 401 → refresh → retry on its own.)

    // MARK: - Bootstrap

    /// Called once at launch. If a token pair is in the Keychain, validate it
    /// with `me()`. On success → `.authenticated`; on auth failure → clear and
    /// `.unauthenticated`; on a transient failure we still go `.authenticated`
    /// optimistically? No — be conservative: a transient failure keeps tokens
    /// but lands on `.unauthenticated` so the user can retry by signing in.
    func bootstrap() async {
        guard tokenStore.load() != nil else {
            authState = .unauthenticated
            return
        }
        do {
            let me = try await client.auth.me()
            authState = .authenticated(me)
        } catch {
            let app = AppError.from(error)
            if app.isAuthFailure {
                tokenStore.clear()
                rebuildClient(tokens: nil)
            }
            authState = .unauthenticated
        }
    }

    // MARK: - Auth

    /// Update the server URL (only allowed while not authenticated) and rebuild.
    func updateServerURL(_ string: String) {
        settings.serverURLString = string
        rebuildClient(tokens: nil)
    }

    /// Returns `.mfaRequired(challengeToken)` when a second factor is needed.
    enum LoginOutcome { case authenticated(MerchantMe); case mfaRequired(challengeToken: String) }

    func login(merchantCode: String, username: String, password: String, subCode: String?) async throws -> LoginOutcome {
        do {
            let result = try await client.auth.login(merchantCode: merchantCode, username: username,
                                                     password: password, subCode: subCode?.isEmpty == true ? nil : subCode)
            if result.requiresMFA, let challenge = result.challengeToken {
                return .mfaRequired(challengeToken: challenge)
            }
            return .authenticated(try await finishLogin())
        } catch {
            throw AppError.from(error)
        }
    }

    func completeMFA(challengeToken: String, code: String) async throws -> MerchantMe {
        do {
            _ = try await client.auth.loginMfa(challengeToken: challengeToken, code: code)
            return try await finishLogin()
        } catch {
            throw AppError.from(error)
        }
    }

    /// After tokens are set in the client, persist them, fetch `me()`, flip state.
    private func finishLogin() async throws -> MerchantMe {
        if let tokens = await client.currentTokens() { tokenStore.save(tokens) }
        let me = try await client.auth.me()
        authState = .authenticated(me)
        return me
    }

    func refreshMe() async throws -> MerchantMe {
        do {
            let me = try await client.auth.me()
            authState = .authenticated(me)
            return me
        } catch {
            let app = AppError.from(error)
            if app.isAuthFailure { await forceSignOut() }
            throw app
        }
    }

    func forgotPassword(merchantCode: String, username: String, subCode: String?) async throws {
        do {
            try await client.auth.forgotPassword(merchantCode: merchantCode, username: username,
                                                 subCode: subCode?.isEmpty == true ? nil : subCode)
        } catch {
            throw AppError.from(error)
        }
    }

    func acceptInvite(token: String, newPassword: String) async throws {
        do {
            try await client.auth.acceptInvite(token: token, newPassword: newPassword)
        } catch {
            throw AppError.from(error)
        }
    }

    func signOut() async {
        try? await client.auth.logout()
        await forceSignOut()
    }

    /// Local sign-out: clear Keychain, drop tokens, return to login.
    private func forceSignOut() async {
        tokenStore.clear()
        rebuildClient(tokens: nil)
        authState = .unauthenticated
    }

    // MARK: - Dashboard

    func dashboard(windowHours: Int) async throws -> MerchantDashboard {
        do { return try await client.reports.dashboard(windowHours: windowHours) }
        catch { throw mapped(error) }
    }

    func dashboardBySub(windowHours: Int) async throws -> [SubBreakdownRow] {
        do { return try await client.reports.dashboardBySub(windowHours: windowHours).subBreakdown }
        catch { throw mapped(error) }
    }

    // MARK: - Pay-links

    func payLinks(filter: PayLinkFilter, limit: Int = 50, cursor: String? = nil) async throws -> PayLinkList {
        let q = filter.query
        do { return try await client.payLinks.list(status: q.status, bucket: q.bucket, limit: limit, cursor: cursor) }
        catch { throw mapped(error) }
    }

    func payLink(_ id: String) async throws -> PayLink {
        do { return try await client.payLinks.get(id) } catch { throw mapped(error) }
    }

    func createPayLink(_ request: CreatePayLinkRequest) async throws -> PayLink {
        do { return try await client.payLinks.create(request) } catch { throw mapped(error) }
    }

    func cancelPayLink(_ id: String) async throws -> PayLink {
        do { return try await client.payLinks.cancel(id) } catch { throw mapped(error) }
    }

    func extendPayLink(_ id: String, additionalSeconds: Int) async throws -> PayLink {
        do { return try await client.payLinks.extend(id, additionalSeconds: additionalSeconds) } catch { throw mapped(error) }
    }

    func clonePayLink(_ id: String) async throws -> PayLink {
        do { return try await client.payLinks.clone(id) } catch { throw mapped(error) }
    }

    func markPayLinkShared(_ id: String) async throws -> PayLink {
        do { return try await client.payLinks.markShared(id) } catch { throw mapped(error) }
    }

    // MARK: - Payments (SDK 1.2)

    func payments(psp: String? = nil, status: String? = nil,
                  subMerchantId: String? = nil, after: String? = nil,
                  limit: Int = 50) async throws -> [PaymentRow] {
        do { return try await client.payments.list(
            status: status, subMerchantId: subMerchantId, after: after, limit: limit).items }
        catch { throw mapped(error) }
    }

    func payment(_ id: String) async throws -> PaymentView {
        do { return try await client.payments.get(id) } catch { throw mapped(error) }
    }

    // MARK: - Settlements (SDK 1.2)

    func settlements(subMerchantId: String? = nil, after: String? = nil,
                     limit: Int = 50) async throws -> [Settlement] {
        do { return try await client.settlements.list(
            subMerchantId: subMerchantId, after: after, limit: limit).items }
        catch { throw mapped(error) }
    }

    func settlement(_ id: String) async throws -> Settlement {
        do { return try await client.settlements.get(id) } catch { throw mapped(error) }
    }

    func settlementRows(fileID: String, after: String? = nil,
                        limit: Int = 200) async throws -> [SettlementRow] {
        do { return try await client.settlements.rows(fileID, after: after, limit: limit).items }
        catch { throw mapped(error) }
    }

    // MARK: - Account / org / sub-merchants (SDK 1.2)

    func changePassword(oldPassword: String, newPassword: String, code: String?) async throws {
        do { try await client.account.changePassword(
            oldPassword: oldPassword, newPassword: newPassword, code: code) }
        catch { throw mapped(error) }
    }

    func mfaEnrol() async throws -> MfaEnrol {
        do { return try await client.account.mfaEnrol() } catch { throw mapped(error) }
    }

    func mfaConfirm(code: String) async throws {
        do { try await client.account.mfaConfirm(code: code) } catch { throw mapped(error) }
        try? await refreshMe()   // flip `mfaEnabled` so the More-screen badge updates
    }

    func mfaDisable(password: String) async throws {
        do { try await client.account.mfaDisable(password: password) } catch { throw mapped(error) }
        try? await refreshMe()
    }

    func getOrg() async throws -> OrgInfo {
        do { return try await client.org.get() } catch { throw mapped(error) }
    }

    func updateOrg(_ patch: OrgPatch) async throws -> OrgInfo {
        do { return try await client.org.update(patch) } catch { throw mapped(error) }
    }

    func listSubMerchants() async throws -> [SubMerchant] {
        do { return try await client.subMerchants.list() } catch { throw mapped(error) }
    }

    func getSubMerchant(id: String) async throws -> SubMerchant {
        do { return try await client.subMerchants.get(id) } catch { throw mapped(error) }
    }

    func createSubMerchant(_ body: SubMerchantCreate) async throws -> SubMerchant {
        do { return try await client.subMerchants.create(body) } catch { throw mapped(error) }
    }

    func updateSubMerchant(id: String, _ body: SubMerchantPatch) async throws -> SubMerchant {
        do { return try await client.subMerchants.update(id, body) } catch { throw mapped(error) }
    }

    func deleteSubMerchant(id: String) async throws {
        do { try await client.subMerchants.delete(id) } catch { throw mapped(error) }
    }

    func listSubUsers(subID: String) async throws -> [SubUser] {
        do { return try await client.subMerchants.users.list(subMerchantId: subID) }
        catch { throw mapped(error) }
    }

    func createSubUser(subID: String, _ body: SubUserCreate) async throws -> SubUserCreated {
        do { return try await client.subMerchants.users.create(subMerchantId: subID, body) }
        catch { throw mapped(error) }
    }

    func updateSubUser(subID: String, uid: String, _ body: SubUserPatch) async throws -> SubUser {
        do { return try await client.subMerchants.users.update(
            subMerchantId: subID, userId: uid, body) }
        catch { throw mapped(error) }
    }

    func disableSubUser(subID: String, uid: String) async throws {
        do { try await client.subMerchants.users.disable(
            subMerchantId: subID, userId: uid) }
        catch { throw mapped(error) }
    }

    func reissueSubUserInvite(subID: String, uid: String) async throws -> ReissueInvite {
        do { return try await client.subMerchants.users.reissueInvite(
            subMerchantId: subID, userId: uid) }
        catch { throw mapped(error) }
    }

    func clearSubUserMfa(subID: String, uid: String, code: String) async throws {
        do { try await client.subMerchants.users.clearMfa(
            subMerchantId: subID, userId: uid, code: code) }
        catch { throw mapped(error) }
    }

    // MARK: - Sub-merchant API keys (SDK 1.2)

    /// List the masked API keys minted for one sub-merchant.
    func listSubApiKeys(subID: String) async throws -> [MerchantApiKey] {
        do { return try await client.subMerchants.apiKeys.list(subMerchantId: subID) }
        catch { throw mapped(error) }
    }

    /// Mint a new sub-API-key. The plaintext `secret` on the result is shown
    /// **once** — there is no way to recover it (the server stores only an
    /// argon2 hash). UI must surface it in a copy-or-it-is-gone sheet.
    func createSubApiKey(subID: String,
                         scopes: [String],
                         allowedIps: [String] = [],
                         rateLimitTier: String = "standard") async throws -> MerchantApiKeyWithSecret {
        do { return try await client.subMerchants.apiKeys.create(
            subMerchantId: subID, scopes: scopes,
            allowedIps: allowedIps, rateLimitTier: rateLimitTier) }
        catch { throw mapped(error) }
    }

    /// Revoke a sub-API-key. Returns the now-revoked masked row.
    func revokeSubApiKey(subID: String, keyID: String) async throws -> MerchantApiKey {
        do { return try await client.subMerchants.apiKeys.revoke(
            subMerchantId: subID, keyId: keyID) }
        catch { throw mapped(error) }
    }

    // MARK: - Push

    func registerDevice(apnsTokenHex: String) async throws {
        do { _ = try await client.devices.register(platform: .ios, token: apnsTokenHex) }
        catch { throw mapped(error) }
    }

    func unregisterDevice(apnsTokenHex: String) async throws {
        do { try await client.devices.unregister(token: apnsTokenHex) }
        catch { throw mapped(error) }
    }

    // MARK: - Helpers

    /// Map an error to `AppError`, and if it's an auth failure, sign out so the
    /// UI bounces to login.
    private func mapped(_ error: Error) -> AppError {
        let app = AppError.from(error)
        if app.isAuthFailure { Task { await forceSignOut() } }
        return app
    }
}
