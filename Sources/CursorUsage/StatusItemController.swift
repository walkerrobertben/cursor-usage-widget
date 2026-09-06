import AppKit

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

final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private var displayState = UsageDisplayState()
    var onRefreshRequested: (() -> Void)?

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        statusItem.menu = NSMenu()
        statusItem.menu?.delegate = self
        updateStatusTitle()
    }

    func apply(state: UsageDisplayState) {
        displayState = state
        updateStatusTitle()
        statusItem.menu?.update()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu(menu)
    }

    private func updateStatusTitle() {
        guard let button = statusItem.button else { return }

        if !displayState.isAuthenticated {
            statusItem.isVisible = true
            button.attributedTitle = NSAttributedString(string: "⚠ Cursor")
            return
        }

        guard let summary = displayState.summary else {
            // Stay invisible until the first successful fetch.
            button.attributedTitle = NSAttributedString(string: "")
            statusItem.isVisible = false
            return
        }

        statusItem.isVisible = true

        let apiPercent = summary.apiPercentUsed ?? 0
        let autoPercent = summary.autoPercentUsed ?? 0
        let individualOnDemand = summary.individualUsage?.onDemand?.used ?? 0
        let teamOnDemand = summary.teamUsage?.onDemand?.used
        // Prefer team total in the menubar when a team budget exists.
        let onDemandMenubarCents = teamOnDemand ?? individualOnDemand

        let title = NSMutableAttributedString()
        func appendSegment(_ segment: NSAttributedString) {
            if title.length > 0 {
                title.append(NSAttributedString(string: " · ", attributes: baseAttributes()))
            }
            title.append(segment)
        }

        appendSegment(
            formattedLabeledPercentSegment(
                label: "Cursor",
                percent: autoPercent,
                showUpArrow: displayState.autoPercentIncreased
            )
        )

        if Int(apiPercent.rounded()) > 0 {
            appendSegment(
                formattedLabeledPercentSegment(
                    label: "API",
                    percent: apiPercent,
                    showUpArrow: displayState.apiPercentIncreased
                )
            )
        }

        if let botPercent = displayState.sandUsage?.usagePercent,
           displayState.sandUsage?.showsMenubarPercent == true,
           Int(botPercent.rounded()) > 0
        {
            appendSegment(
                formattedLabeledPercentSegment(
                    label: "Bot",
                    percent: botPercent,
                    showUpArrow: displayState.botPercentIncreased
                )
            )
        }

        if onDemandMenubarCents > 0 {
            appendSegment(
                NSAttributedString(
                    string: UsageFormatting.dollarsFromCentsInt(onDemandMenubarCents),
                    attributes: baseAttributes()
                )
            )
        }

        button.attributedTitle = title
    }

    private func formattedLabeledPercentSegment(
        label: String,
        percent: Double,
        showUpArrow: Bool
    ) -> NSAttributedString {
        let rounded = Int(percent.rounded())
        let text = "\(label): \(rounded)%\(showUpArrow ? "↑" : "")"
        return NSAttributedString(string: text, attributes: baseAttributes())
    }

    private func baseAttributes(color: NSColor = .labelColor) -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: color,
        ]
    }

    private func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        if !displayState.isAuthenticated {
            addInfoItem(
                to: menu,
                title: displayState.authErrorMessage ?? "Couldn't authenticate — is Cursor signed in?",
                style: .emphasis
            )
            addCommonActions(to: menu)
            return
        }

        guard let summary = displayState.summary else {
            addInfoItem(to: menu, title: "Loading…", style: .secondary)
            addCommonActions(to: menu)
            return
        }

        let membership = summary.membershipType ?? "unknown"
        addInfoItem(to: menu, title: "Cursor Usage — \(membership)", style: .header)

        if let start = summary.billingCycleStartDate, let end = summary.billingCycleEndDate {
            addInfoItem(
                to: menu,
                title: "Cycle: \(UsageFormatting.formatCycleDate(start)) – \(UsageFormatting.formatCycleDate(end))",
                style: .secondary
            )
        }

        let aggregations = displayState.aggregations?.aggregations
        let weeklyAggregations = displayState.weeklyAggregations?.aggregations
        let cursorUsedCents = ModelUsageBreakdown.centsUsed(in: aggregations, kind: .cursor)
        let apiUsedCents = ModelUsageBreakdown.centsUsed(in: aggregations, kind: .api)
        let hasWeeklyBotWindow = weeklyAggregations != nil
        let botSource = weeklyAggregations ?? aggregations
        let botUsedCents = ModelUsageBreakdown.centsUsed(in: botSource, kind: .bot)
        let botRows = ModelUsageBreakdown.rows(from: botSource, kind: .bot)
        let totalUsedCents = cursorUsedCents + apiUsedCents
        let statedApiPoolCents = PlanIncludedBudgets.otherModelsCents(
            membershipType: summary.membershipType,
            planInfo: displayState.planInfo
        )

        addInfoItem(
            to: menu,
            title: UsageFormatting.poolSectionTitle(
                prefix: "Total",
                usedCents: totalUsedCents,
                percentUsed: summary.totalPercentUsed
            ),
            style: .body
        )

        menu.addItem(.separator())

        addModelSection(
            to: menu,
            titlePrefix: "Cursor",
            percent: summary.autoPercentUsed,
            usedCents: cursorUsedCents,
            kind: .cursor,
            resetDate: summary.billingCycleEndDate
        )

        menu.addItem(.separator())

        addModelSection(
            to: menu,
            titlePrefix: "API",
            percent: summary.apiPercentUsed,
            usedCents: apiUsedCents,
            kind: .api,
            statedPoolCents: statedApiPoolCents,
            resetDate: summary.billingCycleEndDate
        )

        if displayState.sandUsage?.showsMenubarPercent == true || !botRows.isEmpty {
            menu.addItem(.separator())
            addBotSection(
                to: menu,
                sand: displayState.sandUsage,
                rows: botRows,
                usedCents: botUsedCents,
                estimatePool: hasWeeklyBotWindow
            )
        }

        menu.addItem(.separator())
        addBillingSection(to: menu, summary: summary)
        menu.addItem(.separator())

        if let lastUpdated = displayState.lastUpdated {
            addInfoItem(
                to: menu,
                title: "Refreshes every 30s · Last updated: \(UsageFormatting.formatTime(lastUpdated))",
                style: .secondary
            )
        }

        addCommonActions(to: menu)
    }

    private func addModelSection(
        to menu: NSMenu,
        titlePrefix: String,
        percent: Double?,
        usedCents: Double,
        kind: ModelUsageKind,
        statedPoolCents: Double? = nil,
        resetDate: Date? = nil
    ) {
        addUsageMeter(
            to: menu,
            title: UsageFormatting.poolSectionHeading(
                prefix: titlePrefix,
                usedCents: usedCents,
                percentUsed: percent
            ),
            subtitle: UsageFormatting.planLimitLine(statedPoolCents: statedPoolCents),
            percentUsed: percent,
            resetDate: resetDate
        )

        guard displayState.aggregations?.aggregations != nil else {
            addInfoItem(to: menu, title: "Loading breakdown…", style: .secondary, indentationLevel: 1)
            return
        }

        let models = ModelUsageBreakdown.rows(
            from: displayState.aggregations?.aggregations,
            kind: kind
        )
        addModelRows(models, to: menu)
    }

    private func addBotSection(
        to menu: NSMenu,
        sand: SandUsageResponse?,
        rows: [ModelUsageRow],
        usedCents: Double,
        estimatePool: Bool
    ) {
        addUsageMeter(
            to: menu,
            title: UsageFormatting.poolSectionHeading(
                prefix: "Bot",
                usedCents: usedCents,
                percentUsed: sand?.usagePercent,
                estimatePool: estimatePool
            ),
            subtitle: UsageFormatting.weeklyWindowLine(start: sand?.periodStartDate, reset: sand?.resetDate),
            percentUsed: sand?.usagePercent,
            resetDate: sand?.resetDate
        )

        if displayState.aggregations?.aggregations == nil, displayState.weeklyAggregations?.aggregations == nil {
            addInfoItem(to: menu, title: "Loading breakdown…", style: .secondary, indentationLevel: 1)
            return
        }

        if !rows.isEmpty {
            addModelRows(rows, to: menu)
        }
    }

    private func addModelRows(_ models: [ModelUsageRow], to menu: NSMenu) {
        if models.isEmpty {
            addInfoItem(to: menu, title: "No usage this cycle", style: .secondary, indentationLevel: 1)
            return
        }

        for model in models {
            let item = NSMenuItem()
            item.view = UsageModelRowView(
                content: UsageModelRowContent(
                    name: model.name,
                    tokens: UsageFormatting.tokensColumnText(model.tokens),
                    cost: UsageFormatting.dollarsFromCents(model.cents)
                )
            )
            item.isEnabled = true
            menu.addItem(item)
        }
    }

    private func addBillingSection(to menu: NSMenu, summary: UsageSummaryResponse) {
        let billing = UsageFormatting.BillingSnapshot.make(
            summary: summary,
            planInfo: displayState.planInfo,
            hardLimit: displayState.hardLimit
        )
        let highlightOnDemand = billing.isOnDemandActive
        let valueStyle: InfoItemStyle = highlightOnDemand ? .alert : .body

        if let totalBillLine = billing.totalBillLine {
            addInfoItem(to: menu, title: totalBillLine, style: .section)
        }
        if let totalBillDetailLine = billing.totalBillDetailLine {
            addInfoItem(
                to: menu,
                title: totalBillDetailLine,
                style: .secondary,
                indentationLevel: 1
            )
        }

        addInfoItem(
            to: menu,
            title: billing.onDemandHeaderLine,
            style: highlightOnDemand ? .alert : .section
        )

        if billing.hasTeamBudget {
            addInfoItem(
                to: menu,
                title: billing.youLine,
                style: valueStyle,
                indentationLevel: 1
            )
            if let everyoneElseLine = billing.everyoneElseLine {
                addInfoItem(
                    to: menu,
                    title: everyoneElseLine,
                    style: valueStyle,
                    indentationLevel: 1
                )
            }
        }
    }

    private enum InfoItemStyle {
        case header
        case section
        case body
        case secondary
        case emphasis
        case alert
    }

    private func addUsageMeter(
        to menu: NSMenu,
        title: String,
        subtitle: String?,
        percentUsed: Double?,
        resetDate: Date?
    ) {
        let content = UsageMeterContent(
            title: title,
            subtitle: subtitle,
            percentUsed: UsageFormatting.normalizedPercentUsed(percentUsed),
            leftCaption: UsageFormatting.percentUsedCaption(percentUsed),
            rightCaption: UsageFormatting.resetCaption(resetDate)
        )
        let item = NSMenuItem()
        item.view = UsageMeterView(content: content)
        item.isEnabled = true
        menu.addItem(item)
    }

    private func addInfoItem(
        to menu: NSMenu,
        title: String,
        style: InfoItemStyle,
        indentationLevel: Int = 0
    ) {
        let item = NSMenuItem(title: "", action: #selector(ignoreMenuSelection), keyEquivalent: "")
        item.attributedTitle = NSAttributedString(
            string: title,
            attributes: infoItemAttributes(for: style)
        )
        item.target = self
        item.isEnabled = true
        item.indentationLevel = indentationLevel
        menu.addItem(item)
    }

    private func infoItemAttributes(for style: InfoItemStyle) -> [NSAttributedString.Key: Any] {
        switch style {
        case .header:
            return [
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: NSColor.labelColor,
            ]
        case .section:
            return [
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: NSColor.labelColor,
            ]
        case .body:
            return [
                .font: NSFont.systemFont(ofSize: 13, weight: .regular),
                .foregroundColor: NSColor.labelColor,
            ]
        case .secondary:
            return [
                .font: NSFont.systemFont(ofSize: 12, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        case .emphasis:
            return [
                .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                .foregroundColor: NSColor.systemOrange,
            ]
        case .alert:
            return [
                .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                .foregroundColor: NSColor.systemRed,
            ]
        }
    }

    private func addCommonActions(to menu: NSMenu) {
        let refreshItem = NSMenuItem(title: "Refresh Now", action: #selector(refreshNow), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        let dashboardItem = NSMenuItem(title: "Open Dashboard…", action: #selector(openDashboard), keyEquivalent: "")
        dashboardItem.target = self
        menu.addItem(dashboardItem)

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    @objc private func ignoreMenuSelection() {}

    @objc private func refreshNow() {
        onRefreshRequested?()
    }

    @objc private func openDashboard() {
        if let url = URL(string: "https://cursor.com/dashboard?tab=usage") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
