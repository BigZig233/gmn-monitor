import Foundation

struct PendingTwoFactor: Codable, Equatable, Sendable {
    var tempToken: String
    var userEmailMasked: String
    var credentials: Credentials?
}
