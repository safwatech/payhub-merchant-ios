import Foundation
import Combine

/// Parsed `payhub://…` deep links the app understands.
enum DeepLink: Equatable {
    /// `payhub://accept-invite?token=…&m=…&u=…&s=…`
    case acceptInvite(token: String, merchantCode: String?, username: String?, subCode: String?)
    /// `payhub://pay-link/<id>`  (also triggered from a push notification tap)
    case payLink(id: String)

    static func parse(_ url: URL) -> DeepLink? {
        guard url.scheme?.lowercased() == "payhub" else { return nil }
        let host = url.host?.lowercased() ?? ""
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let items = components?.queryItems ?? []
        func q(_ name: String) -> String? { items.first { $0.name == name }?.value }

        switch host {
        case "accept-invite":
            guard let token = q("token"), !token.isEmpty else { return nil }
            return .acceptInvite(token: token, merchantCode: q("m"), username: q("u"), subCode: q("s"))
        case "pay-link", "paylink":
            // payhub://pay-link/<id>  or  payhub://pay-link?id=<id>
            let pathID = url.pathComponents.first { $0 != "/" }
            if let id = pathID ?? q("id"), !id.isEmpty { return .payLink(id: id) }
            return nil
        default:
            return nil
        }
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
    case dashboard, payLinks, more
}
