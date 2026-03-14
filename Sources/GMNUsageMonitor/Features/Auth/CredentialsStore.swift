import CryptoKit
import Foundation

@MainActor
final class CredentialsStore: ObservableObject {
    func normalizeSecret(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }

        if trimmed.hasPrefix("otpauth://"),
           let components = URLComponents(string: trimmed) {
            return (components.queryItems?.first(where: { $0.name == "secret" })?.value ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: " ", with: "")
                .uppercased()
        }

        return trimmed
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
            .uppercased()
    }

    func normalizeCredentials(email: String, password: String, totpSecret: String) -> Credentials? {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedEmail.isEmpty, !password.isEmpty else {
            return nil
        }

        return Credentials(
            email: normalizedEmail,
            password: password,
            totpSecret: normalizeSecret(totpSecret)
        )
    }

    func generateTotp(secret: String, now: Date = .now) throws -> String {
        let key = try decodeBase32(secret)
        let counter = UInt64(floor(now.timeIntervalSince1970 / 30))
        var bigEndianCounter = counter.bigEndian
        let message = Data(bytes: &bigEndianCounter, count: MemoryLayout<UInt64>.size)
        let hash = HMAC<Insecure.SHA1>.authenticationCode(for: message, using: SymmetricKey(data: key))
        let bytes = Array(hash)
        let offset = Int(bytes[bytes.count - 1] & 0x0F)
        let binary =
            (UInt32(bytes[offset] & 0x7F) << 24) |
            (UInt32(bytes[offset + 1] & 0xFF) << 16) |
            (UInt32(bytes[offset + 2] & 0xFF) << 8) |
            UInt32(bytes[offset + 3] & 0xFF)
        let code = binary % 1_000_000
        return String(format: "%06d", code)
    }

    private func decodeBase32(_ input: String) throws -> Data {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
        let clean = normalizeSecret(input).replacingOccurrences(of: "=", with: "")
        guard !clean.isEmpty else {
            throw GMNAPIError.api(message: "TOTP Secret 不是合法的 Base32。", code: "BAD_TOTP_SECRET", status: 400)
        }

        var bits = ""
        for character in clean {
            guard let index = alphabet.firstIndex(of: character) else {
                throw GMNAPIError.api(message: "TOTP Secret 不是合法的 Base32。", code: "BAD_TOTP_SECRET", status: 400)
            }
            bits += String(index, radix: 2).leftPadding(toLength: 5, withPad: "0")
        }

        var bytes: [UInt8] = []
        var index = bits.startIndex
        while index < bits.endIndex {
            let next = bits.index(index, offsetBy: 8, limitedBy: bits.endIndex) ?? bits.endIndex
            let slice = bits[index..<next]
            if slice.count == 8, let value = UInt8(slice, radix: 2) {
                bytes.append(value)
            }
            index = next
        }
        return Data(bytes)
    }
}

private extension String {
    func leftPadding(toLength: Int, withPad character: Character) -> String {
        guard count < toLength else { return self }
        return String(repeating: String(character), count: toLength - count) + self
    }
}
