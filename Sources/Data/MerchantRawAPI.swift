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
///
/// The decoders mirror the Pydantic response models 1:1 (see
/// `app/api/merchant/payments.py` and `app/api/merchant/settlements.py`).
///
/// TODO(payhub): drop this once SDK 1.2 ships `payments`, `settlements`,
/// `devices`, and the sub-breakdown.
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
