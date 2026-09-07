import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Model entry point: given auth (and an optional `URLSession`), load usage.
public struct UsageClient: Sendable {
    private let api: CursorAPI

    public init(auth: CursorAuth, session: URLSession = .shared) {
        self.api = CursorAPI(auth: auth, session: session)
    }

    public init(api: CursorAPI) {
        self.api = api
    }

    public func load(now: Date = Date()) async -> UsageDisplayState {
        let summary: UsageSummaryResponse
        do {
            summary = try await api.fetchUsageSummary()
        } catch let CursorAPIError.httpError(statusCode, _) where statusCode == 401 || statusCode == 403 {
            return UsageDisplayState(
                lastUpdated: now,
                isAuthenticated: false,
                authErrorMessage: MenuPresentation.authFallbackMessage
            )
        } catch {
            return UsageDisplayState(
                lastUpdated: now,
                isAuthenticated: false,
                authErrorMessage: error.localizedDescription
            )
        }

        let sand = try? await api.fetchSandUsage()
        let plan = try? await api.fetchPlanInfo()
        let hardLimit = try? await api.fetchHardLimit()
        let teamSeat = await Self.loadTeamSeat(api: api, summary: summary)

        var aggregations: AggregatedUsageResponse?
        var weekly: AggregatedUsageResponse?
        if let start = summary.billingCycleStartDate {
            let end = summary.billingCycleEndDate ?? now
            aggregations = try? await api.fetchAggregatedUsage(startDate: start, endDate: end)
            weekly = await api.fetchWeeklyBotAggregations(sand: sand, now: now)
        }

        return UsageDisplayState(
            summary: summary,
            aggregations: aggregations,
            weeklyAggregations: weekly,
            sandUsage: sand,
            planInfo: plan,
            hardLimit: hardLimit,
            teamSeat: teamSeat,
            lastUpdated: now,
            isAuthenticated: true,
            authErrorMessage: nil
        )
    }

    public static func presentation(
        from state: UsageDisplayState,
        calendar: DisplayCalendar = .current
    ) -> MenuPresentation {
        MenuPresentation.make(from: state, calendar: calendar)
    }

    private static func loadTeamSeat(api: CursorAPI, summary: UsageSummaryResponse) async -> TeamBillingSeat? {
        guard summary.isTeamPlan else { return nil }
        guard let me = try? await api.fetchMe(),
              let teamId = me.teamId,
              let userId = me.userId
        else {
            return nil
        }
        guard let spend = try? await api.fetchTeamSpend(teamId: teamId) else {
            return nil
        }
        return spend.seat(forUserId: userId)
    }
}
