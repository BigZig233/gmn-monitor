import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    @Published var selectedSubscriptionID: Int?
    @Published var selectedSubscriptionAlias: String
    @Published var refreshIntervalPreset: RefreshIntervalPreset

    private let defaultsStore: DefaultsStore

    init(defaultsStore: DefaultsStore) {
        self.defaultsStore = defaultsStore
        selectedSubscriptionID = defaultsStore.selectedSubscriptionID
        selectedSubscriptionAlias = defaultsStore.selectedSubscriptionAlias
        refreshIntervalPreset = defaultsStore.refreshIntervalPreset
    }

    func selectSubscription(id: Int?) {
        selectedSubscriptionID = id
        defaultsStore.selectedSubscriptionID = id
    }

    func updateAlias(_ alias: String) {
        selectedSubscriptionAlias = alias
        defaultsStore.selectedSubscriptionAlias = alias
    }

    func updateRefreshInterval(_ preset: RefreshIntervalPreset) {
        refreshIntervalPreset = preset
        defaultsStore.refreshIntervalPreset = preset
    }

    func clearSelection() {
        selectSubscription(id: nil)
        updateAlias("")
    }

    func clearAll() {
        selectedSubscriptionID = nil
        selectedSubscriptionAlias = ""
        refreshIntervalPreset = .fifteenSeconds
        defaultsStore.clearAll()
    }
}
