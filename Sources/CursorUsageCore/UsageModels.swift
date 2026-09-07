import Foundation

public enum ISODates {
    public static func parse(_ value: String?) -> Date? {
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

public enum ModelUsageKind: Sendable {
    case cursor
    case api
    case bot

    public static func classify(modelIntent: String?, tier: Int?) -> ModelUsageKind {
        if isGrokBotModel(modelIntent) {
            return .bot
        }
        if tier == 2 {
            return .cursor
        }
        return .api
    }

    public static func isGrokBotModel(_ name: String?) -> Bool {
        guard let name else { return false }
        let normalized = name.lowercased()
        return normalized.hasPrefix("grok-bot")
            || normalized.hasPrefix("sand-")
            || normalized.hasPrefix("sand_")
    }
}

public struct ModelUsageRow: Equatable, Sendable {
    public let name: String
    public let tokens: Int
    public let cents: Double
}

public enum ModelUsageBreakdown {
    public static func rows(
        from aggregations: [AggregatedUsageResponse.Aggregation]?,
        kind: ModelUsageKind
    ) -> [ModelUsageRow] {
        guard let aggregations else { return [] }

        var merged: [String: (tokens: Int, cents: Double)] = [:]
        for aggregation in aggregations {
            guard ModelUsageKind.classify(
                modelIntent: aggregation.modelIntent,
                tier: aggregation.tier
            ) == kind else {
                continue
            }

            let name = aggregation.modelIntent ?? "unknown"
            let current = merged[name] ?? (0, 0)
            merged[name] = (
                current.tokens + aggregation.totalTokens,
                current.cents + (aggregation.totalCents ?? 0)
            )
        }

        return merged
            .map { ModelUsageRow(name: $0.key, tokens: $0.value.tokens, cents: $0.value.cents) }
            .filter { $0.cents > 0 || $0.tokens > 0 }
            .sorted { $0.cents > $1.cents }
    }

    public static func centsUsed(
        in aggregations: [AggregatedUsageResponse.Aggregation]?,
        kind: ModelUsageKind
    ) -> Double {
        rows(from: aggregations, kind: kind).reduce(0) { $0 + $1.cents }
    }
}

public enum TeamBillingSeat: Equatable, Sendable {
    case standard
    case premium

    public var displayName: String {
        switch self {
        case .standard:
            return "Standard"
        case .premium:
            return "Premium"
        }
    }

    public var monthlyPriceCents: Int {
        switch self {
        case .standard:
            return 4_000
        case .premium:
            return 12_000
        }
    }

    public static func parse(_ raw: String?) -> TeamBillingSeat? {
        let value = PlanDisplay.normalized(raw)
        if value.contains("tier_2000") {
            return .premium
        }
        if value.contains("tier_1000") {
            return .standard
        }
        return nil
    }
}

public enum PlanDisplay {
    public static func name(
        summary: UsageSummaryResponse,
        planInfo: PlanInfoResponse?,
        teamSeat: TeamBillingSeat? = nil
    ) -> String {
        if let teamSeat {
            return teamSeat.displayName
        }
        if let planName = planInfo?.planInfo?.planName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !planName.isEmpty
        {
            return planName
        }
        return name(fromMembership: summary.membershipType, isTeam: summary.isTeamPlan)
    }

    public static func name(fromMembership membershipType: String?, isTeam: Bool) -> String {
        switch normalized(membershipType) {
        case "enterprise":
            return "Enterprise"
        case "ultra":
            return "Ultra"
        case "pro_plus", "proplus", "pro+", "pro plus":
            return "Pro+"
        case "pro":
            return isTeam ? "Enterprise" : "Pro"
        case "hobby", "free", "start":
            return "Hobby"
        case let value where !value.isEmpty:
            return value.replacingOccurrences(of: "_", with: " ").capitalized
        default:
            return isTeam ? "Enterprise" : "Cursor"
        }
    }

    public static func normalized(_ value: String?) -> String {
        (value ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
    }
}

public enum PlanIncludedBudgets {
    public static func otherModelsCents(
        membershipType: String?,
        planInfo: PlanInfoResponse?
    ) -> Double? {
        if let cents = planInfo?.planInfo?.includedAmountCents, cents >= 0 {
            return Double(cents)
        }
        return fallbackOtherModelsCents(membershipType: membershipType)
    }

    public static func fallbackOtherModelsCents(membershipType: String?) -> Double? {
        switch PlanDisplay.normalized(membershipType) {
        case "ultra":
            return 40_000
        case "pro_plus", "proplus", "pro+", "pro plus":
            return 7_000
        case "pro":
            return 2_000
        case "hobby", "free", "start":
            return 0
        default:
            return nil
        }
    }

    public static func monthlyPriceCents(
        membershipType: String?,
        planInfo: PlanInfoResponse?,
        teamSeat: TeamBillingSeat? = nil
    ) -> Int? {
        if let teamSeat {
            return teamSeat.monthlyPriceCents
        }
        if let parsed = parsePriceCents(planInfo?.planInfo?.price) {
            return parsed
        }
        return fallbackMonthlyPriceCents(membershipType: membershipType)
    }

    public static func parsePriceCents(_ price: String?) -> Int? {
        guard let price else { return nil }
        let collapsed = price.replacingOccurrences(of: ",", with: "")
        guard let match = collapsed.range(of: #"\$([0-9]+(?:\.[0-9]+)?)"#, options: .regularExpression) else {
            return nil
        }
        let number = String(collapsed[match]).dropFirst()
        guard let dollars = Double(number), dollars.isFinite, dollars >= 0 else {
            return nil
        }
        return Int((dollars * 100.0).rounded())
    }

    public static func fallbackMonthlyPriceCents(membershipType: String?) -> Int? {
        switch PlanDisplay.normalized(membershipType) {
        case "ultra":
            return 20_000
        case "pro_plus", "proplus", "pro+", "pro plus":
            return 6_000
        case "pro":
            return 2_000
        case "hobby", "free", "start":
            return 0
        default:
            return nil
        }
    }
}
