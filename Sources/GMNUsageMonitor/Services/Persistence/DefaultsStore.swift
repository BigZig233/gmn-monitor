import Foundation

@MainActor
final class DefaultsStore {
    private let defaults: UserDefaults

    private enum Key {
        static let selectedSubscriptionID = "selectedSubscriptionId"
        static let selectedSubscriptionAlias = "selectedSubscriptionAlias"
        static let refreshIntervalPreset = "refreshIntervalPreset"
        static let baseURL = "baseUrl"
        static let locale = "locale"
        static let timezone = "timezone"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var selectedSubscriptionID: Int? {
        get {
            defaults.object(forKey: Key.selectedSubscriptionID) as? Int
        }
        set {
            defaults.set(newValue, forKey: Key.selectedSubscriptionID)
        }
    }

    var selectedSubscriptionAlias: String {
        get {
            defaults.string(forKey: Key.selectedSubscriptionAlias) ?? ""
        }
        set {
            defaults.set(newValue, forKey: Key.selectedSubscriptionAlias)
        }
    }

    var refreshIntervalPreset: RefreshIntervalPreset {
        get {
            guard let raw = defaults.string(forKey: Key.refreshIntervalPreset),
                  let preset = RefreshIntervalPreset(rawValue: raw) else {
                return .fifteenSeconds
            }

            return preset
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.refreshIntervalPreset)
        }
    }

    var baseURLString: String? {
        get { defaults.string(forKey: Key.baseURL) }
        set { defaults.set(newValue, forKey: Key.baseURL) }
    }

    var locale: String? {
        get { defaults.string(forKey: Key.locale) }
        set { defaults.set(newValue, forKey: Key.locale) }
    }

    var timezone: String? {
        get { defaults.string(forKey: Key.timezone) }
        set { defaults.set(newValue, forKey: Key.timezone) }
    }

    func clearAll() {
        defaults.removeObject(forKey: Key.selectedSubscriptionID)
        defaults.removeObject(forKey: Key.selectedSubscriptionAlias)
        defaults.removeObject(forKey: Key.refreshIntervalPreset)
        defaults.removeObject(forKey: Key.baseURL)
        defaults.removeObject(forKey: Key.locale)
        defaults.removeObject(forKey: Key.timezone)
    }
}
