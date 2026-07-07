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
            button.attributedTitle = NSAttributedString(string: "⚠ Cursor")
            return
        }

        guard let summary = displayState.summary else {
            button.attributedTitle = NSAttributedString(string: "…")
            return
        }

        let apiPercent = summary.apiPercentUsed ?? 0
        let autoPercent = summary.autoPercentUsed ?? 0
        let onDemandUsed = summary.individualUsage?.onDemand?.used ?? 0

        let title = NSMutableAttributedString()
        title.append(
            formattedPercentSegment(
                percent: apiPercent,
                showUpArrow: displayState.apiPercentIncreased,
                warningThresholds: true
            )
        )
        title.append(NSAttributedString(string: " · ", attributes: baseAttributes()))
        title.append(
            formattedPercentSegment(
                percent: autoPercent,
                showUpArrow: displayState.autoPercentIncreased,
                warningThresholds: false
            )
        )

        if onDemandUsed > 0 {
            title.append(NSAttributedString(string: " · ", attributes: baseAttributes()))
            title.append(
                NSAttributedString(
                    string: UsageFormatting.dollarsFromCentsInt(onDemandUsed),
                    attributes: baseAttributes(color: .systemRed)
                )
            )
        }

        button.attributedTitle = title
    }

    private func formattedPercentSegment(
        percent: Double,
        showUpArrow: Bool,
        warningThresholds: Bool
    ) -> NSAttributedString {
        let rounded = Int(percent.rounded())
        var color: NSColor = .labelColor
        if warningThresholds {
            if percent >= 90 {
                color = .systemRed
            } else if percent >= 75 {
                color = .systemOrange
            }
        }

        let text = "\(rounded)%\(showUpArrow ? "↑" : "")"
        return NSAttributedString(string: text, attributes: baseAttributes(color: color))
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
            let errorItem = NSMenuItem(
                title: displayState.authErrorMessage ?? "Couldn't authenticate — is Cursor signed in?",
                action: nil,
                keyEquivalent: ""
            )
            errorItem.isEnabled = false
            menu.addItem(errorItem)
            addCommonActions(to: menu)
            return
        }

        guard let summary = displayState.summary else {
            let loadingItem = NSMenuItem(title: "Loading…", action: nil, keyEquivalent: "")
            loadingItem.isEnabled = false
            menu.addItem(loadingItem)
            addCommonActions(to: menu)
            return
        }

        let membership = summary.membershipType ?? "unknown"
        let header = NSMenuItem(title: "Cursor Usage — \(membership)", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        if let start = summary.billingCycleStartDate, let end = summary.billingCycleEndDate {
            let cycleItem = NSMenuItem(
                title: "Cycle: \(UsageFormatting.formatCycleDate(start)) – \(UsageFormatting.formatCycleDate(end))",
                action: nil,
                keyEquivalent: ""
            )
            cycleItem.isEnabled = false
            menu.addItem(cycleItem)
        }

        if let totalPercent = summary.totalPercentUsed {
            let totalItem = NSMenuItem(
                title: String(format: "Total included: %.1f%%", totalPercent),
                action: nil,
                keyEquivalent: ""
            )
            totalItem.isEnabled = false
            menu.addItem(totalItem)
        }

        menu.addItem(.separator())

        addModelSection(
            to: menu,
            titlePrefix: "API",
            percent: summary.apiPercentUsed,
            tier: 1
        )

        menu.addItem(.separator())

        addModelSection(
            to: menu,
            titlePrefix: "Auto + Composer",
            percent: summary.autoPercentUsed,
            tier: 2
        )

        menu.addItem(.separator())
        addOnDemandSection(to: menu, summary: summary)
        menu.addItem(.separator())

        if let lastUpdated = displayState.lastUpdated {
            let updatedItem = NSMenuItem(
                title: "Last updated: \(UsageFormatting.formatTime(lastUpdated))",
                action: nil,
                keyEquivalent: ""
            )
            updatedItem.isEnabled = false
            menu.addItem(updatedItem)
        }

        addCommonActions(to: menu)
    }

    private func addModelSection(
        to menu: NSMenu,
        titlePrefix: String,
        percent: Double?,
        tier: Int
    ) {
        let sectionTitle = String(format: "%@ — %.1f%%", titlePrefix, percent ?? 0)
        let sectionItem = NSMenuItem(title: sectionTitle, action: nil, keyEquivalent: "")
        sectionItem.isEnabled = false
        menu.addItem(sectionItem)

        guard let aggregations = displayState.aggregations?.aggregations else {
            let loadingItem = NSMenuItem(title: "Loading breakdown…", action: nil, keyEquivalent: "")
            loadingItem.isEnabled = false
            loadingItem.indentationLevel = 1
            menu.addItem(loadingItem)
            return
        }

        let models = aggregations
            .filter { $0.tier == tier }
            .sorted {
                ($0.totalCents ?? 0) > ($1.totalCents ?? 0)
            }

        if models.isEmpty {
            let emptyItem = NSMenuItem(title: "No usage this cycle", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            emptyItem.indentationLevel = 1
            menu.addItem(emptyItem)
            return
        }

        for model in models {
            let intent = model.modelIntent ?? "unknown"
            let tokens = UsageFormatting.compactTokenCount(model.totalTokens)
            let dollars = UsageFormatting.dollarsFromCents(model.totalCents)
            let row = NSMenuItem(
                title: "\(intent)    \(tokens) tok · \(dollars)",
                action: nil,
                keyEquivalent: ""
            )
            row.isEnabled = false
            row.indentationLevel = 1
            menu.addItem(row)
        }
    }

    private func addOnDemandSection(to menu: NSMenu, summary: UsageSummaryResponse) {
        let plan = summary.individualUsage?.plan
        let used = plan?.used ?? 0
        let limit = plan?.limit ?? 0
        let bonus = plan?.breakdown?.bonus ?? 0

        let includedItem = NSMenuItem(
            title: "Included plan: \(formatInteger(used)) / \(formatInteger(limit)) used (+\(formatInteger(bonus)) bonus)",
            action: nil,
            keyEquivalent: ""
        )
        includedItem.isEnabled = false
        menu.addItem(includedItem)

        let onDemandUsed = summary.individualUsage?.onDemand?.used ?? 0
        let teamLimit = summary.teamUsage?.onDemand?.limit
        var onDemandTitle = "On-demand: \(UsageFormatting.dollarsFromCentsInt(onDemandUsed))"
        if let teamLimit {
            onDemandTitle += " of \(UsageFormatting.dollarsFromCentsInt(teamLimit)) team budget"
        }

        let onDemandItem = NSMenuItem(title: onDemandTitle, action: nil, keyEquivalent: "")
        onDemandItem.isEnabled = false
        if onDemandUsed > 0 {
            onDemandItem.attributedTitle = NSAttributedString(
                string: onDemandTitle,
                attributes: [.foregroundColor: NSColor.systemRed]
            )
        }
        menu.addItem(onDemandItem)
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

    private func formatInteger(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

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
