import Foundation

enum RefreshIntervalPreset: String, CaseIterable, Codable, Sendable, Identifiable {
    case fifteenSeconds
    case thirtySeconds
    case oneMinute
    case fiveMinutes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fifteenSeconds:
            "15 秒"
        case .thirtySeconds:
            "30 秒"
        case .oneMinute:
            "1 分钟"
        case .fiveMinutes:
            "5 分钟"
        }
    }

    var interval: TimeInterval {
        switch self {
        case .fifteenSeconds:
            15
        case .thirtySeconds:
            30
        case .oneMinute:
            60
        case .fiveMinutes:
            300
        }
    }
}
