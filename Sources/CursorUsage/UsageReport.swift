import Foundation

enum UsageSnapshotFetcher {
    static func fetchDisplayState(using api: CursorAPI) async throws -> UsageDisplayState {
        let summary: UsageSummaryResponse
        do {
            summary = try await api.fetchUsageSummary()
        } catch let CursorAPIError.httpError(statusCode, _) where statusCode == 401 || statusCode == 403 {
            return UsageDisplayState(
                isAuthenticated: false,
                authErrorMessage: "Couldn't authenticate — is Cursor signed in?"
            )
        }

        let sand = try? await api.fetchSandUsage()
        let plan = try? await api.fetchPlanInfo()
        let hardLimit = try? await api.fetchHardLimit()

        var aggregations: AggregatedUsageResponse?
        var weekly: AggregatedUsageResponse?
        if let start = summary.billingCycleStartDate {
            let end = summary.billingCycleEndDate ?? Date()
            aggregations = try? await api.fetchAggregatedUsage(startDate: start, endDate: end)
            weekly = await api.fetchWeeklyBotAggregations(sand: sand)
        }

        return UsageDisplayState(
            summary: summary,
            aggregations: aggregations,
            weeklyAggregations: weekly,
            sandUsage: sand,
            planInfo: plan,
            hardLimit: hardLimit,
            lastUpdated: Date(),
            isAuthenticated: true,
            authErrorMessage: nil
        )
    }
}

enum UsageReport {
    static func text(
        model: UsageViewModel,
        auth: CursorAuth,
        compact: Bool
    ) -> String {
        if compact {
            return model.menubar.compactLine ?? model.headerTitle
        }

        var lines: [String] = []
        lines.append(model.headerTitle)
        if let cycleLine = model.cycleLine {
            lines.append(cycleLine)
        }
        if let menubar = model.menubar.compactLine {
            lines.append("Menu bar: \(menubar)")
        }
        lines.append("")
        lines.append(model.totalTitle)
        lines.append("")
        lines.append(contentsOf: textSection(model.cursor))
        lines.append("")
        lines.append(contentsOf: textSection(model.api))
        if let bot = model.bot {
            lines.append("")
            lines.append(contentsOf: textSection(bot))
        }
        lines.append("")
        lines.append(model.billing.plainText)
        if let lastUpdatedLine = model.lastUpdatedLine {
            lines.append("")
            lines.append(lastUpdatedLine)
        }
        lines.append("")
        lines.append("Auth")
        lines.append("  Database: \(auth.databasePath)")
        lines.append("  Resolved via: \(auth.source)")
        lines.append("  User ID: \(auth.userId)")
        lines.append("")
        lines.append("Dashboard: \(model.dashboardURL)")
        return lines.joined(separator: "\n")
    }

    static func json(
        model: UsageViewModel,
        auth: CursorAuth
    ) throws -> String {
        let document = CheckJSONDocument.make(model: model, auth: auth)
        return try encodeJSON(document)
    }

    static func encodeJSON<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        guard var text = String(data: data, encoding: .utf8) else {
            throw CursorAPIError.invalidURL
        }
        if !text.hasSuffix("\n") {
            text.append("\n")
        }
        return text
    }

    private static func textSection(_ section: UsageViewModel.PoolSection) -> [String] {
        var lines: [String] = [section.title]
        if let subtitle = section.subtitle, !subtitle.isEmpty {
            lines.append("  \(subtitle)")
        }
        lines.append("  \(UsageFormatting.asciiMeterLine(percentUsed: section.percentUsed, resetDate: section.resetDate))")

        if section.aggregationsMissing {
            lines.append("  \(section.missingBreakdownMessage)")
            return lines
        }
        if section.rows.isEmpty {
            if section.showsEmptyPlaceholder {
                lines.append("  No usage this cycle")
            }
            return lines
        }
        for row in UsageFormatting.formatModelRows(section.rows) {
            lines.append("  \(row)")
        }
        return lines
    }
}

struct CheckJSONDocument: Encodable {
    struct Percent: Encodable {
        let cursor: Double
        let api: Double
        let total: Double
        let bot: Double?
    }

    struct BillingCycle: Encodable {
        let start: String?
        let end: String?
        let display: String?
    }

    struct Model: Encodable {
        let name: String
        let tokens: Int
        let cents: Double
        let tokensDisplay: String
        let costDisplay: String
    }

    struct Section: Encodable {
        let id: String
        let title: String
        let subtitle: String?
        let percentUsed: Double
        let barFraction: Double
        let percentCaption: String
        let resetCaption: String
        let meterLevel: String
        let usedCents: Double
        let estimatedPoolCents: Double?
        let planLimitCents: Double?
        let breakdownStatus: String
        let models: [Model]
    }

    struct Billing: Encodable {
        let totalBillLine: String?
        let totalBillDetailLine: String?
        let onDemandHeaderLine: String
        let totalBillCents: Int?
        let individualUsedCents: Int
        let teamUsedCents: Int?
        let hasTeamBudget: Bool
        let youLine: String?
        let everyoneElseLine: String?
        let isOnDemandActive: Bool
        let mode: String
        let limitCents: Int?
    }

    struct Auth: Encodable {
        let databasePath: String
        let source: String
        let userId: String
    }

    let schemaVersion: Int
    let ok: Bool
    let version: String
    let menubar: String?
    let membershipType: String
    let header: String
    let billingCycle: BillingCycle
    let percent: Percent
    let total: String
    let totalUsedCents: Double
    let sections: [Section]
    let billing: Billing
    let fetchedAt: String?
    let fetchedAtDisplay: String?
    let dashboardURL: String
    let auth: Auth

    static func make(model: UsageViewModel, auth: CursorAuth) -> CheckJSONDocument {
        CheckJSONDocument(
            schemaVersion: AppInfo.schemaVersion,
            ok: true,
            version: AppInfo.version,
            menubar: model.menubar.compactLine,
            membershipType: model.membershipType,
            header: model.headerTitle,
            billingCycle: BillingCycle(
                start: model.billingCycleStart,
                end: model.billingCycleEnd,
                display: model.cycleLine
            ),
            percent: Percent(
                cursor: model.cursorPercent,
                api: model.apiPercent,
                total: model.totalPercent,
                bot: model.botPercent
            ),
            total: model.totalTitle,
            totalUsedCents: model.totalUsedCents,
            sections: model.sections.map(Section.make),
            billing: Billing.make(model.billing),
            fetchedAt: model.fetchedAt.map(UsageFormatting.isoString),
            fetchedAtDisplay: model.lastUpdatedLine,
            dashboardURL: model.dashboardURL,
            auth: Auth(
                databasePath: auth.databasePath,
                source: auth.source,
                userId: auth.userId
            )
        )
    }
}

private extension CheckJSONDocument.Section {
    static func make(_ section: UsageViewModel.PoolSection) -> CheckJSONDocument.Section {
        CheckJSONDocument.Section(
            id: section.id,
            title: section.title,
            subtitle: section.subtitle,
            percentUsed: section.percentUsed,
            barFraction: UsageFormatting.barFraction(percentUsed: section.percentUsed),
            percentCaption: section.leftCaption,
            resetCaption: section.rightCaption,
            meterLevel: section.meterLevel.rawValue,
            usedCents: section.usedCents,
            estimatedPoolCents: section.estimatedPoolCents,
            planLimitCents: section.planLimitCents,
            breakdownStatus: section.breakdownStatus,
            models: section.rows.map { row in
                CheckJSONDocument.Model(
                    name: row.name,
                    tokens: row.tokens,
                    cents: row.cents,
                    tokensDisplay: UsageFormatting.tokensColumnText(row.tokens),
                    costDisplay: UsageFormatting.dollarsFromCents(row.cents)
                )
            }
        )
    }
}

private extension CheckJSONDocument.Billing {
    static func make(_ billing: UsageFormatting.BillingSnapshot) -> CheckJSONDocument.Billing {
        CheckJSONDocument.Billing(
            totalBillLine: billing.totalBillLine,
            totalBillDetailLine: billing.totalBillDetailLine,
            onDemandHeaderLine: billing.onDemandHeaderLine,
            totalBillCents: billing.totalBillCents,
            individualUsedCents: billing.individualUsedCents,
            teamUsedCents: billing.teamUsedCents,
            hasTeamBudget: billing.hasTeamBudget,
            youLine: billing.hasTeamBudget ? billing.youLine : nil,
            everyoneElseLine: billing.everyoneElseLine,
            isOnDemandActive: billing.isOnDemandActive,
            mode: billing.modeIdentifier,
            limitCents: billing.limitCents
        )
    }
}
