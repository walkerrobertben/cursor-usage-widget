#if canImport(AppKit)
import Foundation
import AppKit
import CursorUsageCore

public final class UsagePoller {
    private let statusController: StatusItemController
    private var client: UsageClient?

    private var summaryTimer: Timer?
    private var aggregationTimer: Timer?

    private var lastState = UsageDisplayState()
    private var previousApiPercent: Double?
    private var previousAutoPercent: Double?
    private var previousBotPercent: Double?
    private var selectedDatabasePath: String?
    private var selectedUserId: String?
    private var loadGeneration = 0

    public init(statusController: StatusItemController) {
        self.statusController = statusController
        statusController.onRefreshRequested = { [weak self] in
            Task {
                await self?.refreshAll()
            }
        }
        statusController.onMenuWillOpen = { [weak self] in
            self?.refreshProfileOptions()
        }
        statusController.onProfileSelected = { [weak self] databasePath in
            self?.selectProfile(databasePath: databasePath)
        }
    }

    public func start() {
        attachResolvedAuth()
        pushDisplayState()

        summaryTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(AppInfo.summaryPollSeconds), repeats: true) { [weak self] _ in
            Task {
                await self?.refreshAll()
            }
        }

        aggregationTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(AppInfo.aggregationPollSeconds), repeats: true) { [weak self] _ in
            Task {
                await self?.refreshAll()
            }
        }

        Task {
            await refreshAll()
        }
    }

    func refreshAll() async {
        let generation = loadGeneration
        let expectedPath = selectedDatabasePath
        guard let client else {
            refreshProfileOptions()
            return
        }

        var state = await client.load()
        guard generation == loadGeneration, expectedPath == selectedDatabasePath else { return }

        if !state.isAuthenticated, state.authErrorMessage == MenuPresentation.authFallbackMessage {
            do {
                let auth = try resolveAuth()
                self.client = UsageClient(auth: auth)
                state = await self.client!.load()
                guard generation == loadGeneration, expectedPath == selectedDatabasePath else { return }
            } catch {
                state.authErrorMessage = error.localizedDescription
            }
        }

        let apiIncreased = increased(current: state.summary?.apiPercentUsed, previous: previousApiPercent)
        let autoIncreased = increased(current: state.summary?.autoPercentUsed, previous: previousAutoPercent)
        let botIncreased = increased(current: state.sandUsage?.usagePercent, previous: previousBotPercent)

        previousApiPercent = state.summary?.apiPercentUsed
        previousAutoPercent = state.summary?.autoPercentUsed
        previousBotPercent = state.sandUsage?.usagePercent

        state.apiPercentIncreased = apiIncreased
        state.autoPercentIncreased = autoIncreased
        state.botPercentIncreased = botIncreased
        attachProfiles(to: &state)
        lastState = state
        pushDisplayState()
    }

    private func attachResolvedAuth() {
        do {
            let auth = try resolveAuth()
            client = UsageClient(auth: auth)
            lastState.isAuthenticated = true
            lastState.authErrorMessage = nil
            attachProfiles(to: &lastState)
        } catch {
            lastState.isAuthenticated = false
            lastState.authErrorMessage = error.localizedDescription
            attachProfiles(to: &lastState)
            pushDisplayState()
        }
    }

    private func selectProfile(databasePath: String) {
        let normalized = (databasePath as NSString).standardizingPath
        if normalized == selectedDatabasePath {
            return
        }
        if let selectedUserId,
           let clicked = lastState.profiles.first(where: { $0.id == normalized }),
           clicked.userId == selectedUserId
        {
            return
        }

        ProfileMemory.select(normalized)
        selectedDatabasePath = normalized
        loadGeneration += 1
        previousApiPercent = nil
        previousAutoPercent = nil
        previousBotPercent = nil

        do {
            let auth = try resolveAuth(required: true)
            client = UsageClient(auth: auth)
            lastState.summary = nil
            lastState.aggregations = nil
            lastState.weeklyAggregations = nil
            lastState.sandUsage = nil
            lastState.planInfo = nil
            lastState.hardLimit = nil
            lastState.teamSeat = nil
            lastState.lastUpdated = nil
            lastState.apiPercentIncreased = false
            lastState.autoPercentIncreased = false
            lastState.botPercentIncreased = false
            lastState.isAuthenticated = true
            lastState.authErrorMessage = nil
            attachProfiles(to: &lastState)
            statusController.apply(state: lastState)
            Task {
                await refreshAll()
            }
        } catch {
            lastState = UsageDisplayState(
                isAuthenticated: false,
                authErrorMessage: error.localizedDescription
            )
            attachProfiles(to: &lastState)
            statusController.apply(state: lastState)
        }
    }

    private func refreshProfileOptions() {
        attachProfiles(to: &lastState)
        statusController.apply(state: lastState)
    }

    private func resolveAuth(required: Bool = false) throws -> CursorAuth {
        let auth = try CursorAuth.resolve(
            overrides: authOverrides(),
            preferring: selectedDatabasePath ?? ProfileMemory.selectedDatabasePath,
            required: required
        )
        selectedDatabasePath = auth.databasePath
        selectedUserId = auth.userId
        ProfileMemory.select(auth.databasePath)
        return auth
    }

    private func authOverrides() -> CursorAuthOverrides {
        CursorAuthOverrides(additionalStateDBs: ProfileMemory.seenDatabasePaths)
    }

    private func attachProfiles(to state: inout UsageDisplayState) {
        let profiles = CursorAuth.listUsableProfiles(overrides: authOverrides())
        ProfileMemory.remember(paths: profiles.map(\.databasePath))
        state.profiles = profiles.map { profile in
            CursorProfileOption(
                id: profile.databasePath,
                title: profile.title,
                userId: profile.userId,
                isSelected: profile.userId == selectedUserId || profile.databasePath == selectedDatabasePath
            )
        }
    }

    private func increased(current: Double?, previous: Double?) -> Bool {
        guard let current, let previous else { return false }
        return current > previous
    }

    private func pushDisplayState() {
        let state = lastState
        DispatchQueue.main.async { [statusController] in
            statusController.apply(state: state)
        }
    }
}

private enum ProfileMemory {
    static let selectedKey = "selectedCursorStateDB"
    static let seenKey = "seenCursorStateDBs"
    static let seenLimit = 20

    static var selectedDatabasePath: String? {
        UserDefaults.standard.string(forKey: selectedKey)
    }

    static var seenDatabasePaths: [String] {
        UserDefaults.standard.stringArray(forKey: seenKey) ?? []
    }

    static func select(_ path: String) {
        let normalized = (path as NSString).standardizingPath
        UserDefaults.standard.set(normalized, forKey: selectedKey)
        remember(paths: [normalized])
    }

    static func remember(paths: [String]) {
        var seen = seenDatabasePaths
        for path in paths {
            let normalized = (path as NSString).standardizingPath
            if let index = seen.firstIndex(of: normalized) {
                seen.remove(at: index)
            }
            seen.append(normalized)
        }
        if seen.count > seenLimit {
            seen = Array(seen.suffix(seenLimit))
        }
        UserDefaults.standard.set(seen, forKey: seenKey)
    }
}
#endif
