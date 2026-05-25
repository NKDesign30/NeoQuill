import Foundation
import Security

/// Persistiert eine `ActivationRecord` in der macOS-Keychain.
///
/// Pattern parallel zu `AIProviderSecretStore`: Service-Identifier
/// `com.neon.quill.licensing.activation`, JSON-encoded Payload.
///
/// `kSecAttrAccessibleAfterFirstUnlock` — die Lizenz darf nach erstem Login
/// auch ohne aktive Touch-ID gelesen werden, damit die App im Hintergrund
/// (Sparkle, Auto-Start) ihre Berechtigung kennt.
protocol LicenseSecretStoring {
    func loadActivation() -> ActivationRecord?
    func saveActivation(_ record: ActivationRecord) throws
    func clearActivation()
}

final class KeychainLicenseSecretStore: LicenseSecretStoring {
    private let service = "com.neon.quill.licensing.activation"
    private let account = "primary"

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    func loadActivation() -> ActivationRecord? {
        let query: [CFString: CFTypeRef] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service as CFString,
            kSecAttrAccount: account as CFString,
            kSecReturnData: kCFBooleanTrue,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return try? decoder.decode(ActivationRecord.self, from: data)
    }

    func saveActivation(_ record: ActivationRecord) throws {
        let data = try encoder.encode(record)

        let baseQuery: [CFString: CFTypeRef] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service as CFString,
            kSecAttrAccount: account as CFString,
        ]
        SecItemDelete(baseQuery as CFDictionary)

        var insert = baseQuery
        insert[kSecValueData] = data as CFData
        insert[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(insert as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw LicenseSecretStoreError.keychainStatus(status)
        }
    }

    func clearActivation() {
        let query: [CFString: CFTypeRef] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service as CFString,
            kSecAttrAccount: account as CFString,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum LicenseSecretStoreError: Error, Equatable {
    case keychainStatus(OSStatus)
}

/// In-Memory-Variante für Tests.
final class InMemoryLicenseSecretStore: LicenseSecretStoring {
    private var record: ActivationRecord?

    init(initial: ActivationRecord? = nil) {
        self.record = initial
    }

    func loadActivation() -> ActivationRecord? { record }

    func saveActivation(_ record: ActivationRecord) throws {
        self.record = record
    }

    func clearActivation() {
        record = nil
    }
}
