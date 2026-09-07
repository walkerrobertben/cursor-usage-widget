import Foundation

public enum CursorAPIEndpoint: String, CaseIterable, Equatable, Sendable {
    case usageSummary = "/api/usage-summary"
    case aggregatedUsage = "/api/dashboard/get-aggregated-usage-events"
    case sandUsage = "/api/dashboard/get-sand-usage-status"
    case planInfo = "/api/dashboard/get-plan-info"
    case hardLimit = "/api/dashboard/get-hard-limit"
    case me = "/api/dashboard/get-me"
    case teamSpend = "/api/dashboard/get-team-spend"

    public var method: String {
        switch self {
        case .usageSummary:
            return "GET"
        case .aggregatedUsage, .sandUsage, .planInfo, .hardLimit, .me, .teamSpend:
            return "POST"
        }
    }

    public var requiresOrigin: Bool {
        method == "POST"
    }

    public var urlString: String {
        "https://cursor.com\(rawValue)"
    }
}
