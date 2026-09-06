import Foundation

final class UsagePoller {
    private let statusController: StatusItemController
    private var api: CursorAPI?

    private var summaryTimer: Timer?
    private var aggregationTimer: Timer?

    private var lastSummary: UsageSummaryResponse?
    private var lastAggregations: AggregatedUsageResponse?
    private var lastWeeklyAggregations: AggregatedUsageResponse?
    private var lastSandUsage: SandUsageResponse?
    private var lastPlanInfo: PlanInfoResponse?
    private var lastHardLimit: HardLimitResponse?
    private var previousApiPercent: Double?
    private var previousAutoPercent: Double?
    private var previousBotPercent: Double?
    private var lastUpdated: Date?
    private var isAuthenticated = true
    private var authErrorMessage: String?

    init(statusController: StatusItemController) {
        self.statusController = statusController
        statusController.onRefreshRequested = { [weak self] in
            Task {
                await self?.refreshAll()
            }
        }
    }

    func start() {
        do {
            let auth = try CursorAuth.resolve()
            api = CursorAPI(auth: auth)
            isAuthenticated = true
            authErrorMessage = nil
        } catch {
            isAuthenticated = false
            authErrorMessage = error.localizedDescription
            pushDisplayState(apiIncreased: false, autoIncreased: false, botIncreased: false)
        }

        summaryTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task {
                await self?.pollSummary()
            }
        }

        aggregationTimer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
            Task {
                await self?.pollAggregations()
            }
        }

        Task {
            await refreshAll()
        }
    }

    func refreshAll() async {
        await pollSummary()
        await pollAggregations()
    }

    private func pollSummary() async {
        guard let api else { return }

        do {
            let summary = try await api.fetchUsageSummary()
            let apiPercent = summary.apiPercentUsed
            let autoPercent = summary.autoPercentUsed

            let apiIncreased = increased(current: apiPercent, previous: previousApiPercent)
            let autoIncreased = increased(current: autoPercent, previous: previousAutoPercent)

            previousApiPercent = apiPercent
            previousAutoPercent = autoPercent
            lastSummary = summary
            lastUpdated = Date()
            isAuthenticated = true
            authErrorMessage = nil

            let botIncreased = await refreshOptionalMeters(using: api)
            pushDisplayState(apiIncreased: apiIncreased, autoIncreased: autoIncreased, botIncreased: botIncreased)
        } catch let CursorAPIError.httpError(statusCode, _) where statusCode == 401 || statusCode == 403 {
            enterAuthError("Couldn't authenticate — is Cursor signed in?")
        } catch {
            // Keep last known data on network failures.
        }
    }

    /// Grok Bot weekly status and stated plan cap. Failures must not drop summary data.
    @discardableResult
    private func refreshOptionalMeters(using api: CursorAPI) async -> Bool {
        var botIncreased = false
        if let sand = try? await api.fetchSandUsage() {
            botIncreased = increased(current: sand.usagePercent, previous: previousBotPercent)
            previousBotPercent = sand.usagePercent
            lastSandUsage = sand
        }
        if let plan = try? await api.fetchPlanInfo() {
            lastPlanInfo = plan
        }
        if let hardLimit = try? await api.fetchHardLimit() {
            lastHardLimit = hardLimit
        }
        return botIncreased
    }

    private func pollAggregations() async {
        guard let api else { return }

        var summary = lastSummary
        if summary == nil {
            summary = try? await api.fetchUsageSummary()
            if let summary {
                lastSummary = summary
            }
        }

        guard let summary,
              let startDate = summary.billingCycleStartDate
        else {
            return
        }

        let endDate = summary.billingCycleEndDate ?? Date()

        do {
            let aggregations = try await api.fetchAggregatedUsage(
                startDate: startDate,
                endDate: endDate
            )
            lastAggregations = aggregations
            if let weekly = await api.fetchWeeklyBotAggregations(sand: lastSandUsage) {
                lastWeeklyAggregations = weekly
            }
            lastUpdated = Date()
            pushDisplayState(apiIncreased: false, autoIncreased: false, botIncreased: false)
        } catch let CursorAPIError.httpError(statusCode, _) where statusCode == 401 || statusCode == 403 {
            enterAuthError("Couldn't authenticate — is Cursor signed in?")
        } catch {
            // Keep last known data on network failures.
        }
    }

    private func enterAuthError(_ message: String) {
        isAuthenticated = false
        authErrorMessage = message
        pushDisplayState(apiIncreased: false, autoIncreased: false, botIncreased: false)
    }

    private func increased(current: Double?, previous: Double?) -> Bool {
        guard let current, let previous else { return false }
        return current > previous
    }

    private func pushDisplayState(apiIncreased: Bool, autoIncreased: Bool, botIncreased: Bool) {
        let state = UsageDisplayState(
            summary: lastSummary,
            aggregations: lastAggregations,
            weeklyAggregations: lastWeeklyAggregations,
            sandUsage: lastSandUsage,
            planInfo: lastPlanInfo,
            hardLimit: lastHardLimit,
            lastUpdated: lastUpdated,
            isAuthenticated: isAuthenticated,
            authErrorMessage: authErrorMessage,
            apiPercentIncreased: apiIncreased,
            autoPercentIncreased: autoIncreased,
            botPercentIncreased: botIncreased
        )
        DispatchQueue.main.async { [statusController] in
            statusController.apply(state: state)
        }
    }
}
