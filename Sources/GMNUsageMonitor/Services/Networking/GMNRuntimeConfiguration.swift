import Foundation

struct GMNRuntimeConfiguration: Sendable {
    var baseURL: URL
    var apiPrefix: String
    var locale: String
    var timezone: String
    var requestTimeout: TimeInterval
    var authRefreshLeadTime: TimeInterval
    var cacheTTL: TimeInterval
    var inlineCredentials: Credentials?

    @MainActor
    static func resolve(defaultsStore: DefaultsStore) -> GMNRuntimeConfiguration {
        let environment = ProcessInfo.processInfo.environment
        let credentialsStore = CredentialsStore()
        let defaultBaseURL = "https://gmn.chuangzuoli.com"
        let baseURLString = environment["GMN_BASE_URL"] ?? defaultsStore.baseURLString ?? defaultBaseURL
        let locale = environment["GMN_LOCALE"] ?? defaultsStore.locale ?? Locale.preferredLanguages.first ?? "zh"
        let timezone = environment["GMN_TIMEZONE"] ?? defaultsStore.timezone ?? TimeZone.current.identifier
        let inlineCredentials = credentialsStore.normalizeCredentials(
            email: environment["GMN_EMAIL"] ?? "",
            password: environment["GMN_PASSWORD"] ?? "",
            totpSecret: environment["GMN_TOTP_SECRET"] ?? ""
        )

        return GMNRuntimeConfiguration(
            baseURL: URL(string: baseURLString) ?? URL(string: defaultBaseURL)!,
            apiPrefix: "/api/v1",
            locale: locale,
            timezone: timezone,
            requestTimeout: 30,
            authRefreshLeadTime: 60,
            cacheTTL: 5,
            inlineCredentials: inlineCredentials
        )
    }
}
