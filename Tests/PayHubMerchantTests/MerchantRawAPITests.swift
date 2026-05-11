import XCTest
import Payhub
@testable import PayHubMerchant

/// URL-protocol-stub coverage for the raw HTTP endpoints we own locally
/// (everything outside the `payhub-swift` 1.1.0 SDK). Asserts request shape
/// (path + query + bearer header + body) and Codable round-trips against the
/// Pydantic response shapes in `app/api/merchant/payments.py` and
/// `app/api/merchant/settlements.py`. Pure offline — no MockWebServer-style
/// process, just a per-test `URLSessionConfiguration` with `StubURLProtocol`.
final class MerchantRawAPITests: XCTestCase {

    // The base URL is arbitrary — the stub matches by path regardless.
    private let baseURL = URL(string: "https://app.payhub.test")!
    private let bearer = "test-access-token"

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    private func makeAPI() -> MerchantRawAPI {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [StubURLProtocol.self]
        let token = bearer
        return MerchantRawAPI(baseURL: baseURL,
                              accessTokenProvider: { token },
                              session: URLSession(configuration: cfg))
    }

    // MARK: payments

    func testListPaymentsSerializesQueryAndDecodesRow() async throws {
        StubURLProtocol.stubs.append(.init(
            match: { $0.url?.path == "/merchant/payments" },
            response: { _ in (200, """
              [{
                "id": "11111111-2222-3333-4444-555555555555",
                "psp_code": "moamalat",
                "psp_ref": "abc-123",
                "merchant_order_ref": "shop-987",
                "amount_minor": 25500,
                "currency": "LYD",
                "status": "succeeded",
                "created_at": "2026-05-10T12:34:56Z",
                "updated_at": "2026-05-10T12:35:01Z"
              }]
            """) }))

        let rows = try await makeAPI().listPayments(
            psp: "moamalat", status: "succeeded", limit: 25, offset: 50)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.pspCode, "moamalat")
        XCTAssertEqual(rows.first?.amountMinor, 25_500)
        XCTAssertEqual(rows.first?.merchantOrderRef, "shop-987")

        let req = try XCTUnwrap(StubURLProtocol.recorded.last)
        XCTAssertEqual(req.httpMethod, "GET")
        let url = try XCTUnwrap(req.url)
        XCTAssertEqual(url.path, "/merchant/payments")
        let query = url.query ?? ""
        XCTAssertTrue(query.contains("psp=moamalat"), "got: \(query)")
        XCTAssertTrue(query.contains("status=succeeded"))
        XCTAssertTrue(query.contains("limit=25"))
        XCTAssertTrue(query.contains("offset=50"))
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer \(bearer)")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Accept"), "application/json")
    }

    func testListPaymentsCapsLimitAt200() async throws {
        StubURLProtocol.stubs.append(.init(
            match: { $0.url?.path == "/merchant/payments" },
            response: { _ in (200, "[]") }))
        _ = try await makeAPI().listPayments(limit: 9_999)
        let req = try XCTUnwrap(StubURLProtocol.recorded.last)
        XCTAssertTrue(req.url?.query?.contains("limit=200") == true, "got: \(req.url?.query ?? "nil")")
    }

    func testGetPaymentDecodesEventsAndMetadata() async throws {
        StubURLProtocol.stubs.append(.init(
            match: { $0.url?.path == "/merchant/payments/p-1" },
            response: { _ in (200, """
              {
                "id": "p-1", "psp_code": "sadad", "psp_ref": null,
                "merchant_order_ref": "order-1", "amount_minor": 5000,
                "currency": "LYD", "status": "succeeded",
                "created_at": "2026-05-10T12:00:00Z",
                "updated_at": "2026-05-10T12:05:00Z",
                "events": [
                  {"id": "e1", "event_type": "payment.initiated",
                   "prev_status": null, "new_status": "pending",
                   "source": "payhub", "created_at": "2026-05-10T12:00:00Z"},
                  {"id": "e2", "event_type": "payment.succeeded",
                   "prev_status": "pending", "new_status": "succeeded",
                   "source": "psp", "created_at": "2026-05-10T12:05:00Z"}
                ],
                "metadata": {
                  "pay_link_id": "link-42",
                  "customer_msisdn": "+218910000000"
                }
              }
            """) }))

        let detail = try await makeAPI().getPayment(id: "p-1")
        XCTAssertNil(detail.pspRef)
        XCTAssertEqual(detail.events.count, 2)
        XCTAssertEqual(detail.events.first?.eventType, "payment.initiated")
        XCTAssertEqual(detail.events.first?.source, "payhub")
        XCTAssertEqual(detail.events.last?.newStatus, "succeeded")
        XCTAssertEqual(detail.metadata["pay_link_id"]?.displayString, "link-42")
        XCTAssertEqual(detail.metadata["customer_msisdn"]?.displayString, "+218910000000")
    }

    // MARK: settlements

    func testListSettlementsDecodesCounters() async throws {
        StubURLProtocol.stubs.append(.init(
            match: { $0.url?.path == "/merchant/settlements" },
            response: { _ in (200, """
              [{
                "id": "f-1", "psp_code": "moamalat",
                "filename": "moamalat_2026-05-10.csv",
                "file_sha256": "deadbeef",
                "period_from": "2026-05-10T00:00:00Z",
                "period_to": "2026-05-10T23:59:59Z",
                "row_count": 120, "matched_count": 118, "mismatch_count": 2,
                "missing_in_hub_count": 0, "missing_in_psp_count": 0,
                "created_at": "2026-05-11T01:15:00Z"
              }]
            """) }))

        let files = try await makeAPI().listSettlements()
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files.first?.pspCode, "moamalat")
        XCTAssertEqual(files.first?.matchedCount, 118)
        XCTAssertEqual(files.first?.mismatchCount, 2)
    }

    func testGetSettlementHitsSingularPath() async throws {
        StubURLProtocol.stubs.append(.init(
            match: { $0.url?.path == "/merchant/settlements/f-1" },
            response: { _ in (200, """
              {
                "id": "f-1", "psp_code": "sadad",
                "filename": "sadad.csv", "file_sha256": "abc",
                "period_from": null, "period_to": null,
                "row_count": 0, "matched_count": 0, "mismatch_count": 0,
                "missing_in_hub_count": 0, "missing_in_psp_count": 0,
                "created_at": "2026-05-11T01:15:00Z"
              }
            """) }))
        let f = try await makeAPI().getSettlement(id: "f-1")
        XCTAssertEqual(f.pspCode, "sadad")
        XCTAssertNil(f.periodFrom)
    }

    func testListSettlementRowsPassesFilterAndDecodesDiff() async throws {
        StubURLProtocol.stubs.append(.init(
            match: { $0.url?.path == "/merchant/settlements/file-1/rows" },
            response: { _ in (200, """
              [{
                "id": "row-1",
                "merchant_order_ref": "order-99",
                "psp_ref": "psp-99",
                "psp_status": "settled",
                "amount_minor": 12500,
                "currency": "LYD",
                "payment_id": "pay-99",
                "status": "mismatch",
                "diff": { "amount_minor": { "hub": 12500, "psp": 12000 } },
                "created_at": "2026-05-11T01:00:00Z"
              }]
            """) }))

        let rows = try await makeAPI().listSettlementRows(
            fileID: "file-1", statusFilter: "mismatch", limit: 10, offset: 0)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.status, "mismatch")
        XCTAssertEqual(rows.first?.paymentId, "pay-99")
        XCTAssertEqual(rows.first?.diff["amount_minor"]?.string(forKey: "hub"), "12500")

        let req = try XCTUnwrap(StubURLProtocol.recorded.last)
        XCTAssertEqual(req.url?.path, "/merchant/settlements/file-1/rows")
        XCTAssertTrue(req.url?.query?.contains("status_filter=mismatch") == true)
        XCTAssertTrue(req.url?.query?.contains("limit=10") == true)
    }

    // MARK: errors

    func testHTTP401MapsToAuthenticationKind() async {
        StubURLProtocol.stubs.append(.init(
            match: { _ in true },
            response: { _ in (401, #"{"error":{"code":"hub.auth.expired","message":"expired"}}"#) }))
        do {
            _ = try await makeAPI().listPayments()
            XCTFail("expected failure")
        } catch let err as PayhubError {
            guard case .api(let kind, _, _, _, _, _) = err, case .authentication = kind else {
                return XCTFail("got \(err)")
            }
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testHTTP404MapsToNotFoundKind() async {
        StubURLProtocol.stubs.append(.init(
            match: { _ in true },
            response: { _ in (404, "") }))
        do {
            _ = try await makeAPI().getPayment(id: "missing")
            XCTFail("expected failure")
        } catch let err as PayhubError {
            guard case .api(let kind, _, _, _, _, _) = err, case .notFound = kind else {
                return XCTFail("got \(err)")
            }
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testHTTP500MapsToServerKind() async {
        StubURLProtocol.stubs.append(.init(
            match: { _ in true },
            response: { _ in (503, "") }))
        do {
            _ = try await makeAPI().listSettlements()
            XCTFail("expected failure")
        } catch let err as PayhubError {
            guard case .api(let kind, _, _, _, _, _) = err, case .server = kind else {
                return XCTFail("got \(err)")
            }
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    // MARK: devices

    func testRegisterDevicePostsTokenInJSONBody() async throws {
        StubURLProtocol.stubs.append(.init(
            match: { $0.url?.path == "/merchant/devices" },
            response: { _ in (204, "") }))
        try await makeAPI().registerDevice(apnsTokenHex: "deadbeef")

        let req = try XCTUnwrap(StubURLProtocol.recorded.last)
        XCTAssertEqual(req.httpMethod, "POST")
        let bodyData = try XCTUnwrap(req.bodyData)
        let body = String(decoding: bodyData, as: UTF8.self)
        XCTAssertTrue(body.contains("\"token\":\"deadbeef\""), "body: \(body)")
        XCTAssertTrue(body.contains("\"platform\":\"ios\""), "body: \(body)")
    }

    func testUnregisterDeviceDeletesWithTokenInBody() async throws {
        StubURLProtocol.stubs.append(.init(
            match: { $0.url?.path == "/merchant/devices" },
            response: { _ in (204, "") }))
        try await makeAPI().unregisterDevice(apnsTokenHex: "deadbeef")

        let req = try XCTUnwrap(StubURLProtocol.recorded.last)
        XCTAssertEqual(req.httpMethod, "DELETE")
        let bodyData = try XCTUnwrap(req.bodyData)
        let body = String(decoding: bodyData, as: UTF8.self)
        XCTAssertTrue(body.contains("\"token\":\"deadbeef\""), "body: \(body)")
    }

    // MARK: dashboard breakdown

    func testDashboardBySubDecodesBreakdown() async throws {
        StubURLProtocol.stubs.append(.init(
            match: { $0.url?.path == "/merchant/dashboard" },
            response: { _ in (200, """
              {
                "window_hours": 72,
                "sub_breakdown": [{
                  "sub_merchant_id": "sub-1", "code": "S1", "name": "Shop One",
                  "paid": 4, "volume_minor": 12500, "inflight": 1,
                  "active_pay_links": 2
                }]
              }
            """) }))
        let rows = try await makeAPI().dashboardBySub(windowHours: 72)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.name, "Shop One")
        XCTAssertEqual(rows.first?.paid, 4)
    }
}

// MARK: - StubURLProtocol

/// Tiny in-process URL protocol that pattern-matches each outgoing request and
/// returns a canned status + JSON body. Records the request body so tests can
/// assert what we sent (URLProtocol strips `httpBody` for streamed bodies — the
/// helper below decodes the `httpBodyStream` when needed).
final class StubURLProtocol: URLProtocol {

    struct Stub {
        let match: (URLRequest) -> Bool
        let response: (URLRequest) -> (status: Int, body: String)
    }

    // Plain `static var`s — Swift 5.9 doesn't require the
    // `nonisolated(unsafe)` modifier; the tests are serial so contention isn't
    // a worry here.
    static var stubs: [Stub] = []
    static var recorded: [URLRequest] = []

    static func reset() {
        stubs = []
        recorded = []
    }

    override class func canInit(with request: URLRequest) -> Bool {
        stubs.contains { $0.match(request) }
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.recorded.append(request)
        guard let stub = Self.stubs.first(where: { $0.match(request) }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let (status, body) = stub.response(request)
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://stub")!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private extension URLRequest {
    /// `URLProtocol` swaps `httpBody` for `httpBodyStream` once the request is in
    /// flight — this convenience drains the stream so tests can inspect the body.
    var bodyData: Data? {
        if let body = httpBody { return body }
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
