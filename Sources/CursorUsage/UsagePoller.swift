import Foundation

final class UsagePoller {
    private let statusController: StatusItemController
    private var api: CursorAPI?

    private var summaryTimer: Timer?
    private var aggregationTimer: Timer?

    private var lastSummary: UsageSummaryResponse?
    private var lastAggregations: AggregatedUsageResponse?
    private var previousApiPercent: Double?
    private var previousAutoPercent: Double?
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
            pushDisplayState(apiIncreased: false, autoIncreased: false)
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

            pushDisplayState(apiIncreased: apiIncreased, autoIncreased: autoIncreased)
        } catch let CursorAPIError.httpError(statusCode, _) where statusCode == 401 || statusCode == 403 {
            enterAuthError("Couldn't authenticate — is Cursor signed in?")
        } catch {
            // Keep last known data on network failures.
        }
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
            lastUpdated = Date()
            pushDisplayState(apiIncreased: false, autoIncreased: false)
        } catch let CursorAPIError.httpError(statusCode, _) where statusCode == 401 || statusCode == 403 {
            enterAuthError("Couldn't authenticate — is Cursor signed in?")
        } catch {
            // Keep last known data on network failures.
        }
    }

    private func enterAuthError(_ message: String) {
        isAuthenticated = false
        authErrorMessage = message
        pushDisplayState(apiIncreased: false, autoIncreased: false)
    }

    private func increased(current: Double?, previous: Double?) -> Bool {
        guard let current, let previous else { return false }
        return current > previous
    }

    private func pushDisplayState(apiIncreased: Bool, autoIncreased: Bool) {
        let state = UsageDisplayState(
            summary: lastSummary,
            aggregations: lastAggregations,
            lastUpdated: lastUpdated,
            isAuthenticated: isAuthenticated,
            authErrorMessage: authErrorMessage,
            apiPercentIncreased: apiIncreased,
            autoPercentIncreased: autoIncreased
        )
        DispatchQueue.main.async { [statusController] in
            statusController.apply(state: state)
        }
    }
}

enum CheckMode {
    static func run() -> Int32 {
        do {
            let auth = try CursorAuth.resolve()
            print("Database: \(auth.databasePath)")
            print("Resolved via: \(auth.source)")
            print("User ID: \(auth.userId)")

            let api = CursorAPI(auth: auth)
            let summary = try awaitSync { try await api.fetchUsageSummary() }

            print("Membership: \(summary.membershipType ?? "unknown")")
            if let start = summary.billingCycleStart, let end = summary.billingCycleEnd {
                print("Billing cycle: \(start) – \(end)")
            }
            print(String(format: "API percent: %.2f", summary.apiPercentUsed ?? 0))
            print(String(format: "Auto percent: %.2f", summary.autoPercentUsed ?? 0))
            print(String(format: "Total percent: %.2f", summary.totalPercentUsed ?? 0))
            let onDemandUsed = summary.individualUsage?.onDemand?.used ?? 0
            let teamUsed = summary.teamUsage?.onDemand?.used
            let teamLimit = summary.teamUsage?.onDemand?.limit
            print(
                UsageFormatting.OnDemandBreakdown(
                    individualUsedCents: onDemandUsed,
                    teamUsedCents: teamUsed,
                    teamLimitCents: teamLimit
                ).plainText
            )

            guard let startDate = summary.billingCycleStartDate,
                  let endDate = summary.billingCycleEndDate
            else {
                throw CursorAPIError.missingBillingCycle
            }

            let aggregations = try awaitSync {
                try await api.fetchAggregatedUsage(startDate: startDate, endDate: endDate)
            }

            let models = aggregations.aggregations ?? []
            if models.isEmpty {
                print("No model usage found for billing cycle")
            } else {
                for model in models.sorted(by: { ($0.totalCents ?? 0) > ($1.totalCents ?? 0) }) {
                    let intent = model.modelIntent ?? "unknown"
                    let tier = model.tier ?? -1
                    let tokens = model.totalTokens
                    let dollars = UsageFormatting.dollarsFromCents(model.totalCents)
                    print("\(intent) | tier \(tier) | \(tokens) tokens | \(dollars)")
                }
            }

            return 0
        } catch {
            fputs("Error: \(error.localizedDescription)\n", stderr)
            return 1
        }
    }

    private static func awaitSync<T>(_ operation: @escaping () async throws -> T) throws -> T {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<T, Error>?

        Task {
            do {
                result = .success(try await operation())
            } catch {
                result = .failure(error)
            }
            semaphore.signal()
        }

        semaphore.wait()

        switch result {
        case let .success(value):
            return value
        case let .failure(error):
            throw error
        case .none:
            throw CursorAPIError.invalidURL
        }
    }
}
