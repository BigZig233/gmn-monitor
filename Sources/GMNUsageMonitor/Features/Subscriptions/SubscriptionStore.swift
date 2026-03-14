import Foundation

@MainActor
final class SubscriptionStore: ObservableObject {
    @Published private(set) var subscriptions: [Subscription] = []
    @Published private(set) var lastFetchedAt: Date?
    @Published var lastError: AppErrorState?

    private let client: GMNClient
    private let configuration: GMNRuntimeConfiguration
    private weak var settingsStore: SettingsStore?

    private var lastFetchTime: Date?

    init(client: GMNClient, configuration: GMNRuntimeConfiguration, settingsStore: SettingsStore) {
        self.client = client
        self.configuration = configuration
        self.settingsStore = settingsStore
    }

    var selectedSubscription: Subscription? {
        guard let id = settingsStore?.selectedSubscriptionID else {
            return nil
        }

        return subscriptions.first(where: { $0.id == id })
    }

    var selectedDailyUsagePercent: Double? {
        selectedSubscription?.usage.daily?.percent
    }

    func refreshSubscriptions(accessToken: String, force: Bool = false) async throws {
        if !force, let lastFetchTime, Date().timeIntervalSince(lastFetchTime) < configuration.cacheTTL {
            return
        }

        do {
            let raw = try await client.fetchSubscriptions(accessToken: accessToken)
            let enriched = raw.map(enrichSubscription(_:))
            subscriptions = enriched
            lastFetchedAt = .now
            lastFetchTime = .now
            lastError = nil
            syncSelection()
        } catch let error as GMNAPIError {
            lastError = error.appErrorState
            throw error
        } catch {
            let mapped = GMNAPIError.network
            lastError = mapped.appErrorState
            throw mapped
        }
    }

    func clear() {
        subscriptions = []
        lastFetchedAt = nil
        lastFetchTime = nil
        lastError = nil
    }

    private func syncSelection() {
        guard let settingsStore, let selectedID = settingsStore.selectedSubscriptionID else {
            return
        }

        if !subscriptions.contains(where: { $0.id == selectedID }) {
            settingsStore.clearSelection()
        }
    }

    private func enrichSubscription(_ item: RawSubscription) -> Subscription {
        let expiresDate = item.expires_at.flatMap { DateParser.date(from: $0) }
        let expiresInDays = expiresDate.map {
            Int(ceil($0.timeIntervalSinceNow / 86_400))
        }
        let unlimited = (item.group?.daily_limit_usd ?? 0) == 0 && (item.group?.weekly_limit_usd ?? 0) == 0 && (item.group?.monthly_limit_usd ?? 0) == 0

        return Subscription(
            id: item.id,
            groupID: item.group_id,
            status: item.status ?? "unknown",
            expiresAtIso: expiresDate.map { DateParser.string(from: $0) },
            expiresInDays: expiresInDays,
            groupName: item.group?.name ?? "Group #\(item.group_id.map(String.init) ?? "Unknown")",
            groupDescription: item.group?.description ?? "",
            unlimited: unlimited,
            usage: .init(
                daily: buildUsageWindow(limit: item.group?.daily_limit_usd, used: item.daily_usage_usd, windowStart: item.daily_window_start, hours: 24),
                weekly: buildUsageWindow(limit: item.group?.weekly_limit_usd, used: item.weekly_usage_usd, windowStart: item.weekly_window_start, hours: 168),
                monthly: buildUsageWindow(limit: item.group?.monthly_limit_usd, used: item.monthly_usage_usd, windowStart: item.monthly_window_start, hours: 720)
            )
        )
    }

    private func buildUsageWindow(limit: Double?, used: Double?, windowStart: String?, hours: Double) -> UsageWindow? {
        guard let limit, limit.isFinite, limit > 0 else {
            return nil
        }

        let usedUsd = used ?? 0
        let percent = min((usedUsd / limit) * 100, 100)
        let resetAt = windowStart.flatMap { DateParser.date(from: $0) }?.addingTimeInterval(hours * 3600)
        return UsageWindow(
            limitUsd: limit,
            usedUsd: usedUsd,
            remainingUsd: max(0, limit - usedUsd),
            percent: percent,
            resetAt: resetAt,
            resetInMs: resetAt.map { $0.timeIntervalSinceNow * 1000 }
        )
    }
}

@MainActor
enum DateParser {
    private static let internetDateTimeFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let fractionalSecondsFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func date(from value: String) -> Date? {
        fractionalSecondsFormatter.date(from: value) ?? internetDateTimeFormatter.date(from: value)
    }

    static func string(from date: Date) -> String {
        fractionalSecondsFormatter.string(from: date)
    }
}
