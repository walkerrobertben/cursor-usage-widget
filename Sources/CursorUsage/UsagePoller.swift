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

    public init(statusController: StatusItemController) {
        self.statusController = statusController
        statusController.onRefreshRequested = { [weak self] in
            Task {
                await self?.refreshAll()
            }
        }
    }

    public func start() {
        do {
            let auth = try CursorAuth.resolve()
            client = UsageClient(auth: auth)
            lastState.isAuthenticated = true
            lastState.authErrorMessage = nil
        } catch {
            lastState.isAuthenticated = false
            lastState.authErrorMessage = error.localizedDescription
            pushDisplayState()
        }

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
        guard let client else { return }

        var state = await client.load()
        if !state.isAuthenticated, state.authErrorMessage == MenuPresentation.authFallbackMessage {
            do {
                let auth = try CursorAuth.resolve()
                self.client = UsageClient(auth: auth)
                state = await self.client!.load()
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
        lastState = state
        pushDisplayState()
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
#endif
