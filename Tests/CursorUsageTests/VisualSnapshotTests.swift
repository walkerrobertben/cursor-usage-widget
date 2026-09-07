import XCTest
@testable import CursorUsageCore

final class VisualSnapshotTests: XCTestCase {
    func testUnauthenticated() throws {
        try assertPNGSnapshot(
            name: "unauthenticated",
            MenuPresentation.make(
                from: UsageDisplayState(
                    isAuthenticated: false,
                    authErrorMessage: MenuPresentation.authFallbackMessage
                ),
                calendar: TestCalendar.snapshot
            )
        )
    }

    func testLoading() throws {
        try assertPNGSnapshot(
            name: "loading",
            MenuPresentation.make(from: UsageDisplayState(), calendar: TestCalendar.snapshot)
        )
    }

    func testOnDemandDisabled() async throws {
        try assertPNGSnapshot(name: "ondemand-disabled", try await ScenarioLoad.presentation(.disabled).0)
    }

    func testOnDemandLimited() async throws {
        try assertPNGSnapshot(name: "ondemand-limited", try await ScenarioLoad.presentation(.limited).0)
    }

    func testOnDemandUnlimited() async throws {
        try assertPNGSnapshot(name: "ondemand-unlimited", try await ScenarioLoad.presentation(.unlimited).0)
    }

    func testTeamEnterprise() async throws {
        try assertPNGSnapshot(name: "ondemand-team-enterprise", try await ScenarioLoad.presentation(.teamEnterprise).0)
    }

    func testOnDemandLimitedHigh() async throws {
        try assertPNGSnapshot(name: "ondemand-limited-high", try await ScenarioLoad.presentation(.limitedHigh).0)
    }

    func testMetersEmpty() async throws {
        try assertPNGSnapshot(name: "meters-empty", try await ScenarioLoad.presentation(.emptyMeters).0)
    }

    func testMetersFull() async throws {
        try assertPNGSnapshot(name: "meters-full", try await ScenarioLoad.presentation(.fullMeters).0)
    }

    func testCursorOnlyEmpty() async throws {
        try assertPNGSnapshot(name: "menubar-cursor-only-empty", try await ScenarioLoad.presentation(.cursorOnlyEmpty).0)
    }

    func testCursorOnlyFull() async throws {
        try assertPNGSnapshot(name: "menubar-cursor-only-full", try await ScenarioLoad.presentation(.cursorOnlyFull).0)
    }
}
