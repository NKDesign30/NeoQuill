import Foundation
import Security

// Keychain-backed Storage fuer OAuth-Tokens (Access + Refresh + Expiry).
// Ein Account pro Plattform. Service-String `com.neon.quill.cloud.<provider>`.

struct CloudTokenSet: Codable, Equatable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date
    var scope: String?
    var tokenType: String

    var isExpired: Bool {
        Date() >= expiresAt.addingTimeInterval(-60)
    }
}

protocol CloudTokenPersisting {
    func load(provider: CloudProvider) -> CloudTokenSet?
    func save(provider: CloudProvider, tokens: CloudTokenSet) throws
    func clear(provider: CloudProvider)
}

enum CloudProvider: String, CaseIterable, Codable {
    case teams
    case meet
    case zoom

    var displayName: String {
        switch self {
        case .teams: return "Microsoft Teams"
        case .meet:  return "Google Meet"
        case .zoom:  return "Zoom"
        }
    }

    var keychainService: String { "com.neon.quill.cloud.\(rawValue)" }
}

final class CloudTokenStore: CloudTokenPersisting {

    func load(provider: CloudProvider) -> CloudTokenSet? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: provider.keychainService,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(CloudTokenSet.self, from: data)
    }

    func save(provider: CloudProvider, tokens: CloudTokenSet) throws {
        let data = try JSONEncoder().encode(tokens)
        let baseQuery: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: provider.keychainService,
        ]
        SecItemDelete(baseQuery as CFDictionary)
        var insert = baseQuery
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(insert as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: "CloudTokenStore", code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: "Keychain-Speicherung fehlgeschlagen (\(status))"])
        }
    }

    func clear(provider: CloudProvider) {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: provider.keychainService,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// In-Memory-Variante fuer Tests.
final class InMemoryCloudTokenStore: CloudTokenPersisting {
    private var storage: [CloudProvider: CloudTokenSet] = [:]
    func load(provider: CloudProvider) -> CloudTokenSet? { storage[provider] }
    func save(provider: CloudProvider, tokens: CloudTokenSet) throws { storage[provider] = tokens }
    func clear(provider: CloudProvider) { storage.removeValue(forKey: provider) }
}
