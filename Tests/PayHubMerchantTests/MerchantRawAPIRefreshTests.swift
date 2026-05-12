import XCTest
import Payhub
@testable import PayHubMerchant

/// The transparent "401 → refresh → retry once" the raw shim does so an
/// access-token expiry mid-session doesn't bounce the user to login while the
/// refresh token is still good (`MerchantRawAPI.send` + `MerchantRepository.refreshAccessToken`).
final class MerchantRawAPIRefreshTests: XCTestCase {

    private let baseURL = URL(string: "https://app.payhub.test")!

    override func setUp() { super.setUp(); StubURLProtocol.reset() }
    override func tearDown() { StubURLProtocol.reset(); super.tearDown() }

    /// Spies the `tokenRefresh` closure: counts calls, hands back `nextToken`.
    private actor RefreshSpy {
        private(set) var calls = 0
        private let nextToken: String?
        init(nextToken: String?) { self.nextToken = nextToken }
        func refresh() -> String? { calls += 1; return nextToken }
    }

    private func makeAPI(initialToken: String?, spy: RefreshSpy) -> MerchantRawAPI {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [StubURLProtocol.self]
        return MerchantRawAPI(
            baseURL: baseURL,
            accessTokenProvider: { initialToken },
            tokenRefresh: { await spy.refresh() },
            session: URLSession(configuration: cfg))
    }

    private static let onePaymentJSON = """
      [{
        "id": "11111111-2222-3333-4444-555555555555",
        "psp_code": "moamalat", "psp_ref": "abc-123",
        "merchant_order_ref": "shop-987", "amount_minor": 25500, "currency": "LYD",
        "status": "succeeded",
        "created_at": "2026-05-10T12:34:56Z", "updated_at": "2026-05-10T12:35:01Z"
      }]
    """

    func testOn401RefreshesOnceAndRetriesWithTheNewBearer() async throws {
        var hits = 0
        StubURLProtocol.stubs.append(.init(
            match: { $0.url?.path == "/merchant/payments" },
            response: { _ in
                hits += 1
                return hits == 1 ? (401, #"{"error":{"code":"hub.merchant.bearer_expired","message":"token expired"}}"#)
                                 : (200, Self.onePaymentJSON)
            }))

        let spy = RefreshSpy(nextToken: "fresh-token")
        let rows = try await makeAPI(initialToken: "stale-token", spy: spy).listPayments()

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.pspCode, "moamalat")
        let refreshes = await spy.calls
        XCTAssertEqual(refreshes, 1)

        XCTAssertEqual(StubURLProtocol.recorded.count, 2)
        XCTAssertEqual(StubURLProtocol.recorded.first?.value(forHTTPHeaderField: "Authorization"), "Bearer stale-token")
        XCTAssertEqual(StubURLProtocol.recorded.last?.value(forHTTPHeaderField: "Authorization"), "Bearer fresh-token")
    }

    func testWhenRefreshYieldsNoTokenThe401Surfaces() async throws {
        StubURLProtocol.stubs.append(.init(
            match: { $0.url?.path == "/merchant/payments" },
            response: { _ in (401, #"{"error":{"code":"hub.merchant.bearer_expired","message":"token expired"}}"#) }))

        let spy = RefreshSpy(nextToken: nil)
        do {
            _ = try await makeAPI(initialToken: "stale-token", spy: spy).listPayments()
            XCTFail("expected a PayhubError")
        } catch let error as PayhubError {
            switch error {
            case .api(let kind, _, let status, _, _, _):
                XCTAssertEqual(status, 401)
                if case .authentication = kind {} else { XCTFail("expected .authentication, got \(kind)") }
            default:
                XCTFail("expected an .api error, got \(error)")
            }
        }
        let refreshes = await spy.calls
        XCTAssertEqual(refreshes, 1)              // it tried, once
        XCTAssertEqual(StubURLProtocol.recorded.count, 1)  // and did not retry the request
    }

    func testNonAuthFailureIsNotRetried() async throws {
        var hits = 0
        StubURLProtocol.stubs.append(.init(
            match: { $0.url?.path == "/merchant/payments" },
            response: { _ in hits += 1; return (500, #"{"error":{"code":"hub.internal","message":"boom"}}"#) }))

        let spy = RefreshSpy(nextToken: "fresh-token")
        do {
            _ = try await makeAPI(initialToken: "stale-token", spy: spy).listPayments()
            XCTFail("expected a PayhubError")
        } catch is PayhubError {
            // expected
        }
        XCTAssertEqual(hits, 1)
        let refreshes = await spy.calls
        XCTAssertEqual(refreshes, 0)
    }

    func testNoBearerMeansNoRefreshAttempt() async throws {
        StubURLProtocol.stubs.append(.init(
            match: { $0.url?.path == "/merchant/payments" },
            response: { _ in (401, #"{"error":{"code":"hub.merchant.bearer_required","message":"no token"}}"#) }))

        let spy = RefreshSpy(nextToken: "fresh-token")
        do {
            _ = try await makeAPI(initialToken: nil, spy: spy).listPayments()
            XCTFail("expected a PayhubError")
        } catch is PayhubError {
            // expected
        }
        let refreshes = await spy.calls
        XCTAssertEqual(refreshes, 0)             // no bearer was sent ⇒ nothing to refresh
    }
}
