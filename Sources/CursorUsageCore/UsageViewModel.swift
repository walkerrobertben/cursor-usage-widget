import Foundation

public struct UsageDisplayState: Equatable, Sendable {
    public var summary: UsageSummaryResponse?
    public var aggregations: AggregatedUsageResponse?
    public var weeklyAggregations: AggregatedUsageResponse?
    public var sandUsage: SandUsageResponse?
    public var planInfo: PlanInfoResponse?
    public var hardLimit: HardLimitResponse?
    public var lastUpdated: Date?
    public var isAuthenticated: Bool
    public var authErrorMessage: String?
    public var apiPercentIncreased: Bool
    public var autoPercentIncreased: Bool
    public var botPercentIncreased: Bool

    public init(
        summary: UsageSummaryResponse? = nil,
        aggregations: AggregatedUsageResponse? = nil,
        weeklyAggregations: AggregatedUsageResponse? = nil,
        sandUsage: SandUsageResponse? = nil,
        planInfo: PlanInfoResponse? = nil,
        hardLimit: HardLimitResponse? = nil,
        lastUpdated: Date? = nil,
        isAuthenticated: Bool = true,
        authErrorMessage: String? = nil,
        apiPercentIncreased: Bool = false,
        autoPercentIncreased: Bool = false,
        botPercentIncreased: Bool = false
    ) {
        self.summary = summary
        self.aggregations = aggregations
        self.weeklyAggregations = weeklyAggregations
        self.sandUsage = sandUsage
        self.planInfo = planInfo
        self.hardLimit = hardLimit
        self.lastUpdated = lastUpdated
        self.isAuthenticated = isAuthenticated
        self.authErrorMessage = authErrorMessage
        self.apiPercentIncreased = apiPercentIncreased
        self.autoPercentIncreased = autoPercentIncreased
        self.botPercentIncreased = botPercentIncreased
    }
}

public struct UsageMeterContent: Equatable, Sendable {
    public var title: String
    public var subtitle: String?
    public var percentUsed: Double
    public var leftCaption: String
    public var rightCaption: String

    public init(
        title: String,
        subtitle: String?,
        percentUsed: Double,
        leftCaption: String,
        rightCaption: String
    ) {
        self.title = title
        self.subtitle = subtitle
        self.percentUsed = percentUsed
        self.leftCaption = leftCaption
        self.rightCaption = rightCaption
    }
}

public struct UsageModelRowContent: Equatable, Sendable {
    public var name: String
    public var tokens: String
    public var cost: String

    public init(name: String, tokens: String, cost: String) {
        self.name = name
        self.tokens = tokens
        self.cost = cost
    }
}

public enum UsageMeterLevel: String, Equatable, Sendable {
    case green
    case yellow
    case orange
    case red

    public static func from(percentUsed: Double) -> UsageMeterLevel {
        let percent = UsageFormatting.normalizedPercentUsed(percentUsed)
        if percent >= 100 { return .red }
        if percent >= 90 { return .orange }
        if percent >= 70 { return .yellow }
        return .green
    }
}

public struct MenubarSegment: Equatable, Sendable {
    public var text: String

    public init(text: String) {
        self.text = text
    }
}

public enum MenubarPresentation: Equatable, Sendable {
    case hidden
    case warning
    case visible([MenubarSegment])

    public var compactLine: String? {
        switch self {
        case .hidden:
            return nil
        case .warning:
            return "⚠ Cursor"
        case let .visible(segments):
            return segments.map(\.text).joined(separator: " · ")
        }
    }

    public static func make(from state: UsageDisplayState) -> MenubarPresentation {
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

public struct UsageViewModel: Equatable, Sendable {
    public struct PoolSection: Equatable, Sendable {
        public let id: String
        public let title: String
        public let subtitle: String?
        public let percentUsed: Double
        public let resetDate: Date?
        public let usedCents: Double
        public let estimatedPoolCents: Double?
        public let planLimitCents: Double?
        public let rows: [ModelUsageRow]
        public let aggregationsMissing: Bool
        public let showsEmptyPlaceholder: Bool
        public let missingBreakdownMessage: String

        public var leftCaption: String {
            UsageFormatting.percentUsedCaption(percentUsed)
        }

        public func rightCaption(calendar: DisplayCalendar) -> String {
            UsageFormatting.resetCaption(resetDate, calendar: calendar)
        }

        public func meterContent(calendar: DisplayCalendar) -> UsageMeterContent {
            UsageMeterContent(
                title: title,
                subtitle: subtitle,
                percentUsed: UsageFormatting.normalizedPercentUsed(percentUsed),
                leftCaption: leftCaption,
                rightCaption: rightCaption(calendar: calendar)
            )
        }

        public var meterLevel: UsageMeterLevel {
            UsageMeterLevel.from(percentUsed: percentUsed)
        }
    }

    public let headerTitle: String
    public let membershipType: String
    public let planDisplayName: String
    public let cycleLine: String?
    public let billingCycleStart: String?
    public let billingCycleEnd: String?
    public let totalTitle: String
    public let totalUsedCents: Double
    public let cursorPercent: Double
    public let apiPercent: Double
    public let totalPercent: Double
    public let botPercent: Double?
    public let cursor: PoolSection
    public let api: PoolSection
    public let bot: PoolSection?
    public let billing: UsageFormatting.BillingSnapshot
    public let billingResetDate: Date?
    public let lastUpdatedLine: String?
    public let fetchedAt: Date?
    public let menubar: MenubarPresentation
    public let dashboardURL: String

    public var sections: [PoolSection] {
        if let bot {
            return [cursor, api, bot]
        }
        return [cursor, api]
    }
}

public enum UsageScreen: Equatable, Sendable {
    case unauthenticated(message: String)
    case loading
    case ready(UsageViewModel)

    public static func make(
        from state: UsageDisplayState,
        calendar: DisplayCalendar = .current,
        includePollingHint: Bool = true,
        missingBreakdownMessage: String = "Loading breakdown…"
    ) -> UsageScreen {
        if !state.isAuthenticated {
            return .unauthenticated(
                message: state.authErrorMessage ?? MenuPresentation.authFallbackMessage
            )
        }
        guard let summary = state.summary else {
            return .loading
        }
        return .ready(
            UsageViewModel.make(
                from: state,
                summary: summary,
                calendar: calendar,
                includePollingHint: includePollingHint,
                missingBreakdownMessage: missingBreakdownMessage
            )
        )
    }
}

extension UsageViewModel {
    public static func make(
        from state: UsageDisplayState,
        summary: UsageSummaryResponse,
        calendar: DisplayCalendar = .current,
        includePollingHint: Bool = true,
        missingBreakdownMessage: String = "Loading breakdown…"
    ) -> UsageViewModel {
        let planDisplayName = PlanDisplay.name(summary: summary, planInfo: state.planInfo)
        let membership = summary.membershipType ?? "unknown"

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
                    reset: state.sandUsage?.resetDate,
                    calendar: calendar
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
            let time = UsageFormatting.formatTime(lastUpdated, calendar: calendar)
            lastUpdatedLine = includePollingHint
                ? "Refreshes every \(AppInfo.summaryPollSeconds)s · Last updated: \(time)"
                : "Fetched at: \(time)"
        }

        return UsageViewModel(
            headerTitle: "Cursor Usage — \(planDisplayName)",
            membershipType: membership,
            planDisplayName: planDisplayName,
            cycleLine: UsageFormatting.cycleLine(
                start: summary.billingCycleStartDate,
                end: summary.billingCycleEndDate,
                calendar: calendar
            ),
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
            billingResetDate: summary.billingCycleEndDate,
            lastUpdatedLine: lastUpdatedLine,
            fetchedAt: state.lastUpdated,
            menubar: MenubarPresentation.make(from: state),
            dashboardURL: AppInfo.dashboardURL
        )
    }
}
