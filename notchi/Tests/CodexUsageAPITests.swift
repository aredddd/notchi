import XCTest
@testable import notchi

final class CodexUsageAPITests: XCTestCase {
    private func makeJWT(exp: Double) -> String {
        let payload = try! JSONSerialization.data(withJSONObject: ["exp": exp])
        let encoded = payload.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "header.\(encoded).signature"
    }

    func testAuthLoadReadsAccessTokenAndAccountId() throws {
        let data = Data("""
        { "tokens": { "access_token": "tok-123", "account_id": "acc-9", "refresh_token": "r" } }
        """.utf8)

        let auth = try XCTUnwrap(CodexAPIAuth.load(from: data))

        XCTAssertEqual(auth.accessToken, "tok-123")
        XCTAssertEqual(auth.accountId, "acc-9")
    }

    func testAuthLoadReturnsNilWhenAccessTokenMissing() {
        let data = Data(#"{ "tokens": { "account_id": "acc-9" } }"#.utf8)
        XCTAssertNil(CodexAPIAuth.load(from: data))
    }

    func testAccessTokenExpiryParsesJWTExp() throws {
        let token = makeJWT(exp: 1_777_000_000)
        let expiry = try XCTUnwrap(CodexUsageAPI.accessTokenExpiry(token))
        XCTAssertEqual(expiry.timeIntervalSince1970, 1_777_000_000, accuracy: 0.001)
    }

    func testIsAccessTokenExpiredTrueForPastExpiry() {
        let token = makeJWT(exp: 1_000)
        XCTAssertTrue(CodexUsageAPI.isAccessTokenExpired(token, now: Date(timeIntervalSince1970: 2_000)))
    }

    func testIsAccessTokenExpiredFalseForFutureExpiry() {
        let token = makeJWT(exp: 9_000)
        XCTAssertFalse(CodexUsageAPI.isAccessTokenExpired(token, now: Date(timeIntervalSince1970: 2_000)))
    }

    func testUnparseableTokenIsTreatedAsUsable() {
        XCTAssertFalse(CodexUsageAPI.isAccessTokenExpired("not-a-jwt", now: Date()))
    }

    func testRequestCarriesBearerTokenAndAccountHeader() {
        let request = CodexUsageAPI.makeRequest(auth: CodexAPIAuth(accessToken: "tok-123", accountId: "acc-9"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tok-123")
        XCTAssertEqual(request.value(forHTTPHeaderField: "ChatGPT-Account-Id"), "acc-9")
        XCTAssertEqual(request.url, CodexUsageAPI.usageURL)
    }

    func testUsageParsesReviewsWindowAndCreditsBalance() throws {
        let data = Data("""
        {
          "code_review_rate_limit": { "primary_window": { "used_percent": 42.0, "reset_at": 1777621726 } },
          "credits": { "balance": 310 }
        }
        """.utf8)
        let response = try JSONDecoder().decode(CodexUsageAPIResponse.self, from: data)

        let usage = CodexUsageAPI.usage(from: response, now: Date(timeIntervalSince1970: 1_000))

        XCTAssertEqual(usage.reviews?.usagePercentage, 42)
        let reviewReset = try XCTUnwrap(usage.reviews?.resetDate)
        XCTAssertEqual(reviewReset.timeIntervalSince1970, 1_777_621_726, accuracy: 0.001)
        XCTAssertEqual(usage.creditsBalance, 310)
    }

    func testUsageUsesResetAfterSecondsWhenAbsoluteResetMissing() throws {
        let data = Data("""
        { "code_review_rate_limit": { "primary_window": { "used_percent": 10.0, "reset_after_seconds": 3600 } } }
        """.utf8)
        let response = try JSONDecoder().decode(CodexUsageAPIResponse.self, from: data)

        let usage = CodexUsageAPI.usage(from: response, now: Date(timeIntervalSince1970: 1_000))

        let reviewReset = try XCTUnwrap(usage.reviews?.resetDate)
        XCTAssertEqual(reviewReset.timeIntervalSince1970, 4_600, accuracy: 0.001)
    }

    func testUsageParsesStringCreditsBalance() throws {
        let data = Data(#"{ "credits": { "has_credits": true, "balance": "1250" } }"#.utf8)
        let response = try JSONDecoder().decode(CodexUsageAPIResponse.self, from: data)

        XCTAssertEqual(CodexUsageAPI.usage(from: response, now: Date()).creditsBalance, 1250)
    }

    func testUsageParsesSessionAndWeeklyFromRateLimit() throws {
        let data = Data("""
        {
          "rate_limit": {
            "primary_window": { "used_percent": 27.0, "reset_at": 1777103326 },
            "secondary_window": { "used_percent": 9.0, "reset_at": 1777621726 }
          }
        }
        """.utf8)
        let response = try JSONDecoder().decode(CodexUsageAPIResponse.self, from: data)

        let usage = CodexUsageAPI.usage(from: response, now: Date(timeIntervalSince1970: 1_000))

        XCTAssertEqual(usage.session?.usagePercentage, 27)
        XCTAssertEqual(usage.weekly?.usagePercentage, 9)
    }

    @MainActor
    func testRefreshFromAPIPopulatesSessionWeeklyAndCredits() async throws {
        let service = CodexUsageService(dependencies: CodexUsageServiceDependencies(
            resolveUsage: { _ in nil },
            fetchAPIUsage: {
                CodexAPIUsage(
                    session: QuotaPeriod(utilization: 40, resetDate: Date(timeIntervalSince1970: 9_999_999_999)),
                    weekly: QuotaPeriod(utilization: 12, resetDate: Date(timeIntervalSince1970: 9_999_999_999)),
                    reviews: nil,
                    creditsBalance: 100
                )
            },
            now: { Date(timeIntervalSince1970: 1_000) }
        ))

        await service.refreshFromAPI()

        XCTAssertEqual(service.currentUsage?.usagePercentage, 40)
        XCTAssertEqual(service.currentWeeklyUsage?.usagePercentage, 12)
        let credits = try XCTUnwrap(service.currentExtraCreditsUSD)
        XCTAssertEqual(credits, 100 * CodexUsageAPI.creditUSDRate, accuracy: 0.0001)
    }

    func testUsageTreatsHasCreditsFalseAsZeroBalance() throws {
        let data = Data(#"{ "credits": { "has_credits": false } }"#.utf8)
        let response = try JSONDecoder().decode(CodexUsageAPIResponse.self, from: data)

        XCTAssertEqual(CodexUsageAPI.usage(from: response, now: Date()).creditsBalance, 0)
    }

    func testUsageLeavesReviewsAndCreditsNilWhenAbsent() throws {
        let response = try JSONDecoder().decode(CodexUsageAPIResponse.self, from: Data("{}".utf8))
        let usage = CodexUsageAPI.usage(from: response, now: Date())
        XCTAssertNil(usage.reviews)
        XCTAssertNil(usage.creditsBalance)
    }

    @MainActor
    func testRefreshPublishesReviewsAndCreditsFromAPI() async throws {
        let service = CodexUsageService(dependencies: CodexUsageServiceDependencies(
            resolveUsage: { _ in
                CodexUsageSnapshot(
                    usage: QuotaPeriod(utilization: 5, resetDate: Date(timeIntervalSince1970: 9_999_999_999)),
                    weeklyUsage: nil,
                    observedAt: Date(timeIntervalSince1970: 9_000_000_000)
                )
            },
            fetchAPIUsage: {
                CodexAPIUsage(
                    reviews: QuotaPeriod(utilization: 42, resetDate: Date(timeIntervalSince1970: 9_999_999_999)),
                    creditsBalance: 310
                )
            },
            now: { Date(timeIntervalSince1970: 9_000_000_000) }
        ))

        await service.refresh(transcriptPaths: ["/tmp/rollout.jsonl"])

        XCTAssertEqual(service.currentReviewsUsage?.usagePercentage, 42)
        let credits = try XCTUnwrap(service.currentExtraCreditsUSD)
        XCTAssertEqual(credits, 310 * CodexUsageAPI.creditUSDRate, accuracy: 0.0001)
    }

    @MainActor
    func testTransientAPIFailureRetainsLastGoodValues() async throws {
        let state = MutableFetchState(now: Date(timeIntervalSince1970: 1_000))
        state.result = CodexAPIUsage(
            reviews: QuotaPeriod(utilization: 30, resetDate: Date(timeIntervalSince1970: 9_999_999_999)),
            creditsBalance: 100
        )
        let service = CodexUsageService(dependencies: CodexUsageServiceDependencies(
            resolveUsage: { _ in
                CodexUsageSnapshot(
                    usage: QuotaPeriod(utilization: 5, resetDate: Date(timeIntervalSince1970: 9_999_999_999)),
                    weeklyUsage: nil,
                    observedAt: Date(timeIntervalSince1970: 1_000)
                )
            },
            fetchAPIUsage: { state.result },
            now: { state.now }
        ))

        await service.refresh(transcriptPaths: ["/tmp/rollout.jsonl"])
        let firstCredits = try XCTUnwrap(service.currentExtraCreditsUSD)
        XCTAssertEqual(firstCredits, 100 * CodexUsageAPI.creditUSDRate, accuracy: 0.0001)

        state.now = Date(timeIntervalSince1970: 1_000 + 120)
        state.result = nil
        await service.refresh(transcriptPaths: ["/tmp/rollout.jsonl"])

        XCTAssertEqual(service.currentReviewsUsage?.usagePercentage, 30)
        let retainedCredits = try XCTUnwrap(service.currentExtraCreditsUSD)
        XCTAssertEqual(retainedCredits, 100 * CodexUsageAPI.creditUSDRate, accuracy: 0.0001)
    }

    @MainActor
    func testIdleRefreshAppliesCachedSessionWeeklyWhenThrottled() async {
        let counter = CallCounter()
        let now = Date(timeIntervalSince1970: 1_000)
        let service = CodexUsageService(dependencies: CodexUsageServiceDependencies(
            resolveUsage: { _ in
                CodexUsageSnapshot(
                    usage: QuotaPeriod(utilization: 5, resetDate: Date(timeIntervalSince1970: 9_999_999_999)),
                    weeklyUsage: nil,
                    observedAt: now
                )
            },
            fetchAPIUsage: {
                await counter.bump()
                return CodexAPIUsage(
                    session: QuotaPeriod(utilization: 73, resetDate: Date(timeIntervalSince1970: 9_999_999_999)),
                    weekly: QuotaPeriod(utilization: 8, resetDate: Date(timeIntervalSince1970: 9_999_999_999)),
                    reviews: nil,
                    creditsBalance: nil
                )
            },
            now: { now }
        ))

        // Active refresh: file drives session (5%), API fetched once (reviews/credits only).
        await service.refresh(transcriptPaths: ["/tmp/rollout.jsonl"])
        XCTAssertEqual(service.currentUsage?.usagePercentage, 5)

        // Session ends within the throttle window: cached API session/weekly are applied without a new fetch.
        await service.refreshFromAPI()

        let fetchCount = await counter.count
        XCTAssertEqual(fetchCount, 1)
        XCTAssertEqual(service.currentUsage?.usagePercentage, 73)
        XCTAssertEqual(service.currentWeeklyUsage?.usagePercentage, 8)
    }

    @MainActor
    func testRapidRefreshesThrottleTheNetworkedAPIFetch() async {
        let counter = CallCounter()
        let service = CodexUsageService(dependencies: CodexUsageServiceDependencies(
            resolveUsage: { _ in
                CodexUsageSnapshot(
                    usage: QuotaPeriod(utilization: 5, resetDate: Date(timeIntervalSince1970: 9_999_999_999)),
                    weeklyUsage: nil,
                    observedAt: Date(timeIntervalSince1970: 9_000_000_000)
                )
            },
            fetchAPIUsage: {
                await counter.bump()
                return CodexAPIUsage(reviews: nil, creditsBalance: nil)
            },
            now: { Date(timeIntervalSince1970: 9_000_000_000) }
        ))

        await service.refresh(transcriptPaths: ["/tmp/rollout.jsonl"])
        await service.refresh(transcriptPaths: ["/tmp/rollout.jsonl"])

        let count = await counter.count
        XCTAssertEqual(count, 1)
    }
}

private actor CallCounter {
    private(set) var count = 0
    func bump() { count += 1 }
}

private final class MutableFetchState: @unchecked Sendable {
    var now: Date
    var result: CodexAPIUsage?
    init(now: Date) { self.now = now }
}
