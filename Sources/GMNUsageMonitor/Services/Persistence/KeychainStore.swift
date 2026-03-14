import Foundation
import Security

@MainActor
final class KeychainStore {
    private let service = "GMNUsageMonitor"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        decoder.dateDecodingStrategy = .iso8601
        encoder.dateEncodingStrategy = .iso8601
    }

    func saveString(_ value: String, for key: String) throws {
        guard let data = value.data(using: .utf8) else {
            return
        }

        try saveData(data, for: key)
    }

    func loadString(for key: String) throws -> String? {
        guard let data = try loadData(for: key) else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    func saveCodable<T: Codable>(_ value: T, for key: String) throws {
        try saveData(try encoder.encode(value), for: key)
    }

    func loadCodable<T: Codable>(_ type: T.Type, for key: String) throws -> T? {
        guard let data = try loadData(for: key) else {
            return nil
        }

        return try decoder.decode(T.self, from: data)
    }

    func removeValue(for key: String) {
        let query = baseQuery(for: key)
        SecItemDelete(query as CFDictionary)
    }

    func removeValues(for keys: [String]) {
        for key in keys {
            removeValue(for: key)
        }
    }

    private func saveData(_ data: Data, for key: String) throws {
        let query = baseQuery(for: key)
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    private func loadData(for key: String) throws -> Data? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            return item as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    private func baseQuery(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
    }
}
