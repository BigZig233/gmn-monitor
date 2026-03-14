import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    @Published var selectedSubscriptionID: Int?
    @Published var selectedSubscriptionAlias: String
    @Published var refreshIntervalPreset: RefreshIntervalPreset

    private let defaultsStore: DefaultsStore

    init(defaultsStore: DefaultsStore) {
        self.defaultsStore = defaultsStore
        let selectedSubscriptionID = defaultsStore.selectedSubscriptionID
        self.selectedSubscriptionID = selectedSubscriptionID
        selectedSubscriptionAlias = defaultsStore.selectedSubscriptionAlias(for: selectedSubscriptionID)
        refreshIntervalPreset = defaultsStore.refreshIntervalPreset
    }

    func selectSubscription(id: Int?) {
        selectedSubscriptionID = id
        defaultsStore.selectedSubscriptionID = id
        selectedSubscriptionAlias = alias(for: id)
    }

    func alias(for subscriptionID: Int?) -> String {
        defaultsStore.selectedSubscriptionAlias(for: subscriptionID)
    }

    func updateAlias(_ alias: String) {
        guard let selectedSubscriptionID else {
            selectedSubscriptionAlias = ""
            return
        }

        defaultsStore.setSelectedSubscriptionAlias(alias, for: selectedSubscriptionID)
        selectedSubscriptionAlias = defaultsStore.selectedSubscriptionAlias(for: selectedSubscriptionID)
    }

    func updateRefreshInterval(_ preset: RefreshIntervalPreset) {
        refreshIntervalPreset = preset
        defaultsStore.refreshIntervalPreset = preset
    }

    func clearSelection() {
        selectedSubscriptionID = nil
        selectedSubscriptionAlias = ""
        defaultsStore.selectedSubscriptionID = nil
    }

    func clearAll() {
        selectedSubscriptionID = nil
        selectedSubscriptionAlias = ""
        refreshIntervalPreset = .fifteenSeconds
        defaultsStore.clearAll()
    }
}
