import Foundation
import Payhub

/// Thin `URLSession` client for the few `/merchant/*` endpoints not yet covered
/// by the `payhub-swift` 1.1.0 SDK:
///   • `POST   /merchant/devices`                  — register an APNs device token
///   • `DELETE /merchant/devices` (body `{token}`) — unregister it (token in the
///     JSON body, not a query string, so it never lands in WAF/access logs)
///   • `GET    /merchant/dashboard?group_by=sub`   — per-shop breakdown (the SDK's
///     `MerchantDashboard` model doesn't expose `sub_breakdown`)
///
/// TODO(payhub): drop this once SDK 1.2 adds device registration + a
/// `dashboard(groupBySub:)` that returns the breakdown.
struct MerchantRawAPI {
    let baseURL: URL
    /// Pulls a fresh access token each call so token-refresh in the SDK is honoured.
    let accessTokenProvider: @Sendable () async -> String?
    var session: URLSession = .shared

    // MARK: Devices

    func registerDevice(apnsTokenHex: String) async throws {
        let body = try JSONEncoder().encode(["platform": "ios", "token": apnsTokenHex])
        _ = try await send(method: "POST", path: "/merchant/devices", query: nil, body: body)
    }

    func unregisterDevice(apnsTokenHex: String) async throws {
        let body = try JSONEncoder().encode(["token": apnsTokenHex])
        _ = try await send(method: "DELETE", path: "/merchant/devices", query: nil, body: body)
    }

    // MARK: Dashboard breakdown

    /// `GET /merchant/dashboard?group_by=sub&window_hours=…` → decoded leniently.
    func dashboardBySub(windowHours: Int) async throws -> [SubBreakdownRow] {
        let data = try await send(
            method: "GET", path: "/merchant/dashboard",
            query: [URLQueryItem(name: "group_by", value: "sub"),
                    URLQueryItem(name: "window_hours", value: String(windowHours))],
            body: nil)
        let envelope = try JSONDecoder().decode(SubBreakdownEnvelope.self, from: data)
        return envelope.subBreakdown ?? []
    }

    // MARK: - Plumbing

    private func send(method: String, path: String, query: [URLQueryItem]?, body: Data?) async throws -> Data {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        components?.queryItems = query
        guard let url = components?.url else {
            throw PayhubError.transport(kind: .connection, message: "bad URL")
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("payhub-merchant-ios/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        if let token = await accessTokenProvider() {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                throw PayhubError.transport(kind: .decode, message: "non-HTTP response")
            }
            guard (200..<300).contains(http.statusCode) else {
                let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
                throw mapEnvelope(status: http.statusCode, body: data, retryAfter: retryAfter)
            }
            return data
        } catch let pe as PayhubError {
            throw pe
        } catch let urlErr as URLError {
            throw urlErr.code == .timedOut
                ? PayhubError.transport(kind: .timeout, message: urlErr.localizedDescription)
                : PayhubError.transport(kind: .connection, message: urlErr.localizedDescription)
        } catch {
            throw PayhubError.transport(kind: .connection, message: "\(error)")
        }
    }

    /// Minimal copy of the SDK's error-envelope mapping (it's `internal` there).
    private func mapEnvelope(status: Int, body: Data, retryAfter: Int?) -> PayhubError {
        var code = "hub.unknown"
        var message = "HTTP \(status)"
        var requestId: String?
        if !body.isEmpty,
           let parsed = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
           let err = parsed["error"] as? [String: Any] {
            code = err["code"] as? String ?? code
            message = err["message"] as? String ?? message
            requestId = err["request_id"] as? String
        }
        let kind: PayhubError.APIKind
        switch status {
        case 401: kind = .authentication
        case 403: kind = .permission
        case 404: kind = .notFound
        case 409: kind = .idempotencyConflict
        case 422: kind = .validation
        case 429: kind = .rateLimited(retryAfter: retryAfter)
        case 500..<600: kind = .server
        default: kind = .other
        }
        return .api(kind: kind, code: code, httpStatus: status, message: message, details: [:], requestId: requestId)
    }
}

// MARK: - Sub-breakdown decoding

struct SubBreakdownRow: Decodable, Identifiable {
    let subMerchantId: String
    let code: String?
    let name: String?
    let paid: Int
    let volumeMinor: Int64
    let inflight: Int
    let activePayLinks: Int

    var id: String { subMerchantId }

    enum CodingKeys: String, CodingKey {
        case subMerchantId = "sub_merchant_id"
        case code, name
        case paid
        case volumeMinor = "volume_minor"
        case inflight
        case activePayLinks = "active_pay_links"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        subMerchantId = try c.decode(String.self, forKey: .subMerchantId)
        code = try? c.decodeIfPresent(String.self, forKey: .code)
        name = try? c.decodeIfPresent(String.self, forKey: .name)
        paid = (try? c.decode(Int.self, forKey: .paid)) ?? 0
        volumeMinor = (try? c.decode(Int64.self, forKey: .volumeMinor)) ?? 0
        inflight = (try? c.decode(Int.self, forKey: .inflight)) ?? 0
        activePayLinks = (try? c.decode(Int.self, forKey: .activePayLinks)) ?? 0
    }
}

private struct SubBreakdownEnvelope: Decodable {
    let subBreakdown: [SubBreakdownRow]?
    enum CodingKeys: String, CodingKey { case subBreakdown = "sub_breakdown" }
}
