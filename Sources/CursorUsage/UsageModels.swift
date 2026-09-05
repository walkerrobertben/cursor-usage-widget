import Foundation

enum ISODates {
    static func parse(_ value: String?) -> Date? {
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

enum ModelUsageKind {
    case cursor
    case api
    case bot

    static func classify(modelIntent: String?, tier: Int?) -> ModelUsageKind {
        if isGrokBotModel(modelIntent) {
            return .bot
        }
        if tier == 2 {
            return .cursor
        }
        return .api
    }

    /// Grok Bot's own model slugs. Cursor does not tag third-party models
    /// (Claude, GPT, Gemini, …) when the bot uses them.
    static func isGrokBotModel(_ name: String?) -> Bool {
        guard let name else { return false }
        let normalized = name.lowercased()
        return normalized.hasPrefix("grok-bot")
            || normalized.hasPrefix("sand-")
            || normalized.hasPrefix("sand_")
    }
}

struct ModelUsageRow {
    let name: String
    let tokens: Int
    let cents: Double
}

enum ModelUsageBreakdown {
    static func rows(
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

    static func centsUsed(
        in aggregations: [AggregatedUsageResponse.Aggregation]?,
        kind: ModelUsageKind
    ) -> Double {
        rows(from: aggregations, kind: kind).reduce(0) { $0 + $1.cents }
    }
}

enum PlanIncludedBudgets {
    /// Official Other Models (API) included allowance, in cents.
    /// Prefers `get-plan-info`, then a published individual-plan fallback.
    static func otherModelsCents(
        membershipType: String?,
        planInfo: PlanInfoResponse?
    ) -> Double? {
        if let cents = planInfo?.planInfo?.includedAmountCents, cents >= 0 {
            return Double(cents)
        }
        return fallbackOtherModelsCents(membershipType: membershipType)
    }

    static func fallbackOtherModelsCents(membershipType: String?) -> Double? {
        switch normalizedMembership(membershipType) {
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

    static func monthlyPriceCents(
        membershipType: String?,
        planInfo: PlanInfoResponse?
    ) -> Int? {
        if let parsed = parsePriceCents(planInfo?.planInfo?.price) {
            return parsed
        }
        return fallbackMonthlyPriceCents(membershipType: membershipType)
    }

    static func parsePriceCents(_ price: String?) -> Int? {
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

    static func fallbackMonthlyPriceCents(membershipType: String?) -> Int? {
        switch normalizedMembership(membershipType) {
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

    private static func normalizedMembership(_ value: String?) -> String {
        (value ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
    }
}

extension UsageFormatting.BillingSnapshot {
    static func make(
        summary: UsageSummaryResponse,
        planInfo: PlanInfoResponse?,
        hardLimit: HardLimitResponse?
    ) -> UsageFormatting.BillingSnapshot {
        UsageFormatting.BillingSnapshot(
            planName: planInfo?.planInfo?.planName ?? summary.membershipType,
            planPriceCents: PlanIncludedBudgets.monthlyPriceCents(
                membershipType: summary.membershipType,
                planInfo: planInfo
            ),
            individualUsedCents: summary.individualUsage?.onDemand?.used ?? 0,
            individualLimitCents: summary.individualUsage?.onDemand?.limit,
            teamUsedCents: summary.teamUsage?.onDemand?.used,
            teamLimitCents: summary.teamUsage?.onDemand?.limit,
            hardLimit: hardLimit,
            onDemandEnabled: summary.individualUsage?.onDemand?.enabled
        )
    }
}
