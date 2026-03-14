import Foundation

struct SessionSnapshot: Codable, Equatable, Sendable {
    var authToken: String?
    var refreshToken: String?
    var tokenExpiresAt: Date?
    var user: AuthUser?
    var updatedAt: Date?

    static let empty = SessionSnapshot(
        authToken: nil,
        refreshToken: nil,
        tokenExpiresAt: nil,
        user: nil,
        updatedAt: nil
    )
}
