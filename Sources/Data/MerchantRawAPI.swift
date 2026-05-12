import Foundation
import Payhub

/// Thin `URLSession` client for the `/merchant/*` endpoints not yet covered
/// by the `payhub-swift` 1.1.0 SDK:
///   • `POST   /merchant/devices`                  — register an APNs device token
///   • `DELETE /merchant/devices` (body `{token}`) — unregister it (token in the
///     JSON body, not a query string, so it never lands in WAF/access logs)
///   • `GET    /merchant/dashboard?group_by=sub`   — per-shop breakdown (the SDK's
///     `MerchantDashboard` model doesn't expose `sub_breakdown`)
///   • `GET    /merchant/payments`                 — payments list
///   • `GET    /merchant/payments/{id}`            — payment detail + events + metadata
///   • `GET    /merchant/settlements`              — settlement files list
///   • `GET    /merchant/settlements/{id}`         — one settlement file
///   • `GET    /merchant/settlements/{id}/rows`    — per-file reconciliation rows
///   • `POST   /merchant/auth/change-password`     — change own password
///   • `POST   /merchant/auth/mfa/{enrol,confirm,disable}` — own two-factor mgmt
///   • `GET/PATCH /merchant/org`                   — organisation profile
///   • `GET/POST/PATCH/DELETE /merchant/sub-merchants[/{id}]`        — sub-merchants
///   • `GET/POST/PATCH/DELETE /merchant/sub-merchants/{sid}/users[/{uid}]` — sub-users
///   • `POST   /merchant/sub-merchants/{sid}/users/{uid}/reissue-invite`  — re-mint invite
///   • `POST   /merchant/sub-merchants/{sid}/users/{uid}/clear-mfa`       — clear a sub-user's MFA
///
/// The decoders mirror the Pydantic response models 1:1 (see
/// `app/api/merchant/payments.py`, `settlements.py`, `auth.py`, `mfa.py`,
/// `org.py`, `sub_merchants.py`).
///
/// TODO(payhub): drop this once SDK 1.2 ships `payments`, `settlements`,
/// `devices`, the sub-breakdown, change-password, MFA mgmt, org, and the
/// sub-merchant/sub-user endpoints.
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

    // MARK: Payments

    /// `GET /merchant/payments?psp=&status=&limit=&offset=`. Server caps `limit` at 200.
    func listPayments(psp: String? = nil, status: String? = nil,
                      limit: Int = 50, offset: Int = 0) async throws -> [PaymentRow] {
        var query: [URLQueryItem] = []
        if let psp, !psp.isEmpty { query.append(URLQueryItem(name: "psp", value: psp)) }
        if let status, !status.isEmpty { query.append(URLQueryItem(name: "status", value: status)) }
        query.append(URLQueryItem(name: "limit", value: String(min(max(limit, 1), 200))))
        query.append(URLQueryItem(name: "offset", value: String(max(offset, 0))))
        let data = try await send(method: "GET", path: "/merchant/payments", query: query, body: nil)
        return try JSONDecoder().decode([PaymentRow].self, from: data)
    }

    func getPayment(id: String) async throws -> PaymentDetail {
        let data = try await send(method: "GET", path: "/merchant/payments/\(id)", query: nil, body: nil)
        return try JSONDecoder().decode(PaymentDetail.self, from: data)
    }

    // MARK: Settlements

    /// `GET /merchant/settlements?psp=&limit=&offset=`. Server caps `limit` at 200.
    func listSettlements(psp: String? = nil, limit: Int = 50, offset: Int = 0) async throws -> [SettlementFile] {
        var query: [URLQueryItem] = []
        if let psp, !psp.isEmpty { query.append(URLQueryItem(name: "psp", value: psp)) }
        query.append(URLQueryItem(name: "limit", value: String(min(max(limit, 1), 200))))
        query.append(URLQueryItem(name: "offset", value: String(max(offset, 0))))
        let data = try await send(method: "GET", path: "/merchant/settlements", query: query, body: nil)
        return try JSONDecoder().decode([SettlementFile].self, from: data)
    }

    func getSettlement(id: String) async throws -> SettlementFile {
        let data = try await send(method: "GET", path: "/merchant/settlements/\(id)", query: nil, body: nil)
        return try JSONDecoder().decode(SettlementFile.self, from: data)
    }

    /// `GET /merchant/settlements/{id}/rows?status_filter=&limit=&offset=`. Server caps at 1000.
    func listSettlementRows(fileID: String, statusFilter: String? = nil,
                            limit: Int = 100, offset: Int = 0) async throws -> [SettlementRow] {
        var query: [URLQueryItem] = []
        if let statusFilter, !statusFilter.isEmpty {
            query.append(URLQueryItem(name: "status_filter", value: statusFilter))
        }
        query.append(URLQueryItem(name: "limit", value: String(min(max(limit, 1), 1000))))
        query.append(URLQueryItem(name: "offset", value: String(max(offset, 0))))
        let data = try await send(method: "GET", path: "/merchant/settlements/\(fileID)/rows", query: query, body: nil)
        return try JSONDecoder().decode([SettlementRow].self, from: data)
    }

    // MARK: - Account / password / MFA  (TODO(payhub): fold into SDK 1.2)

    // TODO(payhub): fold into SDK 1.2
    func changePassword(oldPassword: String, newPassword: String, code: String?) async throws {
        var dict: [String: String] = ["old_password": oldPassword, "new_password": newPassword]
        if let code, !code.isEmpty { dict["code"] = code }
        let body = try JSONEncoder().encode(dict)
        _ = try await send(method: "POST", path: "/merchant/auth/change-password", query: nil, body: body)
    }

    // TODO(payhub): fold into SDK 1.2
    func mfaEnrol() async throws -> MfaEnrol {
        let body = try JSONEncoder().encode([String: String]())
        let data = try await send(method: "POST", path: "/merchant/auth/mfa/enrol", query: nil, body: body)
        return try JSONDecoder().decode(MfaEnrol.self, from: data)
    }

    // TODO(payhub): fold into SDK 1.2
    func mfaConfirm(code: String) async throws {
        let body = try JSONEncoder().encode(["code": code])
        _ = try await send(method: "POST", path: "/merchant/auth/mfa/confirm", query: nil, body: body)
    }

    // TODO(payhub): fold into SDK 1.2
    func mfaDisable(password: String) async throws {
        let body = try JSONEncoder().encode(["password": password])
        _ = try await send(method: "POST", path: "/merchant/auth/mfa/disable", query: nil, body: body)
    }

    // MARK: - Organisation profile  (TODO(payhub): fold into SDK 1.2)

    // TODO(payhub): fold into SDK 1.2
    func getOrg() async throws -> OrgInfo {
        let data = try await send(method: "GET", path: "/merchant/org", query: nil, body: nil)
        return try JSONDecoder().decode(OrgInfo.self, from: data)
    }

    // TODO(payhub): fold into SDK 1.2
    func updateOrg(_ patch: OrgPatch) async throws -> OrgInfo {
        let body = try JSONEncoder().encode(patch)
        let data = try await send(method: "PATCH", path: "/merchant/org", query: nil, body: body)
        return try JSONDecoder().decode(OrgInfo.self, from: data)
    }

    // MARK: - Sub-merchants  (TODO(payhub): fold into SDK 1.2)

    // TODO(payhub): fold into SDK 1.2
    func listSubMerchants() async throws -> [SubMerchant] {
        let data = try await send(method: "GET", path: "/merchant/sub-merchants", query: nil, body: nil)
        return try JSONDecoder().decode([SubMerchant].self, from: data)
    }

    // TODO(payhub): fold into SDK 1.2
    func getSubMerchant(id: String) async throws -> SubMerchant {
        let data = try await send(method: "GET", path: "/merchant/sub-merchants/\(id)", query: nil, body: nil)
        return try JSONDecoder().decode(SubMerchant.self, from: data)
    }

    // TODO(payhub): fold into SDK 1.2
    func createSubMerchant(_ body: SubMerchantCreate) async throws -> SubMerchant {
        let data = try await send(method: "POST", path: "/merchant/sub-merchants",
                                  query: nil, body: try JSONEncoder().encode(body))
        return try JSONDecoder().decode(SubMerchant.self, from: data)
    }

    // TODO(payhub): fold into SDK 1.2
    func updateSubMerchant(id: String, _ body: SubMerchantPatch) async throws -> SubMerchant {
        let data = try await send(method: "PATCH", path: "/merchant/sub-merchants/\(id)",
                                  query: nil, body: try JSONEncoder().encode(body))
        return try JSONDecoder().decode(SubMerchant.self, from: data)
    }

    // TODO(payhub): fold into SDK 1.2
    func deleteSubMerchant(id: String) async throws {
        _ = try await send(method: "DELETE", path: "/merchant/sub-merchants/\(id)", query: nil, body: nil)
    }

    // MARK: - Sub-users  (TODO(payhub): fold into SDK 1.2)

    // TODO(payhub): fold into SDK 1.2
    func listSubUsers(subID: String) async throws -> [SubUser] {
        let data = try await send(method: "GET", path: "/merchant/sub-merchants/\(subID)/users", query: nil, body: nil)
        return try JSONDecoder().decode([SubUser].self, from: data)
    }

    // TODO(payhub): fold into SDK 1.2
    func createSubUser(subID: String, _ body: SubUserCreate) async throws -> SubUserCreated {
        let data = try await send(method: "POST", path: "/merchant/sub-merchants/\(subID)/users",
                                  query: nil, body: try JSONEncoder().encode(body))
        return try JSONDecoder().decode(SubUserCreated.self, from: data)
    }

    // TODO(payhub): fold into SDK 1.2
    func updateSubUser(subID: String, uid: String, _ body: SubUserPatch) async throws -> SubUser {
        let data = try await send(method: "PATCH", path: "/merchant/sub-merchants/\(subID)/users/\(uid)",
                                  query: nil, body: try JSONEncoder().encode(body))
        return try JSONDecoder().decode(SubUser.self, from: data)
    }

    // TODO(payhub): fold into SDK 1.2
    func disableSubUser(subID: String, uid: String) async throws {
        _ = try await send(method: "DELETE", path: "/merchant/sub-merchants/\(subID)/users/\(uid)", query: nil, body: nil)
    }

    // TODO(payhub): fold into SDK 1.2
    func reissueSubUserInvite(subID: String, uid: String) async throws -> ReissueInvite {
        let data = try await send(method: "POST",
                                  path: "/merchant/sub-merchants/\(subID)/users/\(uid)/reissue-invite",
                                  query: nil, body: nil)
        return try JSONDecoder().decode(ReissueInvite.self, from: data)
    }

    // TODO(payhub): fold into SDK 1.2
    func clearSubUserMfa(subID: String, uid: String, code: String) async throws {
        let body = try JSONEncoder().encode(["code": code])
        _ = try await send(method: "POST",
                           path: "/merchant/sub-merchants/\(subID)/users/\(uid)/clear-mfa",
                           query: nil, body: body)
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

    /// Minimal copy of the SDK's error-envelope mapping (it's `internal` there),
    /// plus a fallback to FastAPI's bare `{"detail": "…"}` shape (raised by
    /// `HTTPException` — e.g. `org.py`'s "no fields to update", the
    /// sub-merchant "has N payment(s)" 409) so those messages aren't swallowed.
    private func mapEnvelope(status: Int, body: Data, retryAfter: Int?) -> PayhubError {
        var code = "hub.unknown"
        var message = "HTTP \(status)"
        var requestId: String?
        if !body.isEmpty,
           let parsed = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
            if let err = parsed["error"] as? [String: Any] {
                code = err["code"] as? String ?? code
                message = err["message"] as? String ?? message
                requestId = err["request_id"] as? String
            } else if let detail = parsed["detail"] as? String, !detail.isEmpty {
                message = detail
            }
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

// MARK: - Payment models (mirror app/api/merchant/payments.py)

/// Lightweight any-codable wrapper for the `metadata` and `diff` fields, which
/// arrive as arbitrary JSON. We decode primitives + nested containers; arrays
/// of objects are flattened to a single primitive (`nil`) on display.
enum JSONValue: Decodable, Equatable {
    case string(String)
    case int(Int64)
    case double(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let v = try? c.decode(Bool.self) { self = .bool(v); return }
        if let v = try? c.decode(Int64.self) { self = .int(v); return }
        if let v = try? c.decode(Double.self) { self = .double(v); return }
        if let v = try? c.decode(String.self) { self = .string(v); return }
        if let v = try? c.decode([String: JSONValue].self) { self = .object(v); return }
        if let v = try? c.decode([JSONValue].self) { self = .array(v); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "unknown JSON type")
    }

    /// Compact display string for a primitive; nil for composite/null values.
    var displayString: String? {
        switch self {
        case .null, .object, .array: return nil
        case .string(let s): return s.isEmpty ? nil : s
        case .int(let i): return String(i)
        case .double(let d): return String(d)
        case .bool(let b): return b ? "true" : "false"
        }
    }

    /// For `diff` payloads shaped `{ "hub": …, "psp": … }`.
    func string(forKey key: String) -> String? {
        if case let .object(dict) = self, let v = dict[key] { return v.displayString }
        return nil
    }
}

struct PaymentRow: Decodable, Identifiable, Equatable {
    let id: String
    let pspCode: String
    let pspRef: String?
    let merchantOrderRef: String
    let amountMinor: Int64
    let currency: String
    let status: String
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case pspCode = "psp_code"
        case pspRef = "psp_ref"
        case merchantOrderRef = "merchant_order_ref"
        case amountMinor = "amount_minor"
        case currency, status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct PaymentEvent: Decodable, Identifiable, Equatable {
    let id: String
    let eventType: String
    let prevStatus: String?
    let newStatus: String?
    let source: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case eventType = "event_type"
        case prevStatus = "prev_status"
        case newStatus = "new_status"
        case source
        case createdAt = "created_at"
    }
}

struct PaymentDetail: Decodable, Identifiable, Equatable {
    let id: String
    let pspCode: String
    let pspRef: String?
    let merchantOrderRef: String
    let amountMinor: Int64
    let currency: String
    let status: String
    let createdAt: String
    let updatedAt: String
    let events: [PaymentEvent]
    let metadata: [String: JSONValue]

    enum CodingKeys: String, CodingKey {
        case id
        case pspCode = "psp_code"
        case pspRef = "psp_ref"
        case merchantOrderRef = "merchant_order_ref"
        case amountMinor = "amount_minor"
        case currency, status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case events, metadata
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        pspCode = try c.decode(String.self, forKey: .pspCode)
        pspRef = try c.decodeIfPresent(String.self, forKey: .pspRef)
        merchantOrderRef = try c.decode(String.self, forKey: .merchantOrderRef)
        amountMinor = try c.decode(Int64.self, forKey: .amountMinor)
        currency = try c.decode(String.self, forKey: .currency)
        status = try c.decode(String.self, forKey: .status)
        createdAt = try c.decode(String.self, forKey: .createdAt)
        updatedAt = try c.decode(String.self, forKey: .updatedAt)
        events = (try? c.decodeIfPresent([PaymentEvent].self, forKey: .events)) ?? []
        metadata = (try? c.decodeIfPresent([String: JSONValue].self, forKey: .metadata)) ?? [:]
    }
}

// MARK: - Settlement models (mirror app/api/merchant/settlements.py)

struct SettlementFile: Decodable, Identifiable, Equatable {
    let id: String
    let pspCode: String
    let filename: String
    let fileSha256: String
    let periodFrom: String?
    let periodTo: String?
    let rowCount: Int
    let matchedCount: Int
    let mismatchCount: Int
    let missingInHubCount: Int
    let missingInPspCount: Int
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case pspCode = "psp_code"
        case filename
        case fileSha256 = "file_sha256"
        case periodFrom = "period_from"
        case periodTo = "period_to"
        case rowCount = "row_count"
        case matchedCount = "matched_count"
        case mismatchCount = "mismatch_count"
        case missingInHubCount = "missing_in_hub_count"
        case missingInPspCount = "missing_in_psp_count"
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        pspCode = try c.decode(String.self, forKey: .pspCode)
        filename = try c.decode(String.self, forKey: .filename)
        fileSha256 = try c.decode(String.self, forKey: .fileSha256)
        periodFrom = try c.decodeIfPresent(String.self, forKey: .periodFrom)
        periodTo = try c.decodeIfPresent(String.self, forKey: .periodTo)
        rowCount = (try? c.decode(Int.self, forKey: .rowCount)) ?? 0
        matchedCount = (try? c.decode(Int.self, forKey: .matchedCount)) ?? 0
        mismatchCount = (try? c.decode(Int.self, forKey: .mismatchCount)) ?? 0
        missingInHubCount = (try? c.decode(Int.self, forKey: .missingInHubCount)) ?? 0
        missingInPspCount = (try? c.decode(Int.self, forKey: .missingInPspCount)) ?? 0
        createdAt = try c.decode(String.self, forKey: .createdAt)
    }
}

struct SettlementRow: Decodable, Identifiable, Equatable {
    let id: String
    let merchantOrderRef: String?
    let pspRef: String?
    let pspStatus: String?
    let amountMinor: Int64?
    let currency: String?
    let paymentId: String?
    let status: String
    let diff: [String: JSONValue]
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case merchantOrderRef = "merchant_order_ref"
        case pspRef = "psp_ref"
        case pspStatus = "psp_status"
        case amountMinor = "amount_minor"
        case currency
        case paymentId = "payment_id"
        case status, diff
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        merchantOrderRef = try c.decodeIfPresent(String.self, forKey: .merchantOrderRef)
        pspRef = try c.decodeIfPresent(String.self, forKey: .pspRef)
        pspStatus = try c.decodeIfPresent(String.self, forKey: .pspStatus)
        amountMinor = try c.decodeIfPresent(Int64.self, forKey: .amountMinor)
        currency = try c.decodeIfPresent(String.self, forKey: .currency)
        paymentId = try c.decodeIfPresent(String.self, forKey: .paymentId)
        status = try c.decode(String.self, forKey: .status)
        diff = (try? c.decodeIfPresent([String: JSONValue].self, forKey: .diff)) ?? [:]
        createdAt = try c.decode(String.self, forKey: .createdAt)
    }
}

// MARK: - Account / MFA models (mirror app/api/merchant/{auth,mfa}.py)

struct MfaEnrol: Decodable {
    let secret: String
    let otpauthURI: String
    let issuer: String
    let account: String

    enum CodingKeys: String, CodingKey {
        case secret
        case otpauthURI = "otpauth_uri"
        case issuer, account
    }
}

// MARK: - Organisation profile models (mirror app/api/merchant/org.py)

/// `GET /merchant/org` response — `id`/`code`/`name`/`type`/`status`/`created_at`
/// always present, the 12 profile fields optional.
struct OrgInfo: Decodable, Equatable {
    let id: String
    let code: String
    let name: String
    let type: String
    let status: String
    let createdAt: String
    let legalName: String?
    let taxNumber: String?
    let commercialRegisterNo: String?
    let billingEmail: String?
    let supportEmail: String?
    let phone: String?
    let website: String?
    let addressLine1: String?
    let addressLine2: String?
    let city: String?
    let country: String?
    let logoURL: String?

    enum CodingKeys: String, CodingKey {
        case id, code, name, type, status, phone, website, city, country
        case createdAt = "created_at"
        case legalName = "legal_name"
        case taxNumber = "tax_number"
        case commercialRegisterNo = "commercial_register_no"
        case billingEmail = "billing_email"
        case supportEmail = "support_email"
        case addressLine1 = "address_line_1"
        case addressLine2 = "address_line_2"
        case logoURL = "logo_url"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        code = try c.decode(String.self, forKey: .code)
        name = try c.decode(String.self, forKey: .name)
        type = (try? c.decode(String.self, forKey: .type)) ?? "company"
        status = (try? c.decode(String.self, forKey: .status)) ?? ""
        createdAt = (try? c.decode(String.self, forKey: .createdAt)) ?? ""
        legalName = try? c.decodeIfPresent(String.self, forKey: .legalName)
        taxNumber = try? c.decodeIfPresent(String.self, forKey: .taxNumber)
        commercialRegisterNo = try? c.decodeIfPresent(String.self, forKey: .commercialRegisterNo)
        billingEmail = try? c.decodeIfPresent(String.self, forKey: .billingEmail)
        supportEmail = try? c.decodeIfPresent(String.self, forKey: .supportEmail)
        phone = try? c.decodeIfPresent(String.self, forKey: .phone)
        website = try? c.decodeIfPresent(String.self, forKey: .website)
        addressLine1 = try? c.decodeIfPresent(String.self, forKey: .addressLine1)
        addressLine2 = try? c.decodeIfPresent(String.self, forKey: .addressLine2)
        city = try? c.decodeIfPresent(String.self, forKey: .city)
        country = try? c.decodeIfPresent(String.self, forKey: .country)
        logoURL = try? c.decodeIfPresent(String.self, forKey: .logoURL)
    }
}

/// Sparse `PATCH /merchant/org` body — `encode(to:)` uses `encodeIfPresent` so a
/// `nil` property is *omitted* (true PATCH semantics); to clear a server-side
/// value, pass `""` (the server coerces empty string → null). `code` isn't
/// editable, so it isn't here.
struct OrgPatch: Encodable {
    var name: String?
    var type: String?
    var legalName: String?
    var taxNumber: String?
    var commercialRegisterNo: String?
    var billingEmail: String?
    var supportEmail: String?
    var phone: String?
    var website: String?
    var addressLine1: String?
    var addressLine2: String?
    var city: String?
    var country: String?
    var logoURL: String?

    enum CodingKeys: String, CodingKey {
        case name, type, phone, website, city, country
        case legalName = "legal_name"
        case taxNumber = "tax_number"
        case commercialRegisterNo = "commercial_register_no"
        case billingEmail = "billing_email"
        case supportEmail = "support_email"
        case addressLine1 = "address_line_1"
        case addressLine2 = "address_line_2"
        case logoURL = "logo_url"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encodeIfPresent(type, forKey: .type)
        try c.encodeIfPresent(legalName, forKey: .legalName)
        try c.encodeIfPresent(taxNumber, forKey: .taxNumber)
        try c.encodeIfPresent(commercialRegisterNo, forKey: .commercialRegisterNo)
        try c.encodeIfPresent(billingEmail, forKey: .billingEmail)
        try c.encodeIfPresent(supportEmail, forKey: .supportEmail)
        try c.encodeIfPresent(phone, forKey: .phone)
        try c.encodeIfPresent(website, forKey: .website)
        try c.encodeIfPresent(addressLine1, forKey: .addressLine1)
        try c.encodeIfPresent(addressLine2, forKey: .addressLine2)
        try c.encodeIfPresent(city, forKey: .city)
        try c.encodeIfPresent(country, forKey: .country)
        try c.encodeIfPresent(logoURL, forKey: .logoURL)
    }

    /// `true` when nothing would be sent — the server 400s on an empty PATCH.
    var isEmpty: Bool {
        name == nil && type == nil && legalName == nil && taxNumber == nil
            && commercialRegisterNo == nil && billingEmail == nil && supportEmail == nil
            && phone == nil && website == nil && addressLine1 == nil && addressLine2 == nil
            && city == nil && country == nil && logoURL == nil
    }
}

// MARK: - Sub-merchant models (mirror app/api/merchant/sub_merchants.py)

struct SubMerchant: Decodable, Identifiable, Equatable {
    let id: String
    let merchantID: String
    let code: String
    let codePrefix: String
    let name: String
    let status: String
    let externalRef: String?
    let metadata: [String: JSONValue]
    let createdAt: String
    let updatedAt: String
    let paymentsCount: Int

    enum CodingKeys: String, CodingKey {
        case id, code, name, status, metadata
        case merchantID = "merchant_id"
        case codePrefix = "code_prefix"
        case externalRef = "external_ref"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case paymentsCount = "payments_count"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        merchantID = (try? c.decode(String.self, forKey: .merchantID)) ?? ""
        code = try c.decode(String.self, forKey: .code)
        codePrefix = (try? c.decode(String.self, forKey: .codePrefix)) ?? ""
        name = try c.decode(String.self, forKey: .name)
        status = (try? c.decode(String.self, forKey: .status)) ?? "active"
        externalRef = try? c.decodeIfPresent(String.self, forKey: .externalRef)
        metadata = (try? c.decodeIfPresent([String: JSONValue].self, forKey: .metadata)) ?? [:]
        createdAt = (try? c.decode(String.self, forKey: .createdAt)) ?? ""
        updatedAt = (try? c.decode(String.self, forKey: .updatedAt)) ?? ""
        paymentsCount = (try? c.decode(Int.self, forKey: .paymentsCount)) ?? 0
    }

    var isActive: Bool { status == "active" }
}

struct SubMerchantCreate: Encodable {
    var code: String
    var codePrefix: String
    var name: String
    var status: String
    var externalRef: String?

    enum CodingKeys: String, CodingKey {
        case code, name, status
        case codePrefix = "code_prefix"
        case externalRef = "external_ref"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(code, forKey: .code)
        try c.encode(codePrefix, forKey: .codePrefix)
        try c.encode(name, forKey: .name)
        try c.encode(status, forKey: .status)
        try c.encodeIfPresent(externalRef, forKey: .externalRef)
    }
}

struct SubMerchantPatch: Encodable {
    var name: String?
    var status: String?
    var externalRef: String?

    enum CodingKeys: String, CodingKey {
        case name, status
        case externalRef = "external_ref"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encodeIfPresent(status, forKey: .status)
        try c.encodeIfPresent(externalRef, forKey: .externalRef)
    }

    var isEmpty: Bool { name == nil && status == nil && externalRef == nil }
}

// MARK: - Sub-user models (mirror app/api/merchant/sub_merchants.py users)

struct SubUser: Decodable, Identifiable, Equatable {
    let id: String
    let subMerchantID: String
    let username: String
    let role: String
    let status: String
    let fullName: String
    let email: String?
    let mobile: String?
    let phone: String?
    let mfaEnabled: Bool
    let lastLoginAt: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, username, role, status, email, mobile, phone
        case subMerchantID = "sub_merchant_id"
        case fullName = "full_name"
        case mfaEnabled = "mfa_enabled"
        case lastLoginAt = "last_login_at"
        case createdAt = "created_at"
    }

    init(id: String, subMerchantID: String, username: String, role: String, status: String,
         fullName: String, email: String?, mobile: String?, phone: String?,
         mfaEnabled: Bool, lastLoginAt: String?, createdAt: String) {
        self.id = id
        self.subMerchantID = subMerchantID
        self.username = username
        self.role = role
        self.status = status
        self.fullName = fullName
        self.email = email
        self.mobile = mobile
        self.phone = phone
        self.mfaEnabled = mfaEnabled
        self.lastLoginAt = lastLoginAt
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        subMerchantID = (try? c.decode(String.self, forKey: .subMerchantID)) ?? ""
        username = try c.decode(String.self, forKey: .username)
        role = (try? c.decode(String.self, forKey: .role)) ?? "sub_operator"
        status = (try? c.decode(String.self, forKey: .status)) ?? "active"
        fullName = (try? c.decode(String.self, forKey: .fullName)) ?? ""
        email = try? c.decodeIfPresent(String.self, forKey: .email)
        mobile = try? c.decodeIfPresent(String.self, forKey: .mobile)
        phone = try? c.decodeIfPresent(String.self, forKey: .phone)
        mfaEnabled = (try? c.decode(Bool.self, forKey: .mfaEnabled)) ?? false
        lastLoginAt = try? c.decodeIfPresent(String.self, forKey: .lastLoginAt)
        createdAt = (try? c.decode(String.self, forKey: .createdAt)) ?? ""
    }

    var isActive: Bool { status == "active" }
}

struct SubUserCreate: Encodable {
    var username: String
    var fullName: String
    var email: String?
    var mobile: String?
    var phone: String?
    var role: String

    enum CodingKeys: String, CodingKey {
        case username, email, mobile, phone, role
        case fullName = "full_name"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(username, forKey: .username)
        try c.encode(fullName, forKey: .fullName)
        try c.encodeIfPresent(email, forKey: .email)
        try c.encodeIfPresent(mobile, forKey: .mobile)
        try c.encodeIfPresent(phone, forKey: .phone)
        try c.encode(role, forKey: .role)
    }
}

/// `POST .../users` response — the `SubUser` fields plus the freshly minted
/// invite link (`invite_url`), the channel it was dispatched on (null when none
/// could be sent), and when the link expires.
struct SubUserCreated: Decodable, Identifiable, Equatable {
    let id: String
    let subMerchantID: String
    let username: String
    let role: String
    let status: String
    let fullName: String
    let email: String?
    let mobile: String?
    let phone: String?
    let mfaEnabled: Bool
    let lastLoginAt: String?
    let createdAt: String
    let inviteURL: String
    let inviteSentToChannel: String?
    let inviteExpiresAt: String

    enum CodingKeys: String, CodingKey {
        case id, username, role, status, email, mobile, phone
        case subMerchantID = "sub_merchant_id"
        case fullName = "full_name"
        case mfaEnabled = "mfa_enabled"
        case lastLoginAt = "last_login_at"
        case createdAt = "created_at"
        case inviteURL = "invite_url"
        case inviteSentToChannel = "invite_sent_to_channel"
        case inviteExpiresAt = "invite_expires_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        subMerchantID = (try? c.decode(String.self, forKey: .subMerchantID)) ?? ""
        username = try c.decode(String.self, forKey: .username)
        role = (try? c.decode(String.self, forKey: .role)) ?? "sub_operator"
        status = (try? c.decode(String.self, forKey: .status)) ?? "active"
        fullName = (try? c.decode(String.self, forKey: .fullName)) ?? ""
        email = try? c.decodeIfPresent(String.self, forKey: .email)
        mobile = try? c.decodeIfPresent(String.self, forKey: .mobile)
        phone = try? c.decodeIfPresent(String.self, forKey: .phone)
        mfaEnabled = (try? c.decode(Bool.self, forKey: .mfaEnabled)) ?? false
        lastLoginAt = try? c.decodeIfPresent(String.self, forKey: .lastLoginAt)
        createdAt = (try? c.decode(String.self, forKey: .createdAt)) ?? ""
        inviteURL = (try? c.decode(String.self, forKey: .inviteURL)) ?? ""
        inviteSentToChannel = try? c.decodeIfPresent(String.self, forKey: .inviteSentToChannel)
        inviteExpiresAt = (try? c.decode(String.self, forKey: .inviteExpiresAt)) ?? ""
    }

    /// The new sub-user as a plain `SubUser` (for splicing into the list).
    var asSubUser: SubUser {
        SubUser(id: id, subMerchantID: subMerchantID, username: username, role: role, status: status,
                fullName: fullName, email: email, mobile: mobile, phone: phone,
                mfaEnabled: mfaEnabled, lastLoginAt: lastLoginAt, createdAt: createdAt)
    }
}

struct SubUserPatch: Encodable {
    var fullName: String?
    var email: String?
    var mobile: String?
    var phone: String?
    var role: String?
    var status: String?

    enum CodingKeys: String, CodingKey {
        case email, mobile, phone, role, status
        case fullName = "full_name"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(fullName, forKey: .fullName)
        try c.encodeIfPresent(email, forKey: .email)
        try c.encodeIfPresent(mobile, forKey: .mobile)
        try c.encodeIfPresent(phone, forKey: .phone)
        try c.encodeIfPresent(role, forKey: .role)
        try c.encodeIfPresent(status, forKey: .status)
    }

    var isEmpty: Bool {
        fullName == nil && email == nil && mobile == nil && phone == nil && role == nil && status == nil
    }
}

struct ReissueInvite: Decodable, Equatable {
    let sentToChannel: String?
    let inviteURL: String
    let expiresAt: String

    enum CodingKeys: String, CodingKey {
        case sentToChannel = "sent_to_channel"
        case inviteURL = "invite_url"
        case expiresAt = "expires_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sentToChannel = try? c.decodeIfPresent(String.self, forKey: .sentToChannel)
        inviteURL = (try? c.decode(String.self, forKey: .inviteURL)) ?? ""
        expiresAt = (try? c.decode(String.self, forKey: .expiresAt)) ?? ""
    }
}
