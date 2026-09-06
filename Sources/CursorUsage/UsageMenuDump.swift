import Foundation

/// Line-by-line dump of everything the menu bar extra shows.
/// Shared by the CLI so an agent can read the same surfaces without AppKit.
struct VisibleDump: Encodable {
    struct Menubar: Encodable {
        let visible: Bool
        let warning: Bool
        let text: String?
        let segments: [String]
    }

    struct Line: Encodable {
        let role: String
        let text: String
        let style: String
        let indentation: Int
        let meterLevel: String?
        let keyEquivalent: String?
        let url: String?
    }

    let menubar: Menubar
    let dropdown: [Line]

    var menubarText: String? { menubar.text }

    func fullText() -> String {
        var lines: [String] = []
        lines.append("Menu bar")
        if menubar.warning, let text = menubar.text {
            lines.append("  \(text)")
        } else if menubar.visible, let text = menubar.text {
            lines.append("  \(text)")
        } else {
            lines.append("  (hidden)")
        }
        lines.append("")
        lines.append("Dropdown")
        for item in dropdown {
            lines.append(contentsOf: Self.render(item))
        }
        return lines.joined(separator: "\n")
    }

    private static func render(_ item: Line) -> [String] {
        if item.role == "separator" {
            return ["  ---"]
        }

        var text = item.text
        if let key = item.keyEquivalent, !key.isEmpty {
            text += "  [\(key)]"
        }
        if let url = item.url, !url.isEmpty {
            text += "  \(url)"
        }
        if let level = item.meterLevel, item.role == "meterBar" {
            text += "  \(level)"
        }

        let indent = 2 + max(item.indentation, 0) * 2
        let padding = String(repeating: " ", count: indent)
        return ["\(padding)\(text)"]
    }
}

enum AppSurfaceDump {
    static let authFallbackMessage = "Couldn't authenticate — is Cursor signed in?"
    static let loadingMessage = "Loading…"
    static let emptyBreakdownMessage = "No usage this cycle"
    static let refreshTitle = "Refresh Now"
    static let dashboardTitle = "Open Dashboard…"
    static let quitTitle = "Quit"
    static let refreshKey = "r"
    static let quitKey = "q"

    static func make(
        from state: UsageDisplayState,
        includePollingHint: Bool = true,
        missingBreakdownMessage: String = "Loading breakdown…"
    ) -> VisibleDump {
        let menubar = menubarDump(from: state)
        let screen = UsageScreen.make(
            from: state,
            includePollingHint: includePollingHint,
            missingBreakdownMessage: missingBreakdownMessage
        )
        var dropdown: [VisibleDump.Line] = []
        switch screen {
        case let .unauthenticated(message):
            dropdown.append(
                line(role: "authError", text: message, style: "emphasis")
            )
        case .loading:
            dropdown.append(
                line(role: "loading", text: loadingMessage, style: "secondary")
            )
        case let .ready(model):
            appendReadyMenu(&dropdown, model: model)
        }
        appendActions(&dropdown)
        return VisibleDump(menubar: menubar, dropdown: dropdown)
    }

    static func selfCheckFailures() -> [String] {
        var failures: [String] = []

        let unauth = make(
            from: UsageDisplayState(
                isAuthenticated: false,
                authErrorMessage: authFallbackMessage
            )
        )
        expect(unauth.menubar.warning, "unauth menubar should warn", into: &failures)
        expect(unauth.menubar.text == "⚠ Cursor", "unauth menubar text", into: &failures)
        expect(
            unauth.dropdown.contains { $0.text == authFallbackMessage && $0.style == "emphasis" },
            "unauth dropdown shows the auth error",
            into: &failures
        )
        expectActions(unauth.dropdown, into: &failures)

        let loading = make(from: UsageDisplayState())
        expect(!loading.menubar.visible, "loading menubar is hidden", into: &failures)
        expect(
            loading.dropdown.contains { $0.text == loadingMessage },
            "loading dropdown shows Loading…",
            into: &failures
        )
        expectActions(loading.dropdown, into: &failures)

        let ready = make(from: SelfCheckFixture.state)
        expect(ready.menubar.visible, "ready menubar is visible", into: &failures)
        expect(
            ready.menubar.segments.contains(where: { $0.hasPrefix("Cursor:") }),
            "ready menubar shows Cursor %",
            into: &failures
        )
        expect(
            ready.menubar.segments.contains(where: { $0.hasPrefix("API:") }),
            "ready menubar shows API %",
            into: &failures
        )
        expect(
            ready.menubar.segments.contains(where: { $0.hasPrefix("Bot:") }),
            "ready menubar shows Bot %",
            into: &failures
        )
        expect(
            ready.menubar.segments.contains(where: { $0.hasPrefix("$") }),
            "ready menubar shows on-demand $",
            into: &failures
        )
        expectContains(ready.dropdown, text: "Cursor Usage — pro", into: &failures)
        expectContains(ready.dropdown, textPrefix: "Cycle: ", into: &failures)
        expectContains(ready.dropdown, textPrefix: "Total — ", into: &failures)
        expectContains(ready.dropdown, textPrefix: "Cursor — ", into: &failures)
        expectContains(ready.dropdown, textPrefix: "API — ", into: &failures)
        expectContains(ready.dropdown, text: "Plan limit: $20", into: &failures)
        expectContains(ready.dropdown, textPrefix: "Bot — ", into: &failures)
        expectContains(ready.dropdown, text: "composer", into: &failures)
        expectContains(ready.dropdown, text: "gpt-5", into: &failures)
        expectContains(ready.dropdown, text: "grok-bot-1", into: &failures)
        expectContains(ready.dropdown, textPrefix: "Total bill this cycle:", into: &failures)
        expectContains(ready.dropdown, textPrefix: "On-demand:", into: &failures)
        expectContains(ready.dropdown, text: "$1.50 (you)", into: &failures)
        expectContains(ready.dropdown, text: "$3.50 (everyone else)", into: &failures)
        expectContains(ready.dropdown, textPrefix: "Refreshes every \(AppInfo.summaryPollSeconds)s", into: &failures)
        expect(
            ready.dropdown.contains { $0.role == "meterBar" && $0.meterLevel != nil },
            "meters include a bar and color level",
            into: &failures
        )
        expect(
            ready.dropdown.contains { $0.role == "meterCaptions" && $0.text.contains("% used") },
            "meters include percent-used caption",
            into: &failures
        )
        expect(
            ready.dropdown.contains { $0.role == "meterCaptions" && $0.text.contains("Resets") },
            "meters include reset caption",
            into: &failures
        )
        expect(
            ready.dropdown.contains { $0.role == "onDemand" && $0.style == "alert" },
            "on-demand header uses alert style when spend is active",
            into: &failures
        )
        expectActions(ready.dropdown, into: &failures)
        return failures
    }

    private static func menubarDump(from state: UsageDisplayState) -> VisibleDump.Menubar {
        switch MenubarPresentation.make(from: state) {
        case .hidden:
            return VisibleDump.Menubar(visible: false, warning: false, text: nil, segments: [])
        case .warning:
            return VisibleDump.Menubar(visible: true, warning: true, text: "⚠ Cursor", segments: ["⚠ Cursor"])
        case let .visible(segments):
            let texts = segments.map(\.text)
            return VisibleDump.Menubar(
                visible: true,
                warning: false,
                text: texts.joined(separator: " · "),
                segments: texts
            )
        }
    }

    private static func appendReadyMenu(_ dropdown: inout [VisibleDump.Line], model: UsageViewModel) {
        dropdown.append(line(role: "header", text: model.headerTitle, style: "header"))
        if let cycleLine = model.cycleLine {
            dropdown.append(line(role: "cycle", text: cycleLine, style: "secondary"))
        }
        dropdown.append(line(role: "total", text: model.totalTitle, style: "body"))
        dropdown.append(separator())
        appendPool(&dropdown, model.cursor)
        dropdown.append(separator())
        appendPool(&dropdown, model.api)
        if let bot = model.bot {
            dropdown.append(separator())
            appendPool(&dropdown, bot)
        }
        dropdown.append(separator())
        appendBilling(&dropdown, model.billing)
        dropdown.append(separator())
        if let lastUpdatedLine = model.lastUpdatedLine {
            dropdown.append(line(role: "footer", text: lastUpdatedLine, style: "secondary"))
        }
    }

    private static func appendPool(_ dropdown: inout [VisibleDump.Line], _ section: UsageViewModel.PoolSection) {
        let meter = section.meterContent
        dropdown.append(line(role: "meterTitle", text: meter.title, style: "section"))
        if let subtitle = meter.subtitle, !subtitle.isEmpty {
            dropdown.append(line(role: "meterSubtitle", text: subtitle, style: "secondary", indentation: 1))
        }
        dropdown.append(
            line(
                role: "meterBar",
                text: UsageFormatting.asciiMeterBar(percentUsed: meter.percentUsed),
                style: "body",
                meterLevel: section.meterLevel.rawValue
            )
        )
        dropdown.append(
            line(
                role: "meterCaptions",
                text: captionLine(left: meter.leftCaption, right: meter.rightCaption),
                style: "secondary"
            )
        )

        if section.aggregationsMissing {
            dropdown.append(
                line(
                    role: "breakdown",
                    text: section.missingBreakdownMessage,
                    style: "secondary",
                    indentation: 1
                )
            )
            return
        }
        if section.rows.isEmpty {
            if section.showsEmptyPlaceholder {
                dropdown.append(
                    line(
                        role: "empty",
                        text: emptyBreakdownMessage,
                        style: "secondary",
                        indentation: 1
                    )
                )
            }
            return
        }
        for row in section.rows {
            dropdown.append(
                line(
                    role: "model",
                    text: "\(row.name)    \(UsageFormatting.tokensColumnText(row.tokens))    \(UsageFormatting.dollarsFromCents(row.cents))",
                    style: "body",
                    indentation: 1
                )
            )
        }
    }

    private static func appendBilling(
        _ dropdown: inout [VisibleDump.Line],
        _ billing: UsageFormatting.BillingSnapshot
    ) {
        let highlight = billing.isOnDemandActive
        let valueStyle = highlight ? "alert" : "body"
        if let totalBillLine = billing.totalBillLine {
            dropdown.append(line(role: "billing", text: totalBillLine, style: "section"))
        }
        if let totalBillDetailLine = billing.totalBillDetailLine {
            dropdown.append(
                line(role: "billingDetail", text: totalBillDetailLine, style: "secondary", indentation: 1)
            )
        }
        dropdown.append(
            line(
                role: "onDemand",
                text: billing.onDemandHeaderLine,
                style: highlight ? "alert" : "section"
            )
        )
        if billing.hasTeamBudget {
            dropdown.append(line(role: "onDemandYou", text: billing.youLine, style: valueStyle, indentation: 1))
            if let everyoneElseLine = billing.everyoneElseLine {
                dropdown.append(
                    line(role: "onDemandOthers", text: everyoneElseLine, style: valueStyle, indentation: 1)
                )
            }
        }
    }

    private static func appendActions(_ dropdown: inout [VisibleDump.Line]) {
        dropdown.append(
            line(role: "action", text: refreshTitle, style: "body", keyEquivalent: refreshKey)
        )
        dropdown.append(
            line(
                role: "action",
                text: dashboardTitle,
                style: "body",
                url: AppInfo.dashboardURL
            )
        )
        dropdown.append(
            line(role: "action", text: quitTitle, style: "body", keyEquivalent: quitKey)
        )
    }

    private static func separator() -> VisibleDump.Line {
        line(role: "separator", text: "", style: "separator")
    }

    private static func captionLine(left: String, right: String) -> String {
        if right.isEmpty {
            return left
        }
        if left.isEmpty {
            return right
        }
        return "\(left)    \(right)"
    }

    private static func line(
        role: String,
        text: String,
        style: String,
        indentation: Int = 0,
        meterLevel: String? = nil,
        keyEquivalent: String? = nil,
        url: String? = nil
    ) -> VisibleDump.Line {
        VisibleDump.Line(
            role: role,
            text: text,
            style: style,
            indentation: indentation,
            meterLevel: meterLevel,
            keyEquivalent: keyEquivalent,
            url: url
        )
    }

    private static func expect(_ condition: Bool, _ message: String, into failures: inout [String]) {
        if !condition {
            failures.append(message)
        }
    }

    private static func expectContains(
        _ dropdown: [VisibleDump.Line],
        text: String,
        into failures: inout [String]
    ) {
        expect(
            dropdown.contains { $0.text == text || $0.text.contains(text) },
            "dropdown missing \(text)",
            into: &failures
        )
    }

    private static func expectContains(
        _ dropdown: [VisibleDump.Line],
        textPrefix: String,
        into failures: inout [String]
    ) {
        expect(
            dropdown.contains { $0.text.hasPrefix(textPrefix) },
            "dropdown missing prefix \(textPrefix)",
            into: &failures
        )
    }

    private static func expectActions(_ dropdown: [VisibleDump.Line], into failures: inout [String]) {
        expectContains(dropdown, text: refreshTitle, into: &failures)
        expectContains(dropdown, text: dashboardTitle, into: &failures)
        expectContains(dropdown, text: quitTitle, into: &failures)
        expect(
            dropdown.contains { $0.text == refreshTitle && $0.keyEquivalent == refreshKey },
            "Refresh Now should show key equivalent r",
            into: &failures
        )
        expect(
            dropdown.contains { $0.text == quitTitle && $0.keyEquivalent == quitKey },
            "Quit should show key equivalent q",
            into: &failures
        )
        expect(
            dropdown.contains { $0.text == dashboardTitle && $0.url == AppInfo.dashboardURL },
            "Open Dashboard… should include the usage dashboard URL",
            into: &failures
        )
    }
}

private enum SelfCheckFixture {
    static var state: UsageDisplayState {
        let summary = UsageSummaryResponse(
            billingCycleStart: "2026-09-01T00:00:00.000Z",
            billingCycleEnd: "2026-10-01T00:00:00.000Z",
            membershipType: "pro",
            limitType: nil,
            isUnlimited: false,
            autoModelSelectedDisplayMessage: nil,
            namedModelSelectedDisplayMessage: nil,
            individualUsage: UsageSummaryResponse.IndividualUsage(
                plan: UsageSummaryResponse.IndividualUsage.Plan(
                    enabled: true,
                    used: 0,
                    limit: 0,
                    remaining: 0,
                    breakdown: nil,
                    autoPercentUsed: 12,
                    apiPercentUsed: 5,
                    totalPercentUsed: 17
                ),
                onDemand: UsageSummaryResponse.IndividualUsage.OnDemand(
                    enabled: true,
                    used: 150,
                    limit: 5000,
                    remaining: 4850
                )
            ),
            teamUsage: UsageSummaryResponse.TeamUsage(
                onDemand: UsageSummaryResponse.TeamUsage.OnDemand(
                    enabled: true,
                    used: 500,
                    limit: 10_000,
                    remaining: 9500
                )
            )
        )

        let aggregations = AggregatedUsageResponse(
            aggregations: [
                AggregatedUsageResponse.Aggregation(
                    modelIntent: "composer",
                    inputTokens: "1000",
                    outputTokens: "2000",
                    cacheWriteTokens: "0",
                    cacheReadTokens: "0",
                    totalCents: 800,
                    tier: 2
                ),
                AggregatedUsageResponse.Aggregation(
                    modelIntent: "gpt-5",
                    inputTokens: "500",
                    outputTokens: "500",
                    cacheWriteTokens: "0",
                    cacheReadTokens: "0",
                    totalCents: 434,
                    tier: 3
                ),
                AggregatedUsageResponse.Aggregation(
                    modelIntent: "grok-bot-1",
                    inputTokens: "100",
                    outputTokens: "100",
                    cacheWriteTokens: "0",
                    cacheReadTokens: "0",
                    totalCents: 100,
                    tier: 1
                ),
            ],
            totalInputTokens: nil,
            totalOutputTokens: nil,
            totalCacheWriteTokens: nil,
            totalCacheReadTokens: nil,
            totalCostCents: nil
        )

        let sand = SandUsageResponse(
            currentPeriodStart: "2026-09-01T00:00:00.000Z",
            nextResetTimestampUtc: "2026-09-08T12:00:00.000Z",
            usagePercent: 8,
            hasAvailableUsage: true,
            hasNonZeroIncludedLimit: true,
            grokPlanLabel: "included"
        )

        let plan = PlanInfoResponse(
            planInfo: PlanInfoResponse.PlanInfo(
                planName: "Pro",
                includedAmountCents: 2000,
                price: "$20",
                billingCycleEnd: "2026-10-01T00:00:00Z",
                planOwner: nil
            )
        )

        return UsageDisplayState(
            summary: summary,
            aggregations: aggregations,
            weeklyAggregations: aggregations,
            sandUsage: sand,
            planInfo: plan,
            hardLimit: HardLimitResponse(noUsageBasedAllowed: false, hardLimit: 50, hardLimitPerUser: nil),
            lastUpdated: Date(timeIntervalSince1970: 1_788_710_400),
            isAuthenticated: true
        )
    }
}
