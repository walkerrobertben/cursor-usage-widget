import Foundation

struct UsageSummaryResponse: Decodable {
    struct IndividualUsage: Decodable {
        struct Plan: Decodable {
            struct Breakdown: Decodable {
                let included: Int?
                let bonus: Int?
                let total: Int?
            }

            let enabled: Bool?
            let used: Int?
            let limit: Int?
            let remaining: Int?
            let breakdown: Breakdown?
            let autoPercentUsed: Double?
            let apiPercentUsed: Double?
            let totalPercentUsed: Double?
        }

        struct OnDemand: Decodable {
            let enabled: Bool?
            let used: Int?
            let limit: Int?
            let remaining: Int?
        }

        let plan: Plan?
        let onDemand: OnDemand?
    }

    struct TeamUsage: Decodable {
        struct OnDemand: Decodable {
            let enabled: Bool?
            let used: Int?
            let limit: Int?
            let remaining: Int?
        }

        let onDemand: OnDemand?
    }

    let billingCycleStart: String?
    let billingCycleEnd: String?
    let membershipType: String?
    let limitType: String?
    let isUnlimited: Bool?
    let autoModelSelectedDisplayMessage: String?
    let namedModelSelectedDisplayMessage: String?
    let individualUsage: IndividualUsage?
    let teamUsage: TeamUsage?
}

struct AggregatedUsageResponse: Decodable {
    struct Aggregation: Decodable {
        let modelIntent: String?
        let inputTokens: String?
        let outputTokens: String?
        let cacheWriteTokens: String?
        let cacheReadTokens: String?
        let totalCents: Double?
        let tier: Int?
    }

    let aggregations: [Aggregation]?
    let totalInputTokens: String?
    let totalOutputTokens: String?
    let totalCacheWriteTokens: String?
    let totalCacheReadTokens: String?
    let totalCostCents: Double?
}

struct SandUsageResponse: Decodable {
    let currentPeriodStart: String?
    let nextResetTimestampUtc: String?
    let usagePercent: Double?
    let hasAvailableUsage: Bool?
    let hasNonZeroIncludedLimit: Bool?
    let grokPlanLabel: String?

    var periodStartDate: Date? {
        ISODates.parse(currentPeriodStart)
    }

    var resetDate: Date? {
        ISODates.parse(nextResetTimestampUtc)
    }

    var showsMenubarPercent: Bool {
        hasNonZeroIncludedLimit == true && usagePercent != nil
    }
}

struct PlanInfoResponse: Decodable {
    struct PlanInfo: Decodable {
        let planName: String?
        let includedAmountCents: Int?
        let price: String?
        let billingCycleEnd: String?
        let planOwner: String?
    }

    let planInfo: PlanInfo?
}

struct HardLimitResponse: Decodable {
    let noUsageBasedAllowed: Bool?
    let hardLimit: Int?
    let hardLimitPerUser: Int?

    enum CodingKeys: String, CodingKey {
        case noUsageBasedAllowed
        case hardLimit
        case hardLimitPerUser
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        noUsageBasedAllowed = try container.decodeIfPresent(Bool.self, forKey: .noUsageBasedAllowed)
        hardLimit = Self.decodeInt(from: container, forKey: .hardLimit)
        hardLimitPerUser = Self.decodeInt(from: container, forKey: .hardLimitPerUser)
    }

    private static func decodeInt(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> Int? {
        if let value = try? container.decode(Int.self, forKey: key) {
            return value
        }
        if let value = try? container.decode(Double.self, forKey: key) {
            return Int(value.rounded())
        }
        return nil
    }
}

enum CursorAPIError: LocalizedError {
    case httpError(statusCode: Int, body: String)
    case decodingError(Error)
    case invalidURL
    case missingBillingCycle

    var errorDescription: String? {
        switch self {
        case let .httpError(statusCode, body):
            return "HTTP \(statusCode): \(body)"
        case let .decodingError(error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .invalidURL:
            return "Invalid API URL"
        case .missingBillingCycle:
            return "Usage summary missing billing cycle dates"
        }
    }
}

final class CursorAPI {
    private var auth: CursorAuth

    init(auth: CursorAuth) {
        self.auth = auth
    }

    func refreshAuth() throws {
        auth = try CursorAuth.resolve()
    }

    func fetchUsageSummary() async throws -> UsageSummaryResponse {
        try await performRequest(
            urlString: "https://cursor.com/api/usage-summary",
            method: "GET",
            body: nil,
            includeOrigin: false,
            retryOnAuthFailure: true
        )
    }

    func fetchAggregatedUsage(startDate: Date, endDate: Date) async throws -> AggregatedUsageResponse {
        let body: [String: Any] = [
            "teamId": -1,
            "startDate": Int(startDate.timeIntervalSince1970 * 1000),
            "endDate": Int(endDate.timeIntervalSince1970 * 1000),
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: body)

        return try await performRequest(
            urlString: "https://cursor.com/api/dashboard/get-aggregated-usage-events",
            method: "POST",
            body: bodyData,
            includeOrigin: true,
            retryOnAuthFailure: true
        )
    }

    func fetchSandUsage() async throws -> SandUsageResponse {
        try await performRequest(
            urlString: "https://cursor.com/api/dashboard/get-sand-usage-status",
            method: "POST",
            body: Data("{}".utf8),
            includeOrigin: true,
            retryOnAuthFailure: true
        )
    }

    func fetchPlanInfo() async throws -> PlanInfoResponse {
        try await performRequest(
            urlString: "https://cursor.com/api/dashboard/get-plan-info",
            method: "POST",
            body: Data("{}".utf8),
            includeOrigin: true,
            retryOnAuthFailure: true
        )
    }

    func fetchHardLimit() async throws -> HardLimitResponse {
        try await performRequest(
            urlString: "https://cursor.com/api/dashboard/get-hard-limit",
            method: "POST",
            body: Data("{}".utf8),
            includeOrigin: true,
            retryOnAuthFailure: true
        )
    }

    private func performRequest<Response: Decodable>(
        urlString: String,
        method: String,
        body: Data?,
        includeOrigin: Bool,
        retryOnAuthFailure: Bool
    ) async throws -> Response {
        do {
            return try await sendRequest(
                urlString: urlString,
                method: method,
                body: body,
                includeOrigin: includeOrigin
            )
        } catch let CursorAPIError.httpError(statusCode, _) where retryOnAuthFailure && (statusCode == 401 || statusCode == 403) {
            try refreshAuth()
            return try await sendRequest(
                urlString: urlString,
                method: method,
                body: body,
                includeOrigin: includeOrigin
            )
        }
    }

    private func sendRequest<Response: Decodable>(
        urlString: String,
        method: String,
        body: Data?,
        includeOrigin: Bool
    ) async throws -> Response {
        guard let url = URL(string: urlString) else {
            throw CursorAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(auth.cookieHeaderValue, forHTTPHeaderField: "Cookie")
        if includeOrigin {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("https://cursor.com", forHTTPHeaderField: "Origin")
        }
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CursorAPIError.httpError(statusCode: -1, body: "No HTTP response")
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw CursorAPIError.httpError(statusCode: httpResponse.statusCode, body: bodyText)
        }

        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw CursorAPIError.decodingError(error)
        }
    }
}

extension AggregatedUsageResponse.Aggregation {
    var totalTokens: Int {
        parseTokenCount(inputTokens)
            + parseTokenCount(outputTokens)
            + parseTokenCount(cacheWriteTokens)
            + parseTokenCount(cacheReadTokens)
    }

    private func parseTokenCount(_ value: String?) -> Int {
        guard let value, let count = Int(value) else {
            return 0
        }
        return count
    }
}

extension UsageSummaryResponse {
    var apiPercentUsed: Double? {
        individualUsage?.plan?.apiPercentUsed
    }

    var autoPercentUsed: Double? {
        individualUsage?.plan?.autoPercentUsed
    }

    var totalPercentUsed: Double? {
        individualUsage?.plan?.totalPercentUsed
    }

    var billingCycleStartDate: Date? {
        ISODates.parse(billingCycleStart)
    }

    var billingCycleEndDate: Date? {
        ISODates.parse(billingCycleEnd)
    }
}

enum UsageFormatting {
    static func compactTokenCount(_ count: Int) -> String {
        let absolute = Double(abs(count))
        if absolute >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000.0)
        }
        if absolute >= 1_000 {
            return String(format: "%.1fk", Double(count) / 1_000.0)
        }
        return "\(count)"
    }

    static func dollarsFromCents(_ cents: Double?) -> String {
        guard let cents else { return "$0.00" }
        return String(format: "$%.2f", cents / 100.0)
    }

    static func dollarsFromCentsInt(_ cents: Int?) -> String {
        guard let cents else { return "$0.00" }
        return String(format: "$%.2f", Double(cents) / 100.0)
    }

    struct BillingSnapshot {
        enum OnDemandMode {
            case disabled
            case limited(limitCents: Int)
            case unlimited
        }

        let planName: String?
        let planPriceCents: Int?
        let individualUsedCents: Int
        let individualLimitCents: Int?
        let teamUsedCents: Int?
        let teamLimitCents: Int?
        let hardLimit: HardLimitResponse?
        let onDemandEnabled: Bool?

        var hasTeamBudget: Bool { teamUsedCents != nil || teamLimitCents != nil }

        var displayedUsedCents: Int {
            if hasTeamBudget {
                return teamUsedCents ?? 0
            }
            return individualUsedCents
        }

        var mode: OnDemandMode {
            if hardLimit?.noUsageBasedAllowed == true || onDemandEnabled == false {
                return .disabled
            }

            if let limit = resolvedLimitCents, limit > 0 {
                return .limited(limitCents: limit)
            }

            if hardLimit?.noUsageBasedAllowed == false || onDemandEnabled == true {
                return .unlimited
            }

            return .disabled
        }

        private var resolvedLimitCents: Int? {
            if let teamLimitCents, teamLimitCents > 0 {
                return teamLimitCents
            }
            if let individualLimitCents, individualLimitCents > 0 {
                return individualLimitCents
            }
            if let dollars = hardLimit?.hardLimit, dollars > 0 {
                return dollars * 100
            }
            return nil
        }

        var totalBillCents: Int? {
            guard let planPriceCents else {
                return individualUsedCents > 0 ? individualUsedCents : nil
            }
            return planPriceCents + individualUsedCents
        }

        var totalBillLine: String? {
            guard let totalBillCents else { return nil }
            return "Total bill this cycle: \(UsageFormatting.dollarsFromCentsInt(totalBillCents))"
        }

        var totalBillDetailLine: String? {
            guard let planPriceCents else { return nil }
            let planLabel = planName.map { "\($0) " } ?? ""
            return "\(planLabel)\(UsageFormatting.dollarsFromCentsInt(planPriceCents)) plan + \(UsageFormatting.dollarsFromCentsInt(individualUsedCents)) on-demand"
        }

        var onDemandHeaderLine: String {
            let used = UsageFormatting.dollarsFromCentsInt(displayedUsedCents)
            switch mode {
            case .disabled:
                return "On-demand: Disabled"
            case let .limited(limitCents):
                return "On-demand: \(used) / \(UsageFormatting.dollarsFromCentsInt(limitCents)) limit"
            case .unlimited:
                return "On-demand: \(used) · unlimited"
            }
        }

        var youLine: String {
            "\(UsageFormatting.dollarsFromCentsInt(individualUsedCents)) (you)"
        }

        var everyoneElseLine: String? {
            guard hasTeamBudget else { return nil }
            let others = max(0, (teamUsedCents ?? 0) - individualUsedCents)
            return "\(UsageFormatting.dollarsFromCentsInt(others)) (everyone else)"
        }

        var isOnDemandActive: Bool {
            displayedUsedCents > 0 || individualUsedCents > 0
        }

        var plainText: String {
            var lines: [String] = []
            if let totalBillLine {
                lines.append(totalBillLine)
            }
            if let totalBillDetailLine {
                lines.append("  \(totalBillDetailLine)")
            }
            lines.append(onDemandHeaderLine)
            if hasTeamBudget {
                lines.append("  \(youLine)")
                if let everyoneElseLine {
                    lines.append("  \(everyoneElseLine)")
                }
            }
            return lines.joined(separator: "\n")
        }
    }

    /// Extrapolate total pool size from spend so far and percent used.
    /// Returns nil when the inputs aren't enough to estimate safely (cycle
    /// reset, no spend yet, tiny %, or non-finite API values).
    static func predictedPoolCents(usedCents: Double, percentUsed: Double) -> Double? {
        guard usedCents.isFinite, percentUsed.isFinite else { return nil }
        guard usedCents > 0 else { return nil }
        // Skip tiny percentages — noise early in a cycle blows up the estimate,
        // and percentUsed == 0 would divide by zero.
        guard percentUsed > 0.05 else { return nil }

        let fractionUsed = percentUsed / 100.0
        guard fractionUsed.isFinite, fractionUsed > 0 else { return nil }

        let poolCents = usedCents / fractionUsed
        guard poolCents.isFinite, poolCents > 0 else { return nil }
        return poolCents
    }

    static func dollarsExact(fromCents cents: Double) -> String {
        guard cents.isFinite else { return "$0.00" }
        return String(format: "$%.2f", cents / 100.0)
    }

    /// Whole-dollar estimate for extrapolated pools (not exact metering).
    static func dollarsApproxPool(fromCents cents: Double) -> String {
        guard cents.isFinite else { return "~$0" }
        return String(format: "~$%.0f", (cents / 100.0).rounded())
    }

    static func poolSectionTitle(
        prefix: String,
        usedCents: Double,
        percentUsed: Double?,
        estimatePool: Bool = true
    ) -> String {
        let percent: Double
        if let percentUsed, percentUsed.isFinite {
            percent = percentUsed
        } else {
            percent = 0
        }
        let safeUsedCents = usedCents.isFinite ? usedCents : 0
        let used = dollarsExact(fromCents: safeUsedCents)
        if estimatePool, let poolCents = predictedPoolCents(usedCents: safeUsedCents, percentUsed: percent) {
            return String(
                format: "%@ — %@ of %@ (%.1f%%)",
                prefix,
                used,
                dollarsApproxPool(fromCents: poolCents),
                percent
            )
        }
        return String(format: "%@ — %@ (%.1f%%)", prefix, used, percent)
    }

    /// Official included cap from the plan, when Cursor publishes one.
    static func planLimitLine(statedPoolCents: Double?) -> String? {
        guard let statedPoolCents, statedPoolCents.isFinite, statedPoolCents > 0 else {
            return nil
        }
        return "Plan limit: \(dollarsExactWhole(fromCents: statedPoolCents))"
    }

    static func dollarsExactWhole(fromCents cents: Double) -> String {
        guard cents.isFinite else { return "$0" }
        let dollars = cents / 100.0
        if abs(dollars - dollars.rounded()) < 0.005 {
            return String(format: "$%.0f", dollars.rounded())
        }
        return dollarsExact(fromCents: cents)
    }

    static func botResetLine(start: Date?, reset: Date?, now: Date = Date()) -> String {
        var parts: [String] = []
        if let start, let reset {
            parts.append("\(formatCycleDate(start)) – \(formatCycleDate(reset))")
        }
        if let reset {
            parts.append(resetCountdown(until: reset, now: now))
        }
        if parts.isEmpty {
            return "Weekly Grok Bot allowance"
        }
        return "Weekly · " + parts.joined(separator: " · ")
    }

    static func resetCountdown(until date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: date)
        ).day ?? 0
        let dateText = formatCycleDate(date)
        if days <= 0 {
            return "Resets \(dateText) (today)"
        }
        if days == 1 {
            return "Resets \(dateText) (1 day left)"
        }
        return "Resets \(dateText) (\(days) days left)"
    }

    static func formatCycleDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date)
    }

    static func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}
