import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct UsageSummaryResponse: Decodable, Equatable, Sendable {
    public struct IndividualUsage: Decodable, Equatable, Sendable {
        public struct Plan: Decodable, Equatable, Sendable {
            public struct Breakdown: Decodable, Equatable, Sendable {
                public let included: Int?
                public let bonus: Int?
                public let total: Int?
            }

            public let enabled: Bool?
            public let used: Int?
            public let limit: Int?
            public let remaining: Int?
            public let breakdown: Breakdown?
            public let autoPercentUsed: Double?
            public let apiPercentUsed: Double?
            public let totalPercentUsed: Double?
        }

        public struct OnDemand: Decodable, Equatable, Sendable {
            public let enabled: Bool?
            public let used: Int?
            public let limit: Int?
            public let remaining: Int?
        }

        public let plan: Plan?
        public let onDemand: OnDemand?
    }

    public struct TeamUsage: Decodable, Equatable, Sendable {
        public struct OnDemand: Decodable, Equatable, Sendable {
            public let enabled: Bool?
            public let used: Int?
            public let limit: Int?
            public let remaining: Int?
        }

        public let onDemand: OnDemand?
    }

    public let billingCycleStart: String?
    public let billingCycleEnd: String?
    public let membershipType: String?
    public let limitType: String?
    public let isUnlimited: Bool?
    public let autoModelSelectedDisplayMessage: String?
    public let namedModelSelectedDisplayMessage: String?
    public let individualUsage: IndividualUsage?
    public let teamUsage: TeamUsage?
}

public struct AggregatedUsageResponse: Decodable, Equatable, Sendable {
    public struct Aggregation: Decodable, Equatable, Sendable {
        public let modelIntent: String?
        public let inputTokens: String?
        public let outputTokens: String?
        public let cacheWriteTokens: String?
        public let cacheReadTokens: String?
        public let totalCents: Double?
        public let tier: Int?
    }

    public let aggregations: [Aggregation]?
    public let totalInputTokens: String?
    public let totalOutputTokens: String?
    public let totalCacheWriteTokens: String?
    public let totalCacheReadTokens: String?
    public let totalCostCents: Double?
}

public struct SandUsageResponse: Decodable, Equatable, Sendable {
    public let currentPeriodStart: String?
    public let nextResetTimestampUtc: String?
    public let usagePercent: Double?
    public let hasAvailableUsage: Bool?
    public let hasNonZeroIncludedLimit: Bool?
    public let grokPlanLabel: String?

    public var periodStartDate: Date? {
        ISODates.parse(currentPeriodStart)
    }

    public var resetDate: Date? {
        ISODates.parse(nextResetTimestampUtc)
    }

    public var showsMenubarPercent: Bool {
        hasNonZeroIncludedLimit == true && usagePercent != nil
    }
}

public struct PlanInfoResponse: Decodable, Equatable, Sendable {
    public struct PlanInfo: Decodable, Equatable, Sendable {
        public let planName: String?
        public let includedAmountCents: Int?
        public let price: String?
        public let billingCycleEnd: String?
        public let planOwner: String?
    }

    public let planInfo: PlanInfo?
}

public struct HardLimitResponse: Decodable, Equatable, Sendable {
    public let noUsageBasedAllowed: Bool?
    public let hardLimit: Int?
    public let hardLimitPerUser: Int?

    enum CodingKeys: String, CodingKey {
        case noUsageBasedAllowed
        case hardLimit
        case hardLimitPerUser
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        noUsageBasedAllowed = try container.decodeIfPresent(Bool.self, forKey: .noUsageBasedAllowed)
        hardLimit = Self.decodeInt(from: container, forKey: .hardLimit)
        hardLimitPerUser = Self.decodeInt(from: container, forKey: .hardLimitPerUser)
    }

    public init(noUsageBasedAllowed: Bool?, hardLimit: Int?, hardLimitPerUser: Int?) {
        self.noUsageBasedAllowed = noUsageBasedAllowed
        self.hardLimit = hardLimit
        self.hardLimitPerUser = hardLimitPerUser
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

public enum CursorAPIError: LocalizedError, Sendable {
    case httpError(statusCode: Int, body: String)
    case decodingError(String)
    case invalidURL
    case missingBillingCycle

    public var errorDescription: String? {
        switch self {
        case let .httpError(statusCode, body):
            return "HTTP \(statusCode): \(body)"
        case let .decodingError(message):
            return "Failed to decode response: \(message)"
        case .invalidURL:
            return "Invalid API URL"
        case .missingBillingCycle:
            return "Usage summary missing billing cycle dates"
        }
    }
}

public final class CursorAPI: @unchecked Sendable {
    private var auth: CursorAuth
    private let session: URLSession

    public init(auth: CursorAuth, session: URLSession = .shared) {
        self.auth = auth
        self.session = session
    }

    public func updateAuth(_ auth: CursorAuth) {
        self.auth = auth
    }

    public func fetchUsageSummary() async throws -> UsageSummaryResponse {
        try await sendRequest(endpoint: .usageSummary, body: nil)
    }

    public func fetchAggregatedUsage(startDate: Date, endDate: Date) async throws -> AggregatedUsageResponse {
        let body: [String: Any] = [
            "teamId": -1,
            "startDate": Int(startDate.timeIntervalSince1970 * 1000),
            "endDate": Int(endDate.timeIntervalSince1970 * 1000),
        ]
        return try await sendRequest(
            endpoint: .aggregatedUsage,
            body: try JSONSerialization.data(withJSONObject: body)
        )
    }

    public func fetchSandUsage() async throws -> SandUsageResponse {
        try await sendRequest(endpoint: .sandUsage, body: Data("{}".utf8))
    }

    public func fetchPlanInfo() async throws -> PlanInfoResponse {
        try await sendRequest(endpoint: .planInfo, body: Data("{}".utf8))
    }

    public func fetchHardLimit() async throws -> HardLimitResponse {
        try await sendRequest(endpoint: .hardLimit, body: Data("{}".utf8))
    }

    /// Bot's official percent is weekly; monthly cycle $ cannot be divided by it.
    public func fetchWeeklyBotAggregations(
        sand: SandUsageResponse?,
        now: Date = Date()
    ) async -> AggregatedUsageResponse? {
        guard let start = sand?.periodStartDate else { return nil }
        let reset = sand?.resetDate ?? now
        let end = min(reset, now)
        guard end > start else { return nil }
        return try? await fetchAggregatedUsage(startDate: start, endDate: end)
    }

    private func sendRequest<Response: Decodable>(
        endpoint: CursorAPIEndpoint,
        body: Data?
    ) async throws -> Response {
        guard let url = URL(string: endpoint.urlString) else {
            throw CursorAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method
        request.setValue(auth.cookieHeaderValue, forHTTPHeaderField: "Cookie")
        if endpoint.requiresOrigin {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("https://cursor.com", forHTTPHeaderField: "Origin")
        }
        request.httpBody = body

        let (data, response) = try await session.cursorData(for: request)

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
            throw CursorAPIError.decodingError(error.localizedDescription)
        }
    }
}

extension AggregatedUsageResponse.Aggregation {
    public var totalTokens: Int {
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
    public var apiPercentUsed: Double? {
        individualUsage?.plan?.apiPercentUsed
    }

    public var autoPercentUsed: Double? {
        individualUsage?.plan?.autoPercentUsed
    }

    public var totalPercentUsed: Double? {
        individualUsage?.plan?.totalPercentUsed
    }

    public var billingCycleStartDate: Date? {
        ISODates.parse(billingCycleStart)
    }

    public var billingCycleEndDate: Date? {
        ISODates.parse(billingCycleEnd)
    }

    public var isTeamPlan: Bool {
        if let limitType, limitType.lowercased() == "team" {
            return true
        }
        return teamUsage?.onDemand != nil
    }
}
