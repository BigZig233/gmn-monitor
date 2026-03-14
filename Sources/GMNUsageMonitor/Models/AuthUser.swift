import Foundation

struct AuthUser: Codable, Equatable, Sendable {
    var email: String
    var nickname: String
    var role: String
}
