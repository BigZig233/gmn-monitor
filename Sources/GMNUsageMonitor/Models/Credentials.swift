import Foundation

struct Credentials: Codable, Equatable, Sendable {
    var email: String
    var password: String
    var totpSecret: String
}
