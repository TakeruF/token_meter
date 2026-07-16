import Foundation
import XCTest
@testable import TokenMeterCore

final class ClaudeCredentialJSONTests: XCTestCase {
    func testDecodesNormalKeychainJSON() throws {
        let data = Data(#"{"claudeAiOauth":{"accessToken":"secret-token","refreshToken":"refresh","expiresAt":123}}"#.utf8)
        XCTAssertEqual(try ClaudeCredentialJSONDecoder.accessToken(from: data), "secret-token")
    }

    func testFindsOAuthSectionWhenContainerShapeChanges() throws {
        let data = Data(#"{"credentials":{"items":[{"claudeAiOauth":{"accessToken":"nested-token"}}]}}"#.utf8)
        XCTAssertEqual(try ClaudeCredentialJSONDecoder.accessToken(from: data), "nested-token")
    }

    func testMissingOAuthSectionIsExplicit() {
        XCTAssertThrowsError(try ClaudeCredentialJSONDecoder.accessToken(from: Data(#"{"other":{}}"#.utf8))) {
            XCTAssertEqual($0 as? ClaudeCredentialError, .oauthSectionMissing)
        }
    }

    func testMissingAccessTokenIsExplicit() {
        XCTAssertThrowsError(try ClaudeCredentialJSONDecoder.accessToken(from: Data(#"{"claudeAiOauth":{"refreshToken":"r"}}"#.utf8))) {
            XCTAssertEqual($0 as? ClaudeCredentialError, .accessTokenMissing)
        }
    }

    func testDecodesExpiresAtAsEpochMilliseconds() throws {
        let data = Data(#"{"claudeAiOauth":{"accessToken":"t","expiresAt":1700000000000}}"#.utf8)
        let credential = try ClaudeCredentialJSONDecoder.credential(from: data)
        XCTAssertEqual(credential.expiresAt, Date(timeIntervalSince1970: 1_700_000_000))
    }

    func testMissingExpiresAtLeavesExpiryUnknown() throws {
        let data = Data(#"{"claudeAiOauth":{"accessToken":"t"}}"#.utf8)
        let credential = try ClaudeCredentialJSONDecoder.credential(from: data)
        XCTAssertNil(credential.expiresAt)
        XCTAssertFalse(credential.isExpired(now: Date()))
    }
}

final class ClaudeUsageResponseTests: XCTestCase {
    func testDecodesAllUsageWindowsAndDates() throws {
        let response = try decode(#"""
        {
          "five_hour":{"utilization":35,"resets_at":"2026-07-15T08:00:00Z"},
          "seven_day":{"utilization":17,"resets_at":"2026-07-20T00:00:00Z"},
          "seven_day_sonnet":{"utilization":10,"resets_at":"2026-07-20T00:00:00.123Z"},
          "future_field":{"anything":true}
        }
        """#)

        XCTAssertEqual(response.fiveHour?.utilization, 35)
        XCTAssertNotNil(response.fiveHour?.resetsAt)
        XCTAssertEqual(try XCTUnwrap(response.sevenDay?.asUsageWindow(windowMinutes: 10)?.remainingRatio), 0.83, accuracy: 0.0001)
        XCTAssertNotNil(response.sevenDaySonnet?.resetsAt)
    }

    func testMissingOptionalWindowsAreAllowed() throws {
        let response = try decode(#"{"five_hour":{"utilization":12.5}}"#)
        XCTAssertEqual(response.fiveHour?.utilization, 12.5)
        XCTAssertNil(response.sevenDay)
        XCTAssertNil(response.sevenDaySonnet)
        XCTAssertNil(response.fiveHour?.resetsAt)
    }

    func testUtilizationIsClampedForNegativeDecimalAndOver100Values() throws {
        let response = try decode(#"""
        {
          "five_hour":{"utilization":-4.5},
          "seven_day":{"utilization":101.25},
          "seven_day_sonnet":{"utilization":33.3}
        }
        """#)

        XCTAssertEqual(response.fiveHour?.asUsageWindow(windowMinutes: 300)?.remainingRatio, 1)
        XCTAssertEqual(response.sevenDay?.asUsageWindow(windowMinutes: 10_080)?.remainingRatio, 0)
        XCTAssertEqual(try XCTUnwrap(response.sevenDaySonnet?.asUsageWindow(windowMinutes: 10_080)?.remainingRatio), 0.667, accuracy: 0.0001)
    }

    func testInvalidDateDoesNotFailTheWholeResponse() throws {
        let response = try decode(#"{"five_hour":{"utilization":35,"resets_at":"not-a-date"}}"#)
        XCTAssertEqual(response.fiveHour?.utilization, 35)
        XCTAssertNil(response.fiveHour?.resetsAt)
    }

    private func decode(_ json: String) throws -> ClaudeUsageResponse {
        try JSONDecoder().decode(ClaudeUsageResponse.self, from: Data(json.utf8))
    }
}

final class ClaudeUsageAPIClientTests: XCTestCase {
    func testRequestUsesFixedEndpointAndRequiredHeaders() async throws {
        let session = MockURLSession(result: .success((
            Data(#"{"five_hour":{"utilization":35}}"#.utf8),
            httpResponse(status: 200)
        )))
        let client = ClaudeUsageAPIClient(session: session, timeout: 7)

        _ = try await client.fetchUsage(accessToken: "test-access-token")
        let request = try XCTUnwrap(session.lastRequest)
        XCTAssertEqual(request.url, ClaudeUsageAPIClient.endpoint)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-access-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-beta"), "oauth-2025-04-20")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.timeoutInterval, 7)
    }

    func test401IsClassified() async { await assertStatus(401, expected: .unauthorized) }
    func test403IsClassified() async { await assertStatus(403, expected: .forbidden) }
    func test429IsClassified() async { await assertStatus(429, expected: .rateLimited(retryAfter: nil)) }
    func test500IsClassified() async { await assertStatus(500, expected: .serverError(status: 500)) }

    func testNetworkFailureIsClassified() async {
        let session = MockURLSession(result: .failure(URLError(.notConnectedToInternet)))
        let client = ClaudeUsageAPIClient(session: session)
        do {
            _ = try await client.fetchUsage(accessToken: "token")
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? ClaudeUsageError, .networkUnavailable)
        }
    }

    func testEmptySuccessPayloadIsTreatedAsFormatChange() async {
        let session = MockURLSession(result: .success((Data("{}".utf8), httpResponse(status: 200))))
        let client = ClaudeUsageAPIClient(session: session)
        do {
            _ = try await client.fetchUsage(accessToken: "token")
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? ClaudeUsageError, .invalidResponse)
        }
    }

    private func assertStatus(_ status: Int, expected: ClaudeUsageError) async {
        let body = Data(#"{"error":{"type":"api_error","message":"safe"}}"#.utf8)
        let session = MockURLSession(result: .success((body, httpResponse(status: status))))
        let client = ClaudeUsageAPIClient(session: session)
        do {
            _ = try await client.fetchUsage(accessToken: "token")
            XCTFail("expected status \(status) to fail")
        } catch {
            XCTAssertEqual(error as? ClaudeUsageError, expected)
        }
    }
}

final class ClaudeUsageServiceTests: XCTestCase {
    func testFailureFallsBackToLastSuccessfulMemoryCache() async {
        let usage = ClaudeUsageResponse(fiveHour: .init(utilization: 20, resetsAt: nil))
        let client = MockClaudeClient(results: [.success(usage), .failure(.networkUnavailable)])
        let service = ClaudeUsageService(
            credentials: StubCredentials(result: .success("token")),
            client: client,
            refreshInterval: 300,
            now: { Date(timeIntervalSince1970: 1000) }
        )

        let first = await service.usage(forceRefresh: true)
        let fallback = await service.usage(forceRefresh: true)

        XCTAssertEqual(first.usage, usage)
        XCTAssertFalse(first.isCached)
        XCTAssertEqual(fallback.usage, usage)
        XCTAssertTrue(fallback.isCached)
        XCTAssertEqual(fallback.error, .networkUnavailable)
    }

    func testFreshCacheAvoidsAnotherRequest() async {
        let usage = ClaudeUsageResponse(fiveHour: .init(utilization: 20, resetsAt: nil))
        let client = MockClaudeClient(results: [.success(usage)])
        let service = ClaudeUsageService(
            credentials: StubCredentials(result: .success("token")),
            client: client,
            refreshInterval: 300,
            now: { Date(timeIntervalSince1970: 1000) }
        )

        _ = await service.usage(forceRefresh: false)
        let second = await service.usage(forceRefresh: false)

        XCTAssertTrue(second.isCached)
        let callCount = await client.callCount
        XCTAssertEqual(callCount, 1)
    }

    func testConcurrentRefreshesAreCoalesced() async {
        let usage = ClaudeUsageResponse(fiveHour: .init(utilization: 20, resetsAt: nil))
        let client = MockClaudeClient(results: [.success(usage)], delay: .milliseconds(100))
        let service = ClaudeUsageService(
            credentials: StubCredentials(result: .success("token")),
            client: client
        )

        async let a = service.usage(forceRefresh: true)
        async let b = service.usage(forceRefresh: true)
        async let c = service.usage(forceRefresh: true)
        _ = await [a, b, c]

        let callCount = await client.callCount
        XCTAssertEqual(callCount, 1)
    }

    func testExpiredTokenFailsFastWithoutNetwork() async {
        let now = Date(timeIntervalSince1970: 2000)
        let client = MockClaudeClient(results: [])
        let service = ClaudeUsageService(
            credentials: StubCredentials(
                result: .success("token"),
                expiresAt: now.addingTimeInterval(-3600)  // expired an hour ago
            ),
            client: client,
            now: { now }
        )

        let result = await service.usage(forceRefresh: true)

        XCTAssertNil(result.usage)
        XCTAssertEqual(result.error, .sessionExpired)
        let callCount = await client.callCount
        XCTAssertEqual(callCount, 0)  // never spends a request on a dead token
    }

    func testValidExpiryStillCallsNetwork() async {
        let now = Date(timeIntervalSince1970: 2000)
        let usage = ClaudeUsageResponse(fiveHour: .init(utilization: 10, resetsAt: nil))
        let client = MockClaudeClient(results: [.success(usage)])
        let service = ClaudeUsageService(
            credentials: StubCredentials(
                result: .success("token"),
                expiresAt: now.addingTimeInterval(3600)  // valid for another hour
            ),
            client: client,
            now: { now }
        )

        let result = await service.usage(forceRefresh: true)

        XCTAssertEqual(result.usage, usage)
        XCTAssertNil(result.error)
        let callCount = await client.callCount
        XCTAssertEqual(callCount, 1)
    }

    func testMissingCredentialDoesNotCallNetwork() async {
        let client = MockClaudeClient(results: [])
        let service = ClaudeUsageService(
            credentials: StubCredentials(result: .failure(.accessTokenMissing)),
            client: client
        )

        let result = await service.usage(forceRefresh: true)

        XCTAssertNil(result.usage)
        XCTAssertEqual(result.error, .credentialsNotFound)
        let callCount = await client.callCount
        XCTAssertEqual(callCount, 0)
    }
}

final class ClaudeOAuthProviderIntegrationTests: XCTestCase {
    func testOAuthFailureWithoutLocalLogsReturnsUnavailableSnapshotInsteadOfThrowing() async throws {
        let provider = ClaudeCodeUsageProvider(
            projectsRoot: makeTempDirectory().appendingPathComponent("missing"),
            store: try makeTempStore(),
            quotaService: StubQuotaService(result: .init(
                usage: nil,
                fetchedAt: nil,
                isCached: false,
                error: .networkUnavailable
            ))
        )
        await provider.setOAuthUsageEnabled(true)

        let snapshot = try await provider.fetchCurrentUsage(forceRefresh: true)

        XCTAssertTrue(snapshot.quotaIntegrationEnabled)
        XCTAssertFalse(snapshot.hasQuotaInformation)
        XCTAssertEqual(snapshot.quotaError, .networkUnavailable)
    }

    func testWidgetSnapshotKeepsQuotaValuesButContainsNoCredentialField() throws {
        let store = SharedSnapshotStore(containerURL: makeTempDirectory())
        let timestamp = Date(timeIntervalSince1970: 1_784_000_000)
        let snapshot = SharedSnapshot(
            updatedAt: timestamp,
            claudeCode: .init(
                displayName: "Claude Code",
                remainingRatio: 0.65,
                hasQuotaInformation: true,
                fiveHourQuota: .init(usedRatio: 0.35, remainingRatio: 0.65, resetsAt: timestamp, windowMinutes: 300),
                quotaUpdatedAt: timestamp,
                quotaIsCached: false
            )
        )

        try store.write(snapshot)
        let data = try Data(contentsOf: store.fileURL)
        let text = String(decoding: data, as: UTF8.self)

        XCTAssertEqual(try store.read(), snapshot)
        XCTAssertFalse(text.contains("accessToken"))
        XCTAssertFalse(text.contains("Authorization"))
    }
}

private struct StubCredentials: ClaudeCredentialProviding {
    let result: Result<String, ClaudeCredentialError>
    var expiresAt: Date?
    func accessToken() throws -> String { try result.get() }
    func credential() throws -> ClaudeCredential {
        ClaudeCredential(accessToken: try result.get(), expiresAt: expiresAt)
    }
}

private struct StubQuotaService: ClaudeUsageServicing {
    let result: ClaudeUsageFetchResult
    func usage(forceRefresh: Bool) async -> ClaudeUsageFetchResult { result }
}

private actor MockClaudeClient: ClaudeUsageAPIClientProtocol {
    private var results: [Result<ClaudeUsageResponse, ClaudeUsageError>]
    private let delay: Duration?
    private(set) var callCount = 0

    init(results: [Result<ClaudeUsageResponse, ClaudeUsageError>], delay: Duration? = nil) {
        self.results = results
        self.delay = delay
    }

    func fetchUsage(accessToken: String) async throws -> ClaudeUsageResponse {
        callCount += 1
        if let delay { try await Task.sleep(for: delay) }
        guard !results.isEmpty else { throw ClaudeUsageError.requestFailed }
        return try results.removeFirst().get()
    }
}

private final class MockURLSession: URLSessionProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private let result: Result<(Data, URLResponse), Error>
    private var capturedRequest: URLRequest?

    init(result: Result<(Data, URLResponse), Error>) {
        self.result = result
    }

    var lastRequest: URLRequest? {
        lock.withLock { capturedRequest }
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lock.withLock { capturedRequest = request }
        return try result.get()
    }
}

private func httpResponse(status: Int) -> HTTPURLResponse {
    HTTPURLResponse(
        url: ClaudeUsageAPIClient.endpoint,
        statusCode: status,
        httpVersion: "HTTP/1.1",
        headerFields: nil
    )!
}
