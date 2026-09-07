import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import CursorUsageCore
import XCTest

enum TestCalendar {
    static let snapshot = DisplayCalendar(
        now: Date(timeIntervalSince1970: 1_788_710_400),
        timeZone: TimeZone(secondsFromGMT: 0)!,
        locale: Locale(identifier: "en_GB")
    )
}

enum FixtureFile {
    static func data(_ name: String) throws -> Data {
        let bundle = Bundle.module
        if let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures/cursor") {
            return try Data(contentsOf: url)
        }
        if let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "cursor") {
            return try Data(contentsOf: url)
        }
        if let url = bundle.url(forResource: name, withExtension: "json") {
            return try Data(contentsOf: url)
        }
        struct MissingFixture: Error, LocalizedError {
            var name: String
            var errorDescription: String? { "Missing fixture \(name).json in test bundle" }
        }
        throw MissingFixture(name: name)
    }
}

enum TestAuth {
    static let userId = "user_test"
    static let token = "aaa.bbb.ccc"

    static func make() -> CursorAuth {
        CursorAuth(
            databasePath: "/tmp/cursor-usage-tests/state.vscdb",
            token: token,
            userId: userId,
            source: "test"
        )
    }
}

struct RecordedRequest: Equatable, Sendable {
    var method: String
    var path: String
    var origin: String?
    var contentType: String?
    var cookie: String?
    var body: String?
}

final class MockCursorStore: @unchecked Sendable {
    struct Canned {
        var status: Int
        var body: Data
    }

    var canned: [String: Canned]
    var requests: [URLRequest] = []
    private let lock = NSLock()

    init(responses: [CursorAPIEndpoint: (status: Int, fixture: String)]) throws {
        var mapped: [String: Canned] = [:]
        for (endpoint, value) in responses {
            mapped[endpoint.rawValue] = Canned(status: value.status, body: try FixtureFile.data(value.fixture))
        }
        canned = mapped
    }

    func record(_ request: URLRequest) {
        lock.lock()
        requests.append(request)
        lock.unlock()
    }

    func response(for path: String) -> Canned? {
        lock.lock()
        defer { lock.unlock() }
        return canned[path]
    }

    var recorded: [RecordedRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requests.map { request in
            RecordedRequest(
                method: request.httpMethod ?? "GET",
                path: request.url?.path ?? "",
                origin: request.value(forHTTPHeaderField: "Origin"),
                contentType: request.value(forHTTPHeaderField: "Content-Type"),
                cookie: request.value(forHTTPHeaderField: "Cookie"),
                body: requestBody(request)
            )
        }
    }

    var recordedPaths: [String] {
        recorded.map(\.path)
    }
}

private func requestBody(_ request: URLRequest) -> String? {
    if let data = request.httpBody {
        return String(data: data, encoding: .utf8)
    }
    guard let stream = request.httpBodyStream else {
        return nil
    }
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 1024)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count <= 0 {
            break
        }
        data.append(buffer, count: count)
    }
    return String(data: data, encoding: .utf8)
}

actor MockCursorHTTPGate {
    func run<T: Sendable>(_ work: @Sendable () async -> T) async -> T {
        await work()
    }
}

enum MockCursorHTTP {
    static let gate = MockCursorHTTPGate()
    nonisolated(unsafe) static var store: MockCursorStore?

    static func session() -> URLSession {
        _ = URLProtocol.registerClass(MockURLProtocol.self)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }

    static func withStore<T: Sendable>(_ store: MockCursorStore, _ body: @Sendable () async -> T) async -> T {
        await gate.run {
            self.store = store
            defer { self.store = nil }
            return await body()
        }
    }
}

final class MockURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "cursor.com"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let store = MockCursorHTTP.store else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        store.record(request)
        let path = request.url?.path ?? ""
        let canned = store.response(for: path)
        let status = canned?.status ?? 404
        let body = canned?.body ?? Data(#"{"error":"unexpected path"}"#.utf8)
        let url = request.url ?? URL(string: "https://cursor.com")!
        let response = HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

enum Scenario {
    case disabled
    case limited
    case unlimited
    case teamEnterprise
    case limitedHigh
    case unauthorized
    case emptyMeters
    case fullMeters
    case cursorOnlyEmpty
    case cursorOnlyFull
    case ultra
    case teamPremium
    case teamStandard

    func store() throws -> MockCursorStore {
        switch self {
        case .disabled:
            return try MockCursorStore(responses: [
                .usageSummary: (200, "usage-summary-disabled"),
                .sandUsage: (200, "get-sand-usage-status"),
                .planInfo: (200, "get-plan-info-pro"),
                .hardLimit: (200, "get-hard-limit-disabled"),
                .aggregatedUsage: (200, "get-aggregated-usage-events"),
            ])
        case .limited:
            return try MockCursorStore(responses: [
                .usageSummary: (200, "usage-summary-limited"),
                .sandUsage: (200, "get-sand-usage-status"),
                .planInfo: (200, "get-plan-info-pro"),
                .hardLimit: (200, "get-hard-limit-limited"),
                .aggregatedUsage: (200, "get-aggregated-usage-events"),
            ])
        case .unlimited:
            return try MockCursorStore(responses: [
                .usageSummary: (200, "usage-summary-unlimited"),
                .sandUsage: (200, "get-sand-usage-status"),
                .planInfo: (200, "get-plan-info-pro"),
                .hardLimit: (200, "get-hard-limit-unlimited"),
                .aggregatedUsage: (200, "get-aggregated-usage-events"),
            ])
        case .teamEnterprise:
            return try MockCursorStore(responses: [
                .usageSummary: (200, "usage-summary-team-enterprise"),
                .sandUsage: (200, "get-sand-usage-status"),
                .planInfo: (200, "get-plan-info-enterprise"),
                .hardLimit: (200, "get-hard-limit-limited"),
                .aggregatedUsage: (200, "get-aggregated-usage-events"),
            ])
        case .limitedHigh:
            return try MockCursorStore(responses: [
                .usageSummary: (200, "usage-summary-limited-high"),
                .sandUsage: (200, "get-sand-usage-status"),
                .planInfo: (200, "get-plan-info-pro"),
                .hardLimit: (200, "get-hard-limit-limited"),
                .aggregatedUsage: (200, "get-aggregated-usage-events"),
            ])
        case .unauthorized:
            return try MockCursorStore(responses: [
                .usageSummary: (401, "unauthorized"),
            ])
        case .emptyMeters:
            return try MockCursorStore(responses: [
                .usageSummary: (200, "usage-summary-empty"),
                .sandUsage: (200, "get-sand-usage-zero"),
                .planInfo: (200, "get-plan-info-pro"),
                .hardLimit: (200, "get-hard-limit-limited"),
                .aggregatedUsage: (200, "get-aggregated-usage-empty"),
            ])
        case .fullMeters:
            return try MockCursorStore(responses: [
                .usageSummary: (200, "usage-summary-full"),
                .sandUsage: (200, "get-sand-usage-full"),
                .planInfo: (200, "get-plan-info-pro"),
                .hardLimit: (200, "get-hard-limit-full"),
                .aggregatedUsage: (200, "get-aggregated-usage-events"),
            ])
        case .cursorOnlyEmpty:
            return try MockCursorStore(responses: [
                .usageSummary: (200, "usage-summary-cursor-only-empty"),
                .sandUsage: (200, "get-sand-usage-none"),
                .planInfo: (200, "get-plan-info-pro"),
                .hardLimit: (200, "get-hard-limit-disabled"),
                .aggregatedUsage: (200, "get-aggregated-usage-empty"),
            ])
        case .cursorOnlyFull:
            return try MockCursorStore(responses: [
                .usageSummary: (200, "usage-summary-cursor-only-full"),
                .sandUsage: (200, "get-sand-usage-none"),
                .planInfo: (200, "get-plan-info-pro"),
                .hardLimit: (200, "get-hard-limit-disabled"),
                .aggregatedUsage: (200, "get-aggregated-usage-empty"),
            ])
        case .ultra:
            return try MockCursorStore(responses: [
                .usageSummary: (200, "usage-summary-ultra"),
                .sandUsage: (200, "get-sand-usage-none"),
                .planInfo: (200, "get-plan-info-ultra"),
                .hardLimit: (200, "get-hard-limit-disabled"),
                .aggregatedUsage: (200, "get-aggregated-usage-events"),
            ])
        case .teamPremium:
            return try MockCursorStore(responses: [
                .usageSummary: (200, "usage-summary-team-enterprise"),
                .sandUsage: (200, "get-sand-usage-status"),
                .planInfo: (200, "get-plan-info-team"),
                .hardLimit: (200, "get-hard-limit-limited"),
                .me: (200, "get-me-team"),
                .teamSpend: (200, "get-team-spend-premium"),
                .aggregatedUsage: (200, "get-aggregated-usage-events"),
            ])
        case .teamStandard:
            return try MockCursorStore(responses: [
                .usageSummary: (200, "usage-summary-team-enterprise"),
                .sandUsage: (200, "get-sand-usage-status"),
                .planInfo: (200, "get-plan-info-team"),
                .hardLimit: (200, "get-hard-limit-limited"),
                .me: (200, "get-me-team"),
                .teamSpend: (200, "get-team-spend-standard"),
                .aggregatedUsage: (200, "get-aggregated-usage-events"),
            ])
        }
    }
}

enum SampleProfiles {
    static func workAndPersonal(selected: String = "Work") -> [CursorProfileOption] {
        [
            CursorProfileOption(id: "/tmp/work", title: "Work", userId: "work", isSelected: selected == "Work"),
            CursorProfileOption(
                id: "/tmp/personal",
                title: "Personal",
                userId: "personal",
                isSelected: selected == "Personal"
            ),
        ]
    }

    static func three(selected: String = "Work") -> [CursorProfileOption] {
        [
            CursorProfileOption(
                id: "/tmp/default",
                title: "Default",
                userId: "default",
                isSelected: selected == "Default"
            ),
            CursorProfileOption(
                id: "/tmp/personal",
                title: "Personal",
                userId: "personal",
                isSelected: selected == "Personal"
            ),
            CursorProfileOption(id: "/tmp/work", title: "Work", userId: "work", isSelected: selected == "Work"),
        ]
    }
}

enum ScenarioLoad {
    static func state(_ scenario: Scenario) async throws -> (UsageDisplayState, MockCursorStore) {
        let store = try scenario.store()
        let state = await MockCursorHTTP.withStore(store) {
            let client = UsageClient(auth: TestAuth.make(), session: MockCursorHTTP.session())
            return await client.load(now: TestCalendar.snapshot.now)
        }
        return (state, store)
    }

    static func presentation(_ scenario: Scenario) async throws -> (MenuPresentation, UsageDisplayState, MockCursorStore) {
        let (state, store) = try await self.state(scenario)
        let presentation = MenuPresentation.make(from: state, calendar: TestCalendar.snapshot)
        return (presentation, state, store)
    }

    static func presentation(_ scenario: Scenario, profiles: [CursorProfileOption]) async throws -> MenuPresentation {
        var (presentation, state, _) = try await self.presentation(scenario)
        state.profiles = profiles
        presentation = MenuPresentation.make(from: state, calendar: TestCalendar.snapshot)
        return presentation
    }
}
