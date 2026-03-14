import Foundation

@MainActor
final class AuthStore: ObservableObject {
    @Published private(set) var session: SessionSnapshot
    @Published private(set) var pendingTwoFactor: PendingTwoFactor?
    @Published private(set) var publicSettings: PublicSettings?
    @Published var lastError: AppErrorState?

    private let client: GMNClient
    private let keychainStore: KeychainStore
    private let credentialsStore: CredentialsStore
    private let configuration: GMNRuntimeConfiguration
    private var refreshTask: Task<Void, Error>?

    private enum Key {
        static let session = "session"
        static let credentials = "credentials"
    }

    init(
        client: GMNClient,
        keychainStore: KeychainStore,
        credentialsStore: CredentialsStore,
        configuration: GMNRuntimeConfiguration
    ) {
        self.client = client
        self.keychainStore = keychainStore
        self.credentialsStore = credentialsStore
        self.configuration = configuration
        session = .empty
    }

    var isAuthenticated: Bool {
        session.authToken?.isEmpty == false
    }

    var hasRefreshToken: Bool {
        session.refreshToken?.isEmpty == false
    }

    var expiresInSeconds: Int? {
        guard let tokenExpiresAt = session.tokenExpiresAt else {
            return nil
        }

        return max(0, Int(tokenExpiresAt.timeIntervalSinceNow.rounded(.down)))
    }

    var effectiveCredentialsSource: String? {
        effectiveCredentials?.source
    }

    private var savedCredentials: Credentials? {
        try? keychainStore.loadCodable(Credentials.self, for: Key.credentials)
    }

    private var effectiveCredentials: (source: String, credentials: Credentials)? {
        if let inlineCredentials = configuration.inlineCredentials {
            return ("config", inlineCredentials)
        }

        if let savedCredentials {
            return ("saved", savedCredentials)
        }

        return nil
    }

    func initialize() async {
        if let storedSession = try? keychainStore.loadCodable(SessionSnapshot.self, for: Key.session) {
            session = storedSession
        }

        do {
            publicSettings = try await client.getPublicSettings()
            lastError = nil
        } catch let error as GMNAPIError {
            lastError = error.appErrorState
        } catch {
            lastError = GMNAPIError.network.appErrorState
        }
    }

    func login(email: String, password: String, totpSecret: String, rememberCredentials: Bool) async throws {
        guard let credentials = credentialsStore.normalizeCredentials(email: email, password: password, totpSecret: totpSecret) else {
            throw GMNAPIError.api(message: "缺少账号或密码。", code: "MISSING_CREDENTIALS", status: 400)
        }

        try await login(credentials: credentials, rememberCredentials: rememberCredentials)
    }

    func login(credentials: Credentials, rememberCredentials: Bool) async throws {
        if publicSettings?.turnstileEnabled == true {
            throw GMNAPIError.turnstileEnabled
        }

        let response = try await client.login(email: credentials.email, password: credentials.password)
        if let tempToken = response.temp_token, response.access_token == nil {
            if !credentials.totpSecret.isEmpty {
                let totpCode = try credentialsStore.generateTotp(secret: credentials.totpSecret)
                try await completeTwoFactor(tempToken: tempToken, totpCode: totpCode, rememberCredentials: rememberCredentials, credentials: credentials)
                return
            }

            pendingTwoFactor = PendingTwoFactor(tempToken: tempToken, userEmailMasked: response.user_email_masked ?? "", credentials: credentials)
            throw GMNAPIError.twoFactorRequired(tempToken: tempToken, userEmailMasked: response.user_email_masked ?? "")
        }

        try applySession(response)
        if rememberCredentials {
            try keychainStore.saveCodable(credentials, for: Key.credentials)
        }
    }

    func completeTwoFactor(tempToken: String, totpCode: String, rememberCredentials: Bool) async throws {
        try await completeTwoFactor(tempToken: tempToken, totpCode: totpCode, rememberCredentials: rememberCredentials, credentials: pendingTwoFactor?.credentials)
    }

    func ensureAuthenticated() async throws {
        if let authToken = session.authToken,
           let tokenExpiresAt = session.tokenExpiresAt,
           Date().addingTimeInterval(configuration.authRefreshLeadTime) < tokenExpiresAt,
           !authToken.isEmpty {
            return
        }

        if hasRefreshToken {
            do {
                try await refreshSession()
                return
            } catch {
                clearSession()
            }
        }

        if let effectiveCredentials {
            try await login(
                credentials: effectiveCredentials.credentials,
                rememberCredentials: effectiveCredentials.source == "saved"
            )
            return
        }

        throw GMNAPIError.authenticationRequired
    }

    func refreshSession() async throws {
        if let refreshTask {
            return try await refreshTask.value
        }

        guard let refreshToken = session.refreshToken, !refreshToken.isEmpty else {
            throw GMNAPIError.authenticationRequired
        }

        let task = Task<Void, Error> {
            let response = try await client.refresh(refreshToken: refreshToken)
            try await MainActor.run {
                try self.applySession(response)
            }
        }
        refreshTask = task
        defer { refreshTask = nil }
        try await task.value
    }

    func logout() async {
        if let refreshToken = session.refreshToken, !refreshToken.isEmpty {
            try? await client.logout(refreshToken: refreshToken)
        }
        clearSession()
    }

    func clearSavedState() {
        clearSession()
        keychainStore.removeValue(for: Key.credentials)
    }

    private func completeTwoFactor(tempToken: String, totpCode: String, rememberCredentials: Bool, credentials: Credentials?) async throws {
        guard !tempToken.isEmpty, !totpCode.isEmpty else {
            throw GMNAPIError.api(message: "缺少 2FA 参数。", code: "MISSING_2FA", status: 400)
        }

        let response = try await client.completeTwoFactor(tempToken: tempToken, totpCode: totpCode)
        try applySession(response)
        if rememberCredentials, let credentials {
            try keychainStore.saveCodable(credentials, for: Key.credentials)
        }
    }

    private func applySession(_ response: AuthResponse) throws {
        session = SessionSnapshot(
            authToken: response.access_token,
            refreshToken: response.refresh_token,
            tokenExpiresAt: response.expires_in.map { Date().addingTimeInterval(TimeInterval($0)) },
            user: response.user.map { AuthUser(email: $0.email ?? "", nickname: $0.nickname ?? "", role: $0.role ?? "") },
            updatedAt: .now
        )
        pendingTwoFactor = nil
        lastError = nil
        try keychainStore.saveCodable(session, for: Key.session)
    }

    private func clearSession() {
        session = .empty
        pendingTwoFactor = nil
        keychainStore.removeValue(for: Key.session)
    }
}
