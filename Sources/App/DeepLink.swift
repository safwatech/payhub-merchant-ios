import Foundation
import Combine

/// Parsed `payhub://…` deep links the app understands.
enum DeepLink: Equatable {
    /// `payhub://accept-invite?token=…&m=…&u=…&s=…`
    case acceptInvite(token: String, merchantCode: String?, username: String?, subCode: String?)
    /// `payhub://pay-link/<id>`  (also triggered from a push notification tap)
    case payLink(id: String)

    static func parse(_ url: URL) -> DeepLink? {
        // Universal Link form (0.4.0+): `https://app.payhub.ly/m/accept-invite?token=…`.
        // Authoritative ID is hostname; path-prefix decides the route. Anything
        // else under `app.payhub.ly` is intentionally ignored so a stray
        // `/some/marketing/page` URL doesn't open the app to a blank screen —
        // the OS will fall back to Safari.
        if url.scheme?.lowercased() == "https", url.host?.lowercased() == "app.payhub.ly" {
            if url.path.hasPrefix("/m/accept-invite") {
                if let invite = parseInvite(url) {
                    return .acceptInvite(token: invite.token, merchantCode: invite.merchantCode,
                                          username: invite.username, subCode: invite.subCode)
                }
            }
            return nil
        }

        // Legacy custom-scheme form (kept through 0.4.0 for in-flight invite
        // emails) + the push pay-link path, which is a private custom-scheme
        // ride and not a user-facing URL.
        guard url.scheme?.lowercased() == "payhub" else { return nil }
        let host = url.host?.lowercased() ?? ""
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let items = components?.queryItems ?? []
        func q(_ name: String) -> String? { items.first { $0.name == name }?.value }

        switch host {
        case "accept-invite":
            if let invite = parseInvite(url) {
                return .acceptInvite(token: invite.token, merchantCode: invite.merchantCode,
                                      username: invite.username, subCode: invite.subCode)
            }
            return nil
        case "pay-link", "paylink":
            // payhub://pay-link/<id>  or  payhub://pay-link?id=<id>
            let pathID = url.pathComponents.first { $0 != "/" }
            if let id = pathID ?? q("id"), !id.isEmpty { return .payLink(id: id) }
            return nil
        default:
            return nil
        }
    }

    /// Pure parser for the invite query string — shared by the Universal Link
    /// (`https://app.payhub.ly/m/accept-invite?…`) and legacy custom-scheme
    /// (`payhub://accept-invite?…`) entry points. Returns `nil` when the
    /// required `token` is missing or empty.
    struct Invite: Equatable {
        let token: String
        let merchantCode: String?
        let username: String?
        let subCode: String?
    }
    static func parseInvite(_ url: URL) -> Invite? {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func q(_ name: String) -> String? { items.first { $0.name == name }?.value }
        guard let token = q("token"), !token.isEmpty else { return nil }
        return Invite(token: token, merchantCode: q("m"), username: q("u"), subCode: q("s"))
    }

    /// From an APNs payload: `{ "payhub": { "kind": "pay_link", "id": "…" } }`.
    static func fromPushUserInfo(_ userInfo: [AnyHashable: Any]) -> DeepLink? {
        guard let payhub = userInfo["payhub"] as? [String: Any] else { return nil }
        switch payhub["kind"] as? String {
        case "pay_link":
            if let id = payhub["id"] as? String, !id.isEmpty { return .payLink(id: id) }
            return nil
        default:
            return nil
        }
    }
}

/// App-wide router for pending deep links — views observe it and react.
@MainActor
final class AppRouter: ObservableObject {
    @Published var pendingInvite: DeepLink?            // accept-invite, shown over login
    @Published var selectedTab: MainTab = .dashboard
    @Published var pendingPayLinkID: String?           // a pay-link to push onto the Pay-links stack
    @Published var pendingPayLinkFilter: PayLinkFilter?  // a filter the Pay-links list should jump to

    func handle(_ link: DeepLink) {
        switch link {
        case .acceptInvite:
            pendingInvite = link
        case let .payLink(id):
            selectedTab = .payLinks
            pendingPayLinkID = id
        }
    }

    func handleURL(_ url: URL) {
        if let link = DeepLink.parse(url) { handle(link) }
    }
}

enum MainTab: Hashable {
    case dashboard, payLinks, payments, more
}

/// Routes that can be pushed onto the More tab's navigation stack.
enum MoreRoute: Hashable {
    case settlements
    case changePassword
    case mfaSettings
    case orgProfile
    case subMerchants
    /// More → Diagnostics (0.4.0) — crash-reporting opt-in. Hidden via the
    /// row's visibility, not the route enum, so the destination still resolves
    /// for unit tests that go directly to the page.
    case diagnostics
}

/// Routes pushed onto the sub-merchant management stack (lives under the More
/// tab's `NavigationStack`). Wrapped in its own enum so the type-segregated
/// `navigationDestination` for sub-merchants doesn't collide with `MoreRoute`.
enum SubMerchantsRoute: Hashable {
    case detail(id: String)
    case users(subID: String)
    /// Sub-merchant API keys (0.4.0). Parent-merchant keys remain
    /// web-portal-only — see CLAUDE.md "Native mobile apps" §.
    case apiKeys(subID: String)
}
