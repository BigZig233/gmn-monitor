import Foundation

struct AppErrorState: Codable, Equatable, Sendable, Identifiable {
    var name: String
    var message: String
    var code: String?
    var status: Int
    var at: Date

    var id: String {
        "\(name)-\(status)-\(at.timeIntervalSince1970)"
    }
}
