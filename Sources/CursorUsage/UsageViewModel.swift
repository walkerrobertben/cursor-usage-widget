import Foundation

struct UsageDisplayState {
    var summary: UsageSummaryResponse?
    var aggregations: AggregatedUsageResponse?
    var weeklyAggregations: AggregatedUsageResponse?
    var sandUsage: SandUsageResponse?
    var planInfo: PlanInfoResponse?
    var hardLimit: HardLimitResponse?
    var lastUpdated: Date?
    var isAuthenticated: Bool = true
    var authErrorMessage: String?
    var apiPercentIncreased: Bool = false
    var autoPercentIncreased: Bool = false
    var botPercentIncreased: Bool = false
}

struct UsageMeterContent {
    var title: String
    var subtitle: String?
    var percentUsed: Double
    var leftCaption: String
    var rightCaption: String
}

struct UsageModelRowContent {
    var name: String
    var tokens: String
    var cost: String
}

enum UsageMeterLevel: String {
    case green
    case yellow
    case orange
    case red

    static func from(percentUsed: Double) -> UsageMeterLevel {
        let percent = UsageFormatting.normalizedPercentUsed(percentUsed)
        if percent >= 100 { return .red }
        if percent >= 90 { return .orange }
        if percent >= 70 { return .yellow }
        return .green
    }
}

struct MenubarSegment: Equatable {
    var text: String
}

enum MenubarPresentation: Equatable {
    case hidden
    case warning
    case visible([MenubarSegment])

    var compactLine: String? {
        switch self {
        case .hidden:
            return nil
        case .warning:
            return "⚠ Cursor"
        case let .visible(segments):
            return segments.map(\.text).joined(separator: " · ")
        }
    }

    static func make(from state: UsageDisplayState) -> MenubarPresentation {
        if !state.isAuthenticated {
            return .warning
        }
        guard let summary = state.summary else {
            return .hidden
        }

        let apiPercent = summary.apiPercentUsed ?? 0
        let autoPercent = summary.autoPercentUsed ?? 0
        let individualOnDemand = summary.individualUsage?.onDemand?.used ?? 0
        let teamOnDemand = summary.teamUsage?.onDemand?.used
        // Prefer team total in the menubar when a team budget exists.
        let onDemandMenubarCents = teamOnDemand ?? individualOnDemand

        var segments: [MenubarSegment] = []
        segments.append(
            MenubarSegment(
                text: labeledPercentText(
                    label: "Cursor",
                    percent: autoPercent,
                    showUpArrow: state.autoPercentIncreased
                )
            )
        )

        if Int(apiPercent.rounded()) > 0 {
            segments.append(
                MenubarSegment(
                    text: labeledPercentText(
                        label: "API",
                        percent: apiPercent,
                        showUpArrow: state.apiPercentIncreased
                    )
                )
            )
        }

        if let botPercent = state.sandUsage?.usagePercent,
           state.sandUsage?.showsMenubarPercent == true,
           Int(botPercent.rounded()) > 0
        {
            segments.append(
                MenubarSegment(
                    text: labeledPercentText(
                        label: "Bot",
                        percent: botPercent,
                        showUpArrow: state.botPercentIncreased
                    )
                )
            )
        }

        if onDemandMenubarCents > 0 {
            segments.append(
                MenubarSegment(text: UsageFormatting.dollarsFromCentsInt(onDemandMenubarCents))
            )
        }

        return .visible(segments)
    }

    private static func labeledPercentText(label: String, percent: Double, showUpArrow: Bool) -> String {
        let rounded = Int(percent.rounded())
        return "\(label): \(rounded)%\(showUpArrow ? "↑" : "")"
    }
}

struct UsageViewModel {
    struct PoolSection {
        let id: String
        let title: String
        let subtitle: String?
        let percentUsed: Double
        let resetDate: Date?
        let usedCents: Double
        let estimatedPoolCents: Double?
        let planLimitCents: Double?
        let rows: [ModelUsageRow]
        let aggregationsMissing: Bool
        let showsEmptyPlaceholder: Bool
        let missingBreakdownMessage: String

        var leftCaption: String {
            UsageFormatting.percentUsedCaption(percentUsed)
        }

        var rightCaption: String {
            UsageFormatting.resetCaption(resetDate)
        }

        var meterContent: UsageMeterContent {
            UsageMeterContent(
                title: title,
                subtitle: subtitle,
                percentUsed: UsageFormatting.normalizedPercentUsed(percentUsed),
                leftCaption: leftCaption,
                rightCaption: rightCaption
            )
        }

        var meterLevel: UsageMeterLevel {
            UsageMeterLevel.from(percentUsed: percentUsed)
        }

        var breakdownStatus: String {
            if aggregationsMissing { return "unavailable" }
            if rows.isEmpty { return "empty" }
            return "ok"
        }
    }

    let headerTitle: String
    let membershipType: String
    let cycleLine: String?
    let billingCycleStart: String?
    let billingCycleEnd: String?
    let totalTitle: String
    let totalUsedCents: Double
    let cursorPercent: Double
    let apiPercent: Double
    let totalPercent: Double
    let botPercent: Double?
    let cursor: PoolSection
    let api: PoolSection
    let bot: PoolSection?
    let billing: UsageFormatting.BillingSnapshot
    let lastUpdatedLine: String?
    let fetchedAt: Date?
    let menubar: MenubarPresentation
    let dashboardURL: String

    var sections: [PoolSection] {
        if let bot {
            return [cursor, api, bot]
        }
        return [cursor, api]
    }
}

enum UsageScreen {
    case unauthenticated(message: String)
    case loading
    case ready(UsageViewModel)

    static func make(
        from state: UsageDisplayState,
        includePollingHint: Bool,
        missingBreakdownMessage: String = "Loading breakdown…"
    ) -> UsageScreen {
        if !state.isAuthenticated {
            return .unauthenticated(
                message: state.authErrorMessage ?? "Couldn't authenticate — is Cursor signed in?"
            )
        }
        guard let summary = state.summary else {
            return .loading
        }
        return .ready(
            UsageViewModel.make(
                from: state,
                summary: summary,
                includePollingHint: includePollingHint,
                missingBreakdownMessage: missingBreakdownMessage
            )
        )
    }
}

extension UsageViewModel {
    static func make(
        from state: UsageDisplayState,
        summary: UsageSummaryResponse,
        includePollingHint: Bool,
        missingBreakdownMessage: String
    ) -> UsageViewModel {
        let membership = summary.membershipType ?? "unknown"

        var cycleLine: String?
        if let start = summary.billingCycleStartDate, let end = summary.billingCycleEndDate {
            cycleLine = "Cycle: \(UsageFormatting.formatCycleDate(start)) – \(UsageFormatting.formatCycleDate(end))"
        }

        let aggregations = state.aggregations?.aggregations
        let weeklyAggregations = state.weeklyAggregations?.aggregations
        let cursorUsedCents = ModelUsageBreakdown.centsUsed(in: aggregations, kind: .cursor)
        let apiUsedCents = ModelUsageBreakdown.centsUsed(in: aggregations, kind: .api)
        let hasWeeklyBotWindow = weeklyAggregations != nil
        let botSource = weeklyAggregations ?? aggregations
        let botUsedCents = ModelUsageBreakdown.centsUsed(in: botSource, kind: .bot)
        let botRows = ModelUsageBreakdown.rows(from: botSource, kind: .bot)
        let totalUsedCents = cursorUsedCents + apiUsedCents
        let statedApiPoolCents = PlanIncludedBudgets.otherModelsCents(
            membershipType: summary.membershipType,
            planInfo: state.planInfo
        )
        let aggregationsMissing = state.aggregations?.aggregations == nil

        let cursorPercent = UsageFormatting.normalizedPercentUsed(summary.autoPercentUsed)
        let apiPercent = UsageFormatting.normalizedPercentUsed(summary.apiPercentUsed)
        let totalPercent = UsageFormatting.normalizedPercentUsed(summary.totalPercentUsed)
        let botPercent = state.sandUsage?.usagePercent

        let cursor = PoolSection(
            id: "cursor",
            title: UsageFormatting.poolSectionHeading(
                prefix: "Cursor",
                usedCents: cursorUsedCents,
                percentUsed: summary.autoPercentUsed
            ),
            subtitle: nil,
            percentUsed: cursorPercent,
            resetDate: summary.billingCycleEndDate,
            usedCents: cursorUsedCents,
            estimatedPoolCents: UsageFormatting.predictedPoolCents(
                usedCents: cursorUsedCents,
                percentUsed: cursorPercent
            ),
            planLimitCents: nil,
            rows: ModelUsageBreakdown.rows(from: aggregations, kind: .cursor),
            aggregationsMissing: aggregationsMissing,
            showsEmptyPlaceholder: true,
            missingBreakdownMessage: missingBreakdownMessage
        )

        let api = PoolSection(
            id: "api",
            title: UsageFormatting.poolSectionHeading(
                prefix: "API",
                usedCents: apiUsedCents,
                percentUsed: summary.apiPercentUsed
            ),
            subtitle: UsageFormatting.planLimitLine(statedPoolCents: statedApiPoolCents),
            percentUsed: apiPercent,
            resetDate: summary.billingCycleEndDate,
            usedCents: apiUsedCents,
            estimatedPoolCents: UsageFormatting.predictedPoolCents(
                usedCents: apiUsedCents,
                percentUsed: apiPercent
            ),
            planLimitCents: {
                guard let cents = statedApiPoolCents, cents > 0 else { return nil }
                return cents
            }(),
            rows: ModelUsageBreakdown.rows(from: aggregations, kind: .api),
            aggregationsMissing: aggregationsMissing,
            showsEmptyPlaceholder: true,
            missingBreakdownMessage: missingBreakdownMessage
        )

        var bot: PoolSection?
        if state.sandUsage?.showsMenubarPercent == true || !botRows.isEmpty {
            let botAggregationsMissing =
                state.aggregations?.aggregations == nil
                && state.weeklyAggregations?.aggregations == nil
            let normalizedBotPercent = UsageFormatting.normalizedPercentUsed(botPercent)
            bot = PoolSection(
                id: "bot",
                title: UsageFormatting.poolSectionHeading(
                    prefix: "Bot",
                    usedCents: botUsedCents,
                    percentUsed: botPercent,
                    estimatePool: hasWeeklyBotWindow
                ),
                subtitle: UsageFormatting.weeklyWindowLine(
                    start: state.sandUsage?.periodStartDate,
                    reset: state.sandUsage?.resetDate
                ),
                percentUsed: normalizedBotPercent,
                resetDate: state.sandUsage?.resetDate,
                usedCents: botUsedCents,
                estimatedPoolCents: hasWeeklyBotWindow
                    ? UsageFormatting.predictedPoolCents(
                        usedCents: botUsedCents,
                        percentUsed: normalizedBotPercent
                    )
                    : nil,
                planLimitCents: nil,
                rows: botRows,
                aggregationsMissing: botAggregationsMissing,
                showsEmptyPlaceholder: false,
                missingBreakdownMessage: missingBreakdownMessage
            )
        }

        var lastUpdatedLine: String?
        if let lastUpdated = state.lastUpdated {
            let time = UsageFormatting.formatTime(lastUpdated)
            lastUpdatedLine = includePollingHint
                ? "Refreshes every \(AppInfo.summaryPollSeconds)s · Last updated: \(time)"
                : "Fetched at: \(time)"
        }

        return UsageViewModel(
            headerTitle: "Cursor Usage — \(membership)",
            membershipType: membership,
            cycleLine: cycleLine,
            billingCycleStart: summary.billingCycleStart,
            billingCycleEnd: summary.billingCycleEnd,
            totalTitle: UsageFormatting.poolSectionTitle(
                prefix: "Total",
                usedCents: totalUsedCents,
                percentUsed: summary.totalPercentUsed
            ),
            totalUsedCents: totalUsedCents,
            cursorPercent: cursorPercent,
            apiPercent: apiPercent,
            totalPercent: totalPercent,
            botPercent: botPercent,
            cursor: cursor,
            api: api,
            bot: bot,
            billing: UsageFormatting.BillingSnapshot.make(
                summary: summary,
                planInfo: state.planInfo,
                hardLimit: state.hardLimit
            ),
            lastUpdatedLine: lastUpdatedLine,
            fetchedAt: state.lastUpdated,
            menubar: MenubarPresentation.make(from: state),
            dashboardURL: AppInfo.dashboardURL
        )
    }
}
