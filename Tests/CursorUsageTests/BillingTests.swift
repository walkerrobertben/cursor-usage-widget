import XCTest
@testable import CursorUsageCore

final class BillingTests: XCTestCase {
    func testDisabledOnDemandShowsPlanOnlyBill() async throws {
        let (presentation, _, _) = try await ScenarioLoad.presentation(.disabled)
        XCTAssertEqual(presentation.text(matching: "header"), "Cursor Usage — Pro")
        XCTAssertEqual(presentation.text(matching: "billing"), "Total bill this cycle: $20.00")
        XCTAssertEqual(presentation.text(matching: "billingDetail"), "Pro $20.00 plan + $0.00 on-demand")
        XCTAssertEqual(presentation.text(matching: "onDemand"), "On-demand: Disabled")
        XCTAssertFalse(presentation.meters.contains { $0.role == "onDemandMeter" })
        XCTAssertFalse(presentation.menubar.segments.contains { $0.hasPrefix("$") })
        assertOnDemandComesBeforeTotalBill(presentation)
        assertNoWarningTextStyles(presentation)
    }

    func testLimitedOnDemandShowsUsageMeterAndPlanPlusSpend() async throws {
        let (presentation, _, _) = try await ScenarioLoad.presentation(.limited)
        XCTAssertEqual(presentation.text(matching: "billing"), "Total bill this cycle: $35.00")
        XCTAssertEqual(presentation.text(matching: "billingDetail"), "Pro $20.00 plan + $15.00 on-demand")

        let meter = try XCTUnwrap(presentation.meters.first { $0.role == "onDemandMeter" })
        XCTAssertEqual(meter.content.title, "On-demand — $15.00 of $50.00")
        XCTAssertEqual(meter.content.percentUsed, 30, accuracy: 0.01)
        XCTAssertEqual(meter.level, .green)
        XCTAssertTrue(meter.content.leftCaption.contains("30% used"))
        XCTAssertTrue(meter.content.rightCaption.contains("Resets"))
        XCTAssertTrue(presentation.menubar.segments.contains("$15.00"))
        assertOnDemandComesBeforeTotalBill(presentation)
        assertNoWarningTextStyles(presentation)
    }

    func testUnlimitedOnDemandShowsUsageWithoutMeterOrColoredText() async throws {
        let (presentation, _, _) = try await ScenarioLoad.presentation(.unlimited)
        XCTAssertEqual(presentation.text(matching: "billing"), "Total bill this cycle: $32.34")
        XCTAssertEqual(presentation.text(matching: "billingDetail"), "Pro $20.00 plan + $12.34 on-demand")
        XCTAssertEqual(presentation.text(matching: "onDemand"), "On-demand: $12.34 · unlimited")
        XCTAssertFalse(presentation.meters.contains { $0.role == "onDemandMeter" })
        XCTAssertTrue(presentation.menubar.segments.contains("$12.34"))
        assertOnDemandComesBeforeTotalBill(presentation)
        assertNoWarningTextStyles(presentation)
    }

    func testTeamEnterpriseDrivesMeterAndSplitsYouVsEveryoneElse() async throws {
        let (presentation, state, _) = try await ScenarioLoad.presentation(.teamEnterprise)
        XCTAssertEqual(presentation.text(matching: "header"), "Cursor Usage — Enterprise")
        XCTAssertEqual(state.summary?.membershipType, "enterprise")

        let meter = try XCTUnwrap(presentation.meters.first { $0.role == "onDemandMeter" })
        XCTAssertEqual(meter.content.title, "On-demand — $5.00 of $100.00")
        XCTAssertEqual(meter.content.percentUsed, 5, accuracy: 0.01)
        XCTAssertEqual(presentation.text(matching: "onDemandYou"), "$1.50 (you)")
        XCTAssertEqual(presentation.text(matching: "onDemandOthers"), "$3.50 (everyone else)")
        XCTAssertEqual(presentation.text(matching: "billing"), "Total bill this cycle: $21.50")
        XCTAssertEqual(presentation.text(matching: "billingDetail"), "Enterprise $20.00 plan + $1.50 on-demand")
        XCTAssertTrue(presentation.menubar.segments.contains("$5.00"))
        assertOnDemandComesBeforeTotalBill(presentation)
        assertNoWarningTextStyles(presentation)
    }

    func testHighOnDemandUsageTurnsMeterOrange() async throws {
        let (presentation, _, _) = try await ScenarioLoad.presentation(.limitedHigh)
        let meter = try XCTUnwrap(presentation.meters.first { $0.role == "onDemandMeter" })
        XCTAssertEqual(meter.content.title, "On-demand — $46.00 of $50.00")
        XCTAssertEqual(meter.content.percentUsed, 92, accuracy: 0.01)
        XCTAssertEqual(meter.level, .orange)
        XCTAssertEqual(presentation.text(matching: "billing"), "Total bill this cycle: $66.00")
        assertNoWarningTextStyles(presentation)
    }

    func testUltraPlanUsesUltraLabelAndPrice() async throws {
        let (presentation, _, _) = try await ScenarioLoad.presentation(.ultra)
        XCTAssertEqual(presentation.text(matching: "header"), "Cursor Usage — Ultra")
        XCTAssertEqual(presentation.text(matching: "billing"), "Total bill this cycle: $200.00")
        XCTAssertEqual(presentation.text(matching: "billingDetail"), "Ultra $200.00 plan + $0.00 on-demand")
        XCTAssertEqual(presentation.text(matching: "onDemand"), "On-demand: Disabled")
    }

    func testEmptyMetersAreZeroAndGreen() async throws {
        let (presentation, _, _) = try await ScenarioLoad.presentation(.emptyMeters)
        let cursor = try XCTUnwrap(presentation.meters.first { $0.role == "meter-cursor" })
        let api = try XCTUnwrap(presentation.meters.first { $0.role == "meter-api" })
        let bot = try XCTUnwrap(presentation.meters.first { $0.role == "meter-bot" })
        let onDemand = try XCTUnwrap(presentation.meters.first { $0.role == "onDemandMeter" })

        XCTAssertEqual(cursor.content.percentUsed, 0, accuracy: 0.01)
        XCTAssertEqual(api.content.percentUsed, 0, accuracy: 0.01)
        XCTAssertEqual(bot.content.percentUsed, 0, accuracy: 0.01)
        XCTAssertEqual(onDemand.content.percentUsed, 0, accuracy: 0.01)
        XCTAssertEqual(cursor.level, .green)
        XCTAssertEqual(onDemand.level, .green)
        XCTAssertEqual(cursor.content.leftCaption, "0% used")
    }

    func testFullMetersAreOneHundredAndRed() async throws {
        let (presentation, _, _) = try await ScenarioLoad.presentation(.fullMeters)
        let cursor = try XCTUnwrap(presentation.meters.first { $0.role == "meter-cursor" })
        let api = try XCTUnwrap(presentation.meters.first { $0.role == "meter-api" })
        let bot = try XCTUnwrap(presentation.meters.first { $0.role == "meter-bot" })
        let onDemand = try XCTUnwrap(presentation.meters.first { $0.role == "onDemandMeter" })

        XCTAssertEqual(cursor.content.percentUsed, 100, accuracy: 0.01)
        XCTAssertEqual(api.content.percentUsed, 100, accuracy: 0.01)
        XCTAssertEqual(bot.content.percentUsed, 100, accuracy: 0.01)
        XCTAssertEqual(onDemand.content.percentUsed, 100, accuracy: 0.01)
        XCTAssertEqual(cursor.level, .red)
        XCTAssertEqual(api.level, .red)
        XCTAssertEqual(bot.level, .red)
        XCTAssertEqual(onDemand.level, .red)
        XCTAssertEqual(cursor.content.leftCaption, "100% used")
    }

    func testCursorOnlyMenubarHidesUnusedAPIAndBot() async throws {
        let empty = try await ScenarioLoad.presentation(.cursorOnlyEmpty).0
        XCTAssertEqual(empty.menubar.segments, ["Cursor: 0%"])
        XCTAssertFalse(empty.meters.contains { $0.role == "meter-bot" })
        XCTAssertEqual(empty.text(matching: "onDemand"), "On-demand: Disabled")

        let full = try await ScenarioLoad.presentation(.cursorOnlyFull).0
        XCTAssertEqual(full.menubar.segments, ["Cursor: 100%"])
        XCTAssertEqual(full.meters.first { $0.role == "meter-cursor" }?.level, .red)
        XCTAssertEqual(full.meters.first { $0.role == "meter-api" }?.content.percentUsed, 0)
    }

    func testPlanDisplayMapsMembershipTypes() {
        XCTAssertEqual(PlanDisplay.name(fromMembership: "pro", isTeam: false), "Pro")
        XCTAssertEqual(PlanDisplay.name(fromMembership: "pro", isTeam: true), "Enterprise")
        XCTAssertEqual(PlanDisplay.name(fromMembership: "enterprise", isTeam: true), "Enterprise")
        XCTAssertEqual(PlanDisplay.name(fromMembership: "ultra", isTeam: false), "Ultra")
        XCTAssertEqual(PlanDisplay.name(fromMembership: "pro_plus", isTeam: false), "Pro+")
    }

    private func assertOnDemandComesBeforeTotalBill(_ presentation: MenuPresentation) {
        let roles = presentation.roleOrder
        let onDemandIndex = roles.firstIndex(where: { $0 == "onDemand" || $0 == "onDemandMeter" })
        let billingIndex = roles.firstIndex(of: "billing")
        XCTAssertNotNil(onDemandIndex)
        XCTAssertNotNil(billingIndex)
        if let onDemandIndex, let billingIndex {
            XCTAssertLessThan(onDemandIndex, billingIndex)
        }
        if let botIndex = roles.firstIndex(of: "meter-bot"), let onDemandIndex {
            XCTAssertLessThan(botIndex, onDemandIndex)
        }
    }

    private func assertNoWarningTextStyles(_ presentation: MenuPresentation) {
        for row in presentation.rows {
            if case let .text(item) = row {
                XCTAssertNotEqual(item.style.rawValue, "alert", item.text)
                XCTAssertNotEqual(item.style.rawValue, "emphasis", item.text)
            }
        }
    }
}
