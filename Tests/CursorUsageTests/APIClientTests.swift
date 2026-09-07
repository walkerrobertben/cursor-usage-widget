import XCTest
@testable import CursorUsageCore

final class APIClientTests: XCTestCase {
    func testLimitedScenarioHitsDashboardEndpointsInOrder() async throws {
        let (state, store) = try await ScenarioLoad.state(.limited)

        XCTAssertTrue(state.isAuthenticated)
        XCTAssertNotNil(state.summary)
        XCTAssertNotNil(state.planInfo)
        XCTAssertNotNil(state.hardLimit)
        XCTAssertNotNil(state.aggregations)
        XCTAssertNotNil(state.sandUsage)

        XCTAssertEqual(
            store.recordedPaths,
            [
                CursorAPIEndpoint.usageSummary.rawValue,
                CursorAPIEndpoint.sandUsage.rawValue,
                CursorAPIEndpoint.planInfo.rawValue,
                CursorAPIEndpoint.hardLimit.rawValue,
                CursorAPIEndpoint.aggregatedUsage.rawValue,
                CursorAPIEndpoint.aggregatedUsage.rawValue,
            ]
        )

        XCTAssertEqual(store.recorded[0].method, "GET")
        XCTAssertNil(store.recorded[0].origin)

        for request in store.recorded.dropFirst() {
            XCTAssertEqual(request.method, "POST")
            XCTAssertEqual(request.origin, "https://cursor.com")
            XCTAssertEqual(request.contentType, "application/json")
        }

        let cookie = store.recorded[0].cookie ?? ""
        XCTAssertTrue(cookie.contains("WorkosCursorSessionToken="))
        XCTAssertTrue(cookie.contains(TestAuth.userId))
        XCTAssertTrue(cookie.contains(TestAuth.token))
    }

    func testUnauthorizedSummaryStopsFurtherCalls() async throws {
        let (state, store) = try await ScenarioLoad.state(.unauthorized)
        XCTAssertFalse(state.isAuthenticated)
        XCTAssertEqual(state.authErrorMessage, MenuPresentation.authFallbackMessage)
        XCTAssertEqual(store.recordedPaths, [CursorAPIEndpoint.usageSummary.rawValue])
    }

    func testDecodesLiveShapedOnDemandNullLimit() throws {
        let data = try FixtureFile.data("usage-summary-unlimited")
        let summary = try JSONDecoder().decode(UsageSummaryResponse.self, from: data)
        XCTAssertEqual(summary.individualUsage?.onDemand?.enabled, true)
        XCTAssertEqual(summary.individualUsage?.onDemand?.used, 1234)
        XCTAssertNil(summary.individualUsage?.onDemand?.limit)
    }

    func testDecodesHardLimitDollarsAndDisabledFlag() throws {
        let limited = try JSONDecoder().decode(
            HardLimitResponse.self,
            from: try FixtureFile.data("get-hard-limit-limited")
        )
        XCTAssertEqual(limited.noUsageBasedAllowed, false)
        XCTAssertEqual(limited.hardLimit, 50)

        let disabled = try JSONDecoder().decode(
            HardLimitResponse.self,
            from: try FixtureFile.data("get-hard-limit-disabled")
        )
        XCTAssertEqual(disabled.noUsageBasedAllowed, true)
    }
}
