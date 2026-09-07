import Foundation

public enum UsageFormatting {
    public struct BillingSnapshot: Equatable, Sendable {
        public enum OnDemandMode: Equatable, Sendable {
            case disabled
            case limited(limitCents: Int)
            case unlimited
        }

        public let planName: String?
        public let planPriceCents: Int?
        public let individualUsedCents: Int
        public let individualLimitCents: Int?
        public let teamUsedCents: Int?
        public let teamLimitCents: Int?
        public let hardLimit: HardLimitResponse?
        public let onDemandEnabled: Bool?

        public var hasTeamBudget: Bool { teamUsedCents != nil || teamLimitCents != nil }

        public var displayedUsedCents: Int {
            if hasTeamBudget {
                return teamUsedCents ?? 0
            }
            return individualUsedCents
        }

        public var mode: OnDemandMode {
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

        public var totalBillCents: Int? {
            guard let planPriceCents else {
                return individualUsedCents > 0 ? individualUsedCents : nil
            }
            return planPriceCents + individualUsedCents
        }

        public var totalBillLine: String? {
            guard let totalBillCents else { return nil }
            return "Total bill this cycle: \(UsageFormatting.dollarsFromCentsInt(totalBillCents))"
        }

        public var totalBillDetailLine: String? {
            guard let planPriceCents else { return nil }
            let planLabel = planName.map { "\($0) " } ?? ""
            return "\(planLabel)\(UsageFormatting.dollarsFromCentsInt(planPriceCents)) plan + \(UsageFormatting.dollarsFromCentsInt(individualUsedCents)) on-demand"
        }

        public var onDemandHeaderLine: String {
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

        public var onDemandPercentUsed: Double? {
            guard case let .limited(limitCents) = mode, limitCents > 0 else {
                return nil
            }
            return (Double(displayedUsedCents) / Double(limitCents)) * 100.0
        }

        public func onDemandMeter(resetDate: Date?, calendar: DisplayCalendar) -> UsageMeterContent? {
            guard let percent = onDemandPercentUsed,
                  case let .limited(limitCents) = mode
            else {
                return nil
            }
            return UsageMeterContent(
                title: "On-demand — \(UsageFormatting.dollarsFromCentsInt(displayedUsedCents)) of \(UsageFormatting.dollarsFromCentsInt(limitCents))",
                subtitle: nil,
                percentUsed: percent,
                leftCaption: UsageFormatting.percentUsedCaption(percent),
                rightCaption: UsageFormatting.resetCaption(resetDate, calendar: calendar)
            )
        }

        public var youLine: String {
            "\(UsageFormatting.dollarsFromCentsInt(individualUsedCents)) (you)"
        }

        public var everyoneElseLine: String? {
            guard hasTeamBudget else { return nil }
            let others = max(0, (teamUsedCents ?? 0) - individualUsedCents)
            return "\(UsageFormatting.dollarsFromCentsInt(others)) (everyone else)"
        }

        public var modeIdentifier: String {
            switch mode {
            case .disabled:
                return "disabled"
            case .limited:
                return "limited"
            case .unlimited:
                return "unlimited"
            }
        }

        public var limitCents: Int? {
            if case let .limited(limitCents) = mode {
                return limitCents
            }
            return nil
        }
    }

    public static func compactTokenCount(_ count: Int) -> String {
        let absolute = Double(abs(count))
        if absolute >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000.0)
        }
        if absolute >= 1_000 {
            return String(format: "%.1fk", Double(count) / 1_000.0)
        }
        return "\(count)"
    }

    public static func tokensColumnText(_ count: Int) -> String {
        "\(compactTokenCount(count)) tok"
    }

    public static func dollarsFromCents(_ cents: Double?) -> String {
        guard let cents else { return "$0.00" }
        return String(format: "$%.2f", cents / 100.0)
    }

    public static func dollarsFromCentsInt(_ cents: Int?) -> String {
        guard let cents else { return "$0.00" }
        return String(format: "$%.2f", Double(cents) / 100.0)
    }

    public static func predictedPoolCents(usedCents: Double, percentUsed: Double) -> Double? {
        guard usedCents.isFinite, percentUsed.isFinite else { return nil }
        guard usedCents > 0 else { return nil }
        guard percentUsed > 0.05 else { return nil }

        let fractionUsed = percentUsed / 100.0
        guard fractionUsed.isFinite, fractionUsed > 0 else { return nil }

        let poolCents = usedCents / fractionUsed
        guard poolCents.isFinite, poolCents > 0 else { return nil }
        return poolCents
    }

    public static func dollarsExact(fromCents cents: Double) -> String {
        guard cents.isFinite else { return "$0.00" }
        return String(format: "$%.2f", cents / 100.0)
    }

    public static func dollarsApproxPool(fromCents cents: Double) -> String {
        guard cents.isFinite else { return "~$0" }
        return String(format: "~$%.0f", (cents / 100.0).rounded())
    }

    public static func normalizedPercentUsed(_ percent: Double?) -> Double {
        guard let percent, percent.isFinite else { return 0 }
        return max(percent, 0)
    }

    public static func barFraction(percentUsed: Double) -> Double {
        min(normalizedPercentUsed(percentUsed) / 100.0, 1)
    }

    public static func percentUsedCaption(_ percent: Double?) -> String {
        let value = normalizedPercentUsed(percent)
        return "\(Int(value.rounded()))% used"
    }

    public static func resetCaption(_ date: Date?, calendar: DisplayCalendar) -> String {
        guard let date else { return "" }
        let formatter = DateFormatter()
        formatter.locale = calendar.locale
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "d MMM 'at' HH:mm"
        return "Resets \(formatter.string(from: date))"
    }

    public static func weeklyWindowLine(start: Date?, reset: Date?, calendar: DisplayCalendar) -> String? {
        guard let start, let reset else { return nil }
        return "\(formatCycleDate(start, calendar: calendar)) – \(formatCycleDate(reset, calendar: calendar))"
    }

    public static func poolSectionHeading(
        prefix: String,
        usedCents: Double,
        percentUsed: Double?,
        estimatePool: Bool = true
    ) -> String {
        let percent = normalizedPercentUsed(percentUsed)
        let safeUsedCents = usedCents.isFinite ? usedCents : 0
        let used = dollarsExact(fromCents: safeUsedCents)
        if estimatePool, let poolCents = predictedPoolCents(usedCents: safeUsedCents, percentUsed: percent) {
            return "\(prefix) — \(used) of \(dollarsApproxPool(fromCents: poolCents))"
        }
        return "\(prefix) — \(used)"
    }

    public static func poolSectionTitle(
        prefix: String,
        usedCents: Double,
        percentUsed: Double?
    ) -> String {
        let heading = poolSectionHeading(
            prefix: prefix,
            usedCents: usedCents,
            percentUsed: percentUsed
        )
        return String(format: "%@ (%.1f%%)", heading, normalizedPercentUsed(percentUsed))
    }

    public static func planLimitLine(statedPoolCents: Double?) -> String? {
        guard let statedPoolCents, statedPoolCents.isFinite, statedPoolCents > 0 else {
            return nil
        }
        return "Plan limit: \(dollarsExactWhole(fromCents: statedPoolCents))"
    }

    public static func dollarsExactWhole(fromCents cents: Double) -> String {
        guard cents.isFinite else { return "$0" }
        let dollars = cents / 100.0
        if abs(dollars - dollars.rounded()) < 0.005 {
            return String(format: "$%.0f", dollars.rounded())
        }
        return dollarsExact(fromCents: cents)
    }

    public static func formatCycleDate(_ date: Date, calendar: DisplayCalendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = calendar.locale
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date)
    }

    public static func formatTime(_ date: Date, calendar: DisplayCalendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = calendar.locale
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    public static func cycleLine(start: Date?, end: Date?, calendar: DisplayCalendar) -> String? {
        guard let start, let end else { return nil }
        return "Cycle: \(formatCycleDate(start, calendar: calendar)) – \(formatCycleDate(end, calendar: calendar))"
    }
}

extension UsageFormatting.BillingSnapshot {
    public static func make(
        summary: UsageSummaryResponse,
        planInfo: PlanInfoResponse?,
        hardLimit: HardLimitResponse?,
        teamSeat: TeamBillingSeat? = nil
    ) -> UsageFormatting.BillingSnapshot {
        UsageFormatting.BillingSnapshot(
            planName: PlanDisplay.name(summary: summary, planInfo: planInfo, teamSeat: teamSeat),
            planPriceCents: PlanIncludedBudgets.monthlyPriceCents(
                membershipType: summary.membershipType,
                planInfo: planInfo,
                teamSeat: teamSeat
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
