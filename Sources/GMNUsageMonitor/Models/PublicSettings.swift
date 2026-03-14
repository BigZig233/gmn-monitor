import Foundation

struct PublicSettings: Codable, Equatable, Sendable {
    var siteName: String
    var turnstileEnabled: Bool
    var purchaseEnabled: Bool

    static let placeholder = PublicSettings(
        siteName: "GMN",
        turnstileEnabled: false,
        purchaseEnabled: false
    )
}
