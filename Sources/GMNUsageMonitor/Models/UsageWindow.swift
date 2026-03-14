import Foundation

struct UsageWindow: Codable, Equatable, Sendable {
    var limitUsd: Double
    var usedUsd: Double
    var remainingUsd: Double
    var percent: Double
    var resetAt: Date?
    var resetInMs: Double?

    var liveResetInMs: Double? {
        guard let resetAt else {
            return nil
        }

        return resetAt.timeIntervalSinceNow * 1000
    }
}
