import AppKit

struct UsageDisplayState {
    var summary: UsageSummaryResponse?
    var aggregations: AggregatedUsageResponse?
    var lastUpdated: Date?
    var isAuthenticated: Bool = true
    var authErrorMessage: String?
    var apiPercentIncreased: Bool = false
    var autoPercentIncreased: Bool = false
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
        title.append(
            formattedLabeledPercentSegment(
                label: "Cursor",
                percent: autoPercent,
                showUpArrow: displayState.autoPercentIncreased
            )
        )
        title.append(NSAttributedString(string: " · ", attributes: baseAttributes()))
        title.append(
            formattedLabeledPercentSegment(
                label: "API",
                percent: apiPercent,
                showUpArrow: displayState.apiPercentIncreased
            )
        )

        if onDemandMenubarCents > 0 {
            title.append(NSAttributedString(string: " · ", attributes: baseAttributes()))
            title.append(
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
        let cursorUsedCents = centsUsed(in: aggregations, tier: 2)
        let apiUsedCents = centsUsed(in: aggregations, tier: 1)
        let totalUsedCents = cursorUsedCents + apiUsedCents

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
            tier: 2
        )

        menu.addItem(.separator())

        addModelSection(
            to: menu,
            titlePrefix: "API",
            percent: summary.apiPercentUsed,
            usedCents: apiUsedCents,
            tier: 1
        )


        menu.addItem(.separator())
        addOnDemandSection(to: menu, summary: summary)
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
        tier: Int
    ) {
        addInfoItem(
            to: menu,
            title: UsageFormatting.poolSectionTitle(
                prefix: titlePrefix,
                usedCents: usedCents,
                percentUsed: percent
            ),
            style: .section,
            indentationLevel: 0
        )

        guard let aggregations = displayState.aggregations?.aggregations else {
            addInfoItem(to: menu, title: "Loading breakdown…", style: .secondary, indentationLevel: 1)
            return
        }

        let models = aggregations
            .filter { $0.tier == tier }
            .filter { ($0.totalCents ?? 0) > 0 || $0.totalTokens > 0 }
            .sorted {
                ($0.totalCents ?? 0) > ($1.totalCents ?? 0)
            }

        if models.isEmpty {
            addInfoItem(to: menu, title: "No usage this cycle", style: .secondary, indentationLevel: 1)
            return
        }

        for model in models {
            let intent = model.modelIntent ?? "unknown"
            let tokens = UsageFormatting.compactTokenCount(model.totalTokens)
            let dollars = UsageFormatting.dollarsFromCents(model.totalCents)
            addInfoItem(
                to: menu,
                title: "\(intent)    \(tokens) tok · \(dollars)",
                style: .body,
                indentationLevel: 1
            )
        }
    }

    private func centsUsed(
        in aggregations: [AggregatedUsageResponse.Aggregation]?,
        tier: Int
    ) -> Double {
        guard let aggregations else { return 0 }
        return aggregations
            .filter { $0.tier == tier }
            .reduce(0) { $0 + ($1.totalCents ?? 0) }
    }

    private func addOnDemandSection(to menu: NSMenu, summary: UsageSummaryResponse) {
        let onDemandUsed = summary.individualUsage?.onDemand?.used ?? 0
        let teamUsed = summary.teamUsage?.onDemand?.used
        let teamLimit = summary.teamUsage?.onDemand?.limit
        let breakdown = UsageFormatting.OnDemandBreakdown(
            individualUsedCents: onDemandUsed,
            teamUsedCents: teamUsed,
            teamLimitCents: teamLimit
        )
        let highlightOnDemand = onDemandUsed > 0 || (teamUsed ?? 0) > 0
        let valueStyle: InfoItemStyle = highlightOnDemand ? .alert : .body

        addInfoItem(
            to: menu,
            title: breakdown.headerLine,
            style: highlightOnDemand ? .alert : .section
        )

        // Always nest the split when a team budget exists, even if you are at $0.
        if breakdown.hasTeamBudget {
            addInfoItem(
                to: menu,
                title: breakdown.youLine,
                style: valueStyle,
                indentationLevel: 1
            )
            if let everyoneElseLine = breakdown.everyoneElseLine {
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
