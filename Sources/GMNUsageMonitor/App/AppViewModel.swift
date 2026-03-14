import Foundation
import SwiftUI

@MainActor
final class AppViewModel: ObservableObject {
    enum Phase {
        case login
        case twoFactor
        case selectSubscription
        case monitor
    }

    @Published var phase: Phase = .login
    @Published var email = ""
    @Published var password = ""
    @Published var totpSecret = ""
    @Published var rememberCredentials = true
    @Published var manualTotpCode = ""
    @Published var message = ""
    @Published var isBusy = false

    let settingsStore: SettingsStore
    let authStore: AuthStore
    let subscriptionStore: SubscriptionStore
    let dockStatusController: DockStatusController
    let refreshCoordinator: RefreshCoordinator
    var onMenuStateChange: (() -> Void)?

    private var hasStarted = false

    var menuStatusSummary: String {
        if authStore.pendingTwoFactor != nil {
            return "需要完成 2FA 验证"
        }

        guard authStore.isAuthenticated else {
            return "未登录"
        }

        guard let subscription = subscriptionStore.selectedSubscription else {
            return "已登录，未选择订阅"
        }

        if let percent = subscriptionStore.selectedDailyUsagePercent {
            return "\(subscription.groupName) · 今日 \(percent.formatted(.number.precision(.fractionLength(1))))%"
        }

        if subscription.unlimited {
            return "\(subscription.groupName) · 无限额度"
        }

        return "\(subscription.groupName) · 已连接"
    }

    init() {
        let defaultsStore = DefaultsStore()
        let configuration = GMNRuntimeConfiguration.resolve(defaultsStore: defaultsStore)
        let keychainStore = KeychainStore()
        let credentialsStore = CredentialsStore()
        let client = GMNClient(configuration: configuration)
        let settingsStore = SettingsStore(defaultsStore: defaultsStore)
        let authStore = AuthStore(
            client: client,
            keychainStore: keychainStore,
            credentialsStore: credentialsStore,
            configuration: configuration
        )
        let subscriptionStore = SubscriptionStore(
            client: client,
            configuration: configuration,
            settingsStore: settingsStore
        )
        let dockAdapter = DockProgressAdapter()
        let dockStatusController = DockStatusController(adapter: dockAdapter)

        self.settingsStore = settingsStore
        self.authStore = authStore
        self.subscriptionStore = subscriptionStore
        self.dockStatusController = dockStatusController
        refreshCoordinator = RefreshCoordinator(
            authStore: authStore,
            subscriptionStore: subscriptionStore,
            settingsStore: settingsStore,
            dockStatusController: dockStatusController
        )
    }

    func start() async {
        guard !hasStarted else {
            return
        }
        hasStarted = true
        await authStore.initialize()
        await refreshCoordinator.refresh(force: true)
        refreshCoordinator.scheduleCurrentPreset()
        updatePhase()
        onMenuStateChange?()
    }

    func refreshNow() async {
        isBusy = true
        defer {
            isBusy = false
            onMenuStateChange?()
        }
        await refreshCoordinator.refresh(force: true)
        updatePhase()
    }

    func appDidBecomeActive() async {
        await refreshNow()
    }

    func submitLogin() async {
        isBusy = true
        defer {
            isBusy = false
            onMenuStateChange?()
        }

        do {
            try await authStore.login(
                email: email,
                password: password,
                totpSecret: totpSecret,
                rememberCredentials: rememberCredentials
            )
            message = "登录成功。"
            await refreshCoordinator.refresh(force: true)
        } catch let error as GMNAPIError {
            if case .twoFactorRequired = error {
                message = "登录成功进入 2FA 阶段，请补验证码。"
            } else {
                message = error.errorDescription ?? "请求失败。"
            }
        } catch {
            message = error.localizedDescription
        }

        updatePhase()
    }

    func submitTwoFactor() async {
        guard let tempToken = authStore.pendingTwoFactor?.tempToken else {
            message = "当前没有待完成的 2FA 登录。"
            return
        }

        isBusy = true
        defer {
            isBusy = false
            onMenuStateChange?()
        }

        do {
            try await authStore.completeTwoFactor(
                tempToken: tempToken,
                totpCode: manualTotpCode,
                rememberCredentials: rememberCredentials
            )
            manualTotpCode = ""
            message = "2FA 登录完成。"
            await refreshCoordinator.refresh(force: true)
        } catch {
            message = error.localizedDescription
        }

        updatePhase()
    }

    func selectSubscription(_ subscription: Subscription) {
        settingsStore.selectSubscription(id: subscription.id)
        dockStatusController.update(
            isAuthenticated: authStore.isAuthenticated,
            selectedSubscription: subscription,
            selectedDailyUsagePercent: subscription.usage.daily?.percent,
            alias: settingsStore.selectedSubscriptionAlias,
            hasError: authStore.lastError != nil || subscriptionStore.lastError != nil
        )
        updatePhase()
        onMenuStateChange?()
    }

    func saveAlias(_ alias: String) {
        settingsStore.updateAlias(alias)
        dockStatusController.update(
            isAuthenticated: authStore.isAuthenticated,
            selectedSubscription: subscriptionStore.selectedSubscription,
            selectedDailyUsagePercent: subscriptionStore.selectedDailyUsagePercent,
            alias: alias,
            hasError: authStore.lastError != nil || subscriptionStore.lastError != nil
        )
        onMenuStateChange?()
    }

    func updateRefreshPreset(_ preset: RefreshIntervalPreset) {
        settingsStore.updateRefreshInterval(preset)
        refreshCoordinator.scheduleCurrentPreset()
        onMenuStateChange?()
    }

    func clearSelectedSubscription() {
        settingsStore.clearSelection()
        dockStatusController.reset()
        updatePhase()
        onMenuStateChange?()
    }

    func logout() async {
        isBusy = true
        defer {
            isBusy = false
            onMenuStateChange?()
        }

        await authStore.logout()
        subscriptionStore.clear()
        settingsStore.clearSelection()
        dockStatusController.reset()
        message = "已退出当前会话。"
        updatePhase()
    }

    func clearSavedState() {
        authStore.clearSavedState()
        subscriptionStore.clear()
        settingsStore.clearAll()
        dockStatusController.reset()
        message = "已清除保存状态。"
        updatePhase()
        onMenuStateChange?()
    }

    func updatePhase() {
        if authStore.pendingTwoFactor != nil {
            phase = .twoFactor
        } else if !authStore.isAuthenticated {
            phase = .login
        } else if subscriptionStore.selectedSubscription == nil {
            phase = .selectSubscription
        } else {
            phase = .monitor
        }
    }
}
