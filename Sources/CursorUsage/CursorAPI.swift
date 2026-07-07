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
        parseISO8601Date(billingCycleStart)
    }

    var billingCycleEndDate: Date? {
        parseISO8601Date(billingCycleEnd)
    }

    private func parseISO8601Date(_ value: String?) -> Date? {
        guard let value else { return nil }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
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
        percentUsed: Double?
    ) -> String {
        let percent: Double
        if let percentUsed, percentUsed.isFinite {
            percent = percentUsed
        } else {
            percent = 0
        }
        let safeUsedCents = usedCents.isFinite ? usedCents : 0
        let used = dollarsExact(fromCents: safeUsedCents)
        if let poolCents = predictedPoolCents(usedCents: safeUsedCents, percentUsed: percent) {
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
