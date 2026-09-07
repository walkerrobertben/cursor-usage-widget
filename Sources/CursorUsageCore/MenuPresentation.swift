import Foundation

/// Structured menu the AppKit dropdown and HTML renderer both paint.
public struct MenuPresentation: Equatable, Sendable {
    public enum Style: String, Equatable, Sendable {
        case header
        case section
        case body
        case secondary
        case separator
    }

    public struct Menubar: Equatable, Sendable {
        public enum Kind: Equatable, Sendable {
            case hidden
            case warning(text: String)
            case loading
            case visible(segments: [String])
        }

        public var kind: Kind

        public var visible: Bool {
            if case .hidden = kind { return false }
            return true
        }

        public var warning: Bool {
            if case .warning = kind { return true }
            return false
        }

        public var segments: [String] {
            switch kind {
            case .hidden:
                return []
            case let .warning(text):
                return [text]
            case .loading:
                return [MenubarPresentation.loadingChip]
            case let .visible(segments):
                return segments
            }
        }

        public var text: String? {
            switch kind {
            case .hidden:
                return nil
            case let .warning(text):
                return text
            case .loading:
                return MenubarPresentation.loadingChip
            case let .visible(segments):
                return segments.joined(separator: " · ")
            }
        }
    }

    public struct TextRow: Equatable, Sendable {
        public var role: String
        public var text: String
        public var style: Style
        public var indentation: Int
    }

    public struct MeterRow: Equatable, Sendable {
        public var role: String
        public var content: UsageMeterContent
        public var level: UsageMeterLevel
    }

    public struct ActionRow: Equatable, Sendable {
        public var role: String
        public var title: String
        public var keyEquivalent: String?
        public var url: String?
    }

    public struct ProfileRow: Equatable, Sendable {
        public var id: String
        public var title: String
        public var isSelected: Bool
    }

    public struct ProfileSwitcherRow: Equatable, Sendable {
        public var role: String
        public var title: String
        public var options: [ProfileRow]
    }

    public enum Row: Equatable, Sendable {
        case separator
        case text(TextRow)
        case meter(MeterRow)
        case model(UsageModelRowContent)
        case action(ActionRow)
        case profileSwitcher(ProfileSwitcherRow)
    }

    public var menubar: Menubar
    public var rows: [Row]

    public static let authFallbackMessage = "Couldn't authenticate — is Cursor signed in?"
    public static let loadingMessage = "Loading…"
    public static let emptyBreakdownMessage = "No usage this cycle"
    public static let refreshTitle = "Refresh Now"
    public static let dashboardTitle = "Open Dashboard…"
    public static let quitTitle = "Quit"
    public static let refreshKey = "r"
    public static let quitKey = "q"
    public static let profileSwitcherRole = "profileSwitcher"

    public static func currentProfileTitle(_ name: String) -> String {
        "Current profile: \(name)"
    }

    public static func make(
        from state: UsageDisplayState,
        calendar: DisplayCalendar = .current,
        includePollingHint: Bool = true,
        missingBreakdownMessage: String = "Loading breakdown…"
    ) -> MenuPresentation {
        var rows: [Row] = []
        switch UsageScreen.make(
            from: state,
            calendar: calendar,
            includePollingHint: includePollingHint,
            missingBreakdownMessage: missingBreakdownMessage
        ) {
        case let .unauthenticated(message):
            rows.append(.text(TextRow(role: "authError", text: message, style: .body, indentation: 0)))
            appendProfiles(&rows, state.profiles)
        case .loading:
            rows.append(.text(TextRow(role: "loading", text: loadingMessage, style: .secondary, indentation: 0)))
            appendProfiles(&rows, state.profiles)
        case let .ready(model):
            appendReady(&rows, model: model, profiles: state.profiles, calendar: calendar)
        }
        appendActions(&rows)
        return MenuPresentation(menubar: menubar(from: state), rows: rows)
    }

    private static func menubar(from state: UsageDisplayState) -> Menubar {
        switch MenubarPresentation.make(from: state) {
        case .hidden:
            return Menubar(kind: .hidden)
        case .warning:
            return Menubar(kind: .warning(text: "⚠ Cursor"))
        case .loading:
            return Menubar(kind: .loading)
        case let .visible(segments):
            return Menubar(kind: .visible(segments: segments.map(\.text)))
        }
    }

    private static func appendReady(
        _ rows: inout [Row],
        model: UsageViewModel,
        profiles: [CursorProfileOption],
        calendar: DisplayCalendar
    ) {
        rows.append(.text(TextRow(role: "header", text: model.headerTitle, style: .header, indentation: 0)))
        if let cycleLine = model.cycleLine {
            rows.append(.text(TextRow(role: "cycle", text: cycleLine, style: .secondary, indentation: 0)))
        }
        rows.append(.text(TextRow(role: "total", text: model.totalTitle, style: .body, indentation: 0)))
        appendProfiles(&rows, profiles)
        rows.append(.separator)
        appendPool(&rows, model.cursor, calendar: calendar)
        rows.append(.separator)
        appendPool(&rows, model.api, calendar: calendar)
        if let bot = model.bot {
            rows.append(.separator)
            appendPool(&rows, bot, calendar: calendar)
        }
        rows.append(.separator)
        appendOnDemand(&rows, model.billing, resetDate: model.billingResetDate, calendar: calendar)
        rows.append(.separator)
        appendTotalBill(&rows, model.billing)
        rows.append(.separator)
        if let lastUpdatedLine = model.lastUpdatedLine {
            rows.append(.text(TextRow(role: "footer", text: lastUpdatedLine, style: .secondary, indentation: 0)))
        }
    }

    private static func appendPool(_ rows: inout [Row], _ section: UsageViewModel.PoolSection, calendar: DisplayCalendar) {
        let meter = section.meterContent(calendar: calendar)
        rows.append(
            .meter(
                MeterRow(
                    role: "meter-\(section.id)",
                    content: meter,
                    level: section.meterLevel
                )
            )
        )

        if section.aggregationsMissing {
            rows.append(
                .text(
                    TextRow(
                        role: "breakdown",
                        text: section.missingBreakdownMessage,
                        style: .secondary,
                        indentation: 1
                    )
                )
            )
            return
        }
        if section.rows.isEmpty {
            if section.showsEmptyPlaceholder {
                rows.append(
                    .text(
                        TextRow(
                            role: "empty",
                            text: emptyBreakdownMessage,
                            style: .secondary,
                            indentation: 1
                        )
                    )
                )
            }
            return
        }
        for row in section.rows {
            rows.append(
                .model(
                    UsageModelRowContent(
                        name: row.name,
                        tokens: UsageFormatting.tokensColumnText(row.tokens),
                        cost: UsageFormatting.dollarsFromCents(row.cents)
                    )
                )
            )
        }
    }

    private static func appendOnDemand(
        _ rows: inout [Row],
        _ billing: UsageFormatting.BillingSnapshot,
        resetDate: Date?,
        calendar: DisplayCalendar
    ) {
        if let meter = billing.onDemandMeter(resetDate: resetDate, calendar: calendar) {
            rows.append(
                .meter(
                    MeterRow(
                        role: "onDemandMeter",
                        content: meter,
                        level: UsageMeterLevel.from(percentUsed: meter.percentUsed)
                    )
                )
            )
        } else {
            rows.append(
                .text(
                    TextRow(
                        role: "onDemand",
                        text: billing.onDemandHeaderLine,
                        style: .section,
                        indentation: 0
                    )
                )
            )
        }

        if billing.hasTeamBudget {
            rows.append(
                .text(TextRow(role: "onDemandYou", text: billing.youLine, style: .secondary, indentation: 1))
            )
            if let everyoneElseLine = billing.everyoneElseLine {
                rows.append(
                    .text(
                        TextRow(
                            role: "onDemandOthers",
                            text: everyoneElseLine,
                            style: .secondary,
                            indentation: 1
                        )
                    )
                )
            }
        }
    }

    private static func appendTotalBill(_ rows: inout [Row], _ billing: UsageFormatting.BillingSnapshot) {
        if let totalBillLine = billing.totalBillLine {
            rows.append(.text(TextRow(role: "billing", text: totalBillLine, style: .section, indentation: 0)))
        }
        if let totalBillDetailLine = billing.totalBillDetailLine {
            rows.append(
                .text(
                    TextRow(
                        role: "billingDetail",
                        text: totalBillDetailLine,
                        style: .secondary,
                        indentation: 1
                    )
                )
            )
        }
    }

    private static func appendProfiles(_ rows: inout [Row], _ profiles: [CursorProfileOption]) {
        guard profiles.count >= 2 else { return }
        let current = profiles.first(where: \.isSelected) ?? profiles[0]
        rows.append(
            .profileSwitcher(
                ProfileSwitcherRow(
                    role: profileSwitcherRole,
                    title: currentProfileTitle(current.title),
                    options: profiles.map { profile in
                        ProfileRow(
                            id: profile.id,
                            title: profile.title,
                            isSelected: profile.isSelected
                        )
                    }
                )
            )
        )
    }

    private static func appendActions(_ rows: inout [Row]) {
        rows.append(
            .action(
                ActionRow(
                    role: "refresh",
                    title: refreshTitle,
                    keyEquivalent: refreshKey,
                    url: nil
                )
            )
        )
        rows.append(
            .action(
                ActionRow(
                    role: "dashboard",
                    title: dashboardTitle,
                    keyEquivalent: nil,
                    url: AppInfo.dashboardURL
                )
            )
        )
        rows.append(
            .action(
                ActionRow(
                    role: "quit",
                    title: quitTitle,
                    keyEquivalent: quitKey,
                    url: nil
                )
            )
        )
    }
}

extension MenuPresentation {
    public func text(matching role: String) -> String? {
        for row in rows {
            if case let .text(item) = row, item.role == role {
                return item.text
            }
            if case let .meter(item) = row, item.role == role {
                return item.content.title
            }
            if case let .action(item) = row, item.role == role {
                return item.title
            }
            if case let .profileSwitcher(item) = row, item.role == role {
                return item.title
            }
        }
        return nil
    }

    public func texts(matching role: String) -> [String] {
        rows.compactMap { row in
            switch row {
            case let .text(item) where item.role == role:
                return item.text
            case let .meter(item) where item.role == role:
                return item.content.title
            case let .action(item) where item.role == role:
                return item.title
            case let .profileSwitcher(item) where item.role == role:
                return item.title
            default:
                return nil
            }
        }
    }

    public var meters: [MeterRow] {
        rows.compactMap { row in
            if case let .meter(item) = row { return item }
            return nil
        }
    }

    public var models: [UsageModelRowContent] {
        rows.compactMap { row in
            if case let .model(item) = row { return item }
            return nil
        }
    }

    public var profileSwitcher: ProfileSwitcherRow? {
        for row in rows {
            if case let .profileSwitcher(item) = row {
                return item
            }
        }
        return nil
    }

    /// The live AppKit dropdown rebuilds from `rows` while it is open.
    public func shouldReplaceOpenMenu(from previous: MenuPresentation, isOpen: Bool) -> Bool {
        isOpen && rows != previous.rows
    }

    public var roleOrder: [String] {
        rows.compactMap { row in
            switch row {
            case .separator:
                return nil
            case let .text(item):
                return item.role
            case let .meter(item):
                return item.role
            case .model:
                return "model"
            case let .action(item):
                return item.role
            case let .profileSwitcher(item):
                return item.role
            }
        }
    }
}
