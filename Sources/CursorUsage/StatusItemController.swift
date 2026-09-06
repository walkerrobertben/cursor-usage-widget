import AppKit

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

        switch MenubarPresentation.make(from: displayState) {
        case .warning:
            statusItem.isVisible = true
            button.attributedTitle = NSAttributedString(string: "⚠ Cursor")
        case .hidden:
            button.attributedTitle = NSAttributedString(string: "")
            statusItem.isVisible = false
        case let .visible(segments):
            statusItem.isVisible = true
            button.attributedTitle = attributedTitle(from: segments)
        }
    }

    private func attributedTitle(from segments: [MenubarSegment]) -> NSAttributedString {
        let title = NSMutableAttributedString()
        for segment in segments {
            if title.length > 0 {
                title.append(NSAttributedString(string: " · ", attributes: baseAttributes()))
            }
            title.append(NSAttributedString(string: segment.text, attributes: baseAttributes()))
        }
        return title
    }

    private func baseAttributes(color: NSColor = .labelColor) -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: color,
        ]
    }

    private func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        switch UsageScreen.make(from: displayState, includePollingHint: true) {
        case let .unauthenticated(message):
            addInfoItem(to: menu, title: message, style: .emphasis)
            addCommonActions(to: menu)
        case .loading:
            addInfoItem(to: menu, title: "Loading…", style: .secondary)
            addCommonActions(to: menu)
        case let .ready(model):
            addReadyMenuItems(model, to: menu)
            addCommonActions(to: menu)
        }
    }

    private func addReadyMenuItems(_ model: UsageViewModel, to menu: NSMenu) {
        addInfoItem(to: menu, title: model.headerTitle, style: .header)

        if let cycleLine = model.cycleLine {
            addInfoItem(to: menu, title: cycleLine, style: .secondary)
        }

        addInfoItem(to: menu, title: model.totalTitle, style: .body)
        menu.addItem(.separator())
        addPoolSection(model.cursor, to: menu)
        menu.addItem(.separator())
        addPoolSection(model.api, to: menu)

        if let bot = model.bot {
            menu.addItem(.separator())
            addPoolSection(bot, to: menu)
        }

        menu.addItem(.separator())
        addBillingSection(model.billing, to: menu)
        menu.addItem(.separator())

        if let lastUpdatedLine = model.lastUpdatedLine {
            addInfoItem(to: menu, title: lastUpdatedLine, style: .secondary)
        }
    }

    private func addPoolSection(_ section: UsageViewModel.PoolSection, to menu: NSMenu) {
        addUsageMeter(to: menu, content: section.meterContent)

        if section.aggregationsMissing {
            addInfoItem(
                to: menu,
                title: section.missingBreakdownMessage,
                style: .secondary,
                indentationLevel: 1
            )
            return
        }

        if section.rows.isEmpty {
            if section.showsEmptyPlaceholder {
                addInfoItem(
                    to: menu,
                    title: "No usage this cycle",
                    style: .secondary,
                    indentationLevel: 1
                )
            }
            return
        }

        addModelRows(section.rows, to: menu)
    }

    private func addModelRows(_ models: [ModelUsageRow], to menu: NSMenu) {
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

    private func addBillingSection(_ billing: UsageFormatting.BillingSnapshot, to menu: NSMenu) {
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

    private func addUsageMeter(to menu: NSMenu, content: UsageMeterContent) {
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
        if let url = URL(string: AppInfo.dashboardURL) {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
