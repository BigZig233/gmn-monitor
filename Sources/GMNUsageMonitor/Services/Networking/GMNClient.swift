import Foundation

private struct Envelope<T: Decodable>: Decodable {
    let code: Int?
    let message: String?
    let detail: String?
    let data: T?
}

private struct AnyDecodable: Decodable {}

actor GMNClient {
    private let configuration: GMNRuntimeConfiguration
    private let session: URLSession

    init(configuration: GMNRuntimeConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    func getPublicSettings() async throws -> PublicSettings {
        struct Response: Decodable {
            let site_name: String?
            let turnstile_enabled: Bool?
            let purchase_subscription_enabled: Bool?
        }

        let response: Response = try await request(path: "/settings/public", requiresAuth: false, includeTimezone: false)
        return PublicSettings(
            siteName: response.site_name ?? "GMN",
            turnstileEnabled: response.turnstile_enabled ?? false,
            purchaseEnabled: response.purchase_subscription_enabled ?? false
        )
    }

    func login(email: String, password: String) async throws -> AuthResponse {
        try await request(path: "/auth/login", method: "POST", body: ["email": email, "password": password], requiresAuth: false, includeTimezone: false)
    }

    func completeTwoFactor(tempToken: String, totpCode: String) async throws -> AuthResponse {
        try await request(path: "/auth/login/2fa", method: "POST", body: ["temp_token": tempToken, "totp_code": totpCode], requiresAuth: false, includeTimezone: false)
    }

    func refresh(refreshToken: String) async throws -> AuthResponse {
        try await request(path: "/auth/refresh", method: "POST", body: ["refresh_token": refreshToken], requiresAuth: false, includeTimezone: false)
    }

    func logout(refreshToken: String) async throws {
        let _: AnyDecodable = try await request(path: "/auth/logout", method: "POST", body: ["refresh_token": refreshToken], requiresAuth: false, includeTimezone: false)
    }

    func fetchSubscriptions(accessToken: String) async throws -> [RawSubscription] {
        try await request(path: "/subscriptions", token: accessToken)
    }

    private func request<T: Decodable>(
        path: String,
        method: String = "GET",
        body: [String: String]? = nil,
        token: String? = nil,
        requiresAuth: Bool = true,
        includeTimezone: Bool? = nil
    ) async throws -> T {
        let shouldIncludeTimezone = includeTimezone ?? (method == "GET")
        var url = configuration.baseURL.appending(path: configuration.apiPrefix + path)
        if shouldIncludeTimezone, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "timezone", value: configuration.timezone)]
            url = components.url ?? url
        }

        var request = URLRequest(url: url, timeoutInterval: configuration.requestTimeout)
        request.httpMethod = method
        request.setValue(configuration.locale, forHTTPHeaderField: "Accept-Language")
        if requiresAuth, let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw GMNAPIError.network
        }

        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 500

        do {
            let envelope = try JSONDecoder.gmn.decode(Envelope<T>.self, from: data)
            if let code = envelope.code {
                guard code == 0 else {
                    if statusCode == 401 {
                        throw GMNAPIError.authenticationRequired
                    }
                    throw GMNAPIError.api(message: envelope.message ?? envelope.detail ?? "请求失败。", code: String(code), status: statusCode)
                }
                guard let payload = envelope.data else {
                    throw GMNAPIError.decoding
                }
                return payload
            }

            if !(200 ..< 300).contains(statusCode) {
                if statusCode == 401 {
                    throw GMNAPIError.authenticationRequired
                }
                throw GMNAPIError.api(
                    message: envelope.message ?? envelope.detail ?? HTTPURLResponse.localizedString(forStatusCode: statusCode),
                    code: nil,
                    status: statusCode
                )
            }
        } catch let error as GMNAPIError {
            throw error
        } catch {
            if !(200 ..< 300).contains(statusCode) {
                if statusCode == 401 {
                    throw GMNAPIError.authenticationRequired
                }
                throw GMNAPIError.api(message: HTTPURLResponse.localizedString(forStatusCode: statusCode), code: nil, status: statusCode)
            }
        }

        if !(200 ..< 300).contains(statusCode) {
            if statusCode == 401 {
                throw GMNAPIError.authenticationRequired
            }
            throw GMNAPIError.api(message: HTTPURLResponse.localizedString(forStatusCode: statusCode), code: nil, status: statusCode)
        }

        do {
            return try JSONDecoder.gmn.decode(T.self, from: data)
        } catch {
            throw GMNAPIError.decoding
        }
    }
}

extension JSONDecoder {
    static let gmn: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

struct AuthResponse: Decodable, Sendable {
    let access_token: String?
    let refresh_token: String?
    let expires_in: Int?
    let user: RawAuthUser?
    let temp_token: String?
    let user_email_masked: String?
}

struct RawAuthUser: Decodable, Sendable {
    let email: String?
    let nickname: String?
    let role: String?
}

struct RawSubscription: Decodable, Sendable {
    struct Group: Decodable, Sendable {
        let name: String?
        let description: String?
        let daily_limit_usd: Double?
        let weekly_limit_usd: Double?
        let monthly_limit_usd: Double?
    }

    let id: Int
    let group_id: Int?
    let status: String?
    let expires_at: String?
    let group: Group?
    let daily_usage_usd: Double?
    let daily_window_start: String?
    let weekly_usage_usd: Double?
    let weekly_window_start: String?
    let monthly_usage_usd: Double?
    let monthly_window_start: String?
}
