import Foundation

@MainActor
final class RefreshCoordinator {
    private let authStore: AuthStore
    private let subscriptionStore: SubscriptionStore
    private let settingsStore: SettingsStore
    private let dockStatusController: DockStatusController
    private var task: Task<Void, Never>?

    init(authStore: AuthStore, subscriptionStore: SubscriptionStore, settingsStore: SettingsStore, dockStatusController: DockStatusController) {
        self.authStore = authStore
        self.subscriptionStore = subscriptionStore
        self.settingsStore = settingsStore
        self.dockStatusController = dockStatusController
    }

    func refresh(force: Bool = false) async {
        do {
            try await authStore.ensureAuthenticated()
            if let token = authStore.session.authToken {
                do {
                    try await subscriptionStore.refreshSubscriptions(accessToken: token, force: force)
                } catch GMNAPIError.authenticationRequired {
                    try await authStore.ensureAuthenticated()
                    if let retriedToken = authStore.session.authToken {
                        try await subscriptionStore.refreshSubscriptions(accessToken: retriedToken, force: true)
                    }
                }
            }
        } catch let error as GMNAPIError {
            authStore.lastError = error.appErrorState
        } catch {
            authStore.lastError = GMNAPIError.network.appErrorState
        }

        dockStatusController.update(
            isAuthenticated: authStore.isAuthenticated,
            selectedSubscription: subscriptionStore.selectedSubscription,
            selectedDailyUsagePercent: subscriptionStore.selectedDailyUsagePercent,
            alias: settingsStore.alias(for: settingsStore.selectedSubscriptionID),
            hasError: authStore.lastError != nil || subscriptionStore.lastError != nil
        )
    }

    func scheduleCurrentPreset() {
        schedule(every: settingsStore.refreshIntervalPreset.interval)
    }

    func schedule(every interval: TimeInterval) {
        task?.cancel()
        task = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { return }
                await refresh(force: true)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}
