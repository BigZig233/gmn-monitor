import Foundation

struct Subscription: Codable, Equatable, Sendable, Identifiable {
    struct Usage: Codable, Equatable, Sendable {
        var daily: UsageWindow?
        var weekly: UsageWindow?
        var monthly: UsageWindow?
    }

    var id: Int
    var groupID: Int?
    var status: String
    var expiresAtIso: String?
    var expiresInDays: Int?
    var groupName: String
    var groupDescription: String
    var unlimited: Bool
    var usage: Usage
}
