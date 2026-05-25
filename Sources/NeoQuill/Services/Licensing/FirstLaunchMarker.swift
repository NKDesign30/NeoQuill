import Foundation
import Security

/// Speichert das Datum des allerersten App-Starts in der Keychain.
/// Wird in `AppState.init` aufgerufen, BEVOR der Enforcement-Modus geprüft wird.
///
/// Warum Keychain statt UserDefaults:
/// - UserDefaults wird beim "App neu installieren" gelöscht, Keychain nicht
///   (sofern User-Account erhalten bleibt)
/// - schwerer zu manipulieren als plist-Datei
/// - bleibt erhalten auch wenn die App neu signiert wird (gleicher Bundle-ID).
///
/// Mitigation gegen "App komplett neu auf neuem Mac": LS-Discount-Codes
/// ("BETA100") für manuelle Beta-Grace-Vergabe.
protocol FirstLaunchMarkerStoring {
    func firstLaunchDate() -> Date?
    func ensureMarker(now: Date) throws
    func reset()
}

/// Real-Keychain-Implementierung. Service-Identifier nach NeoQuill-Konvention
/// (com.neon.quill.<bereich>).
final class KeychainFirstLaunchMarker: FirstLaunchMarkerStoring {
    private let service = "com.neon.quill.licensing.first-launch"
    private let account = "marker"

    func firstLaunchDate() -> Date? {
        let query: [CFString: CFTypeRef] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service as CFString,
            kSecAttrAccount: account as CFString,
            kSecReturnData: kCFBooleanTrue,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let iso = String(data: data, encoding: .utf8) else { return nil }
        return Self.formatter.date(from: iso)
    }

    func ensureMarker(now: Date) throws {
        if firstLaunchDate() != nil { return }

        let iso = Self.formatter.string(from: now)
        guard let data = iso.data(using: .utf8) else {
            throw FirstLaunchMarkerError.encodingFailed
        }

        let insert: [CFString: CFTypeRef] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service as CFString,
            kSecAttrAccount: account as CFString,
            kSecValueData: data as CFData,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemAdd(insert as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else {
            throw FirstLaunchMarkerError.keychainStatus(status)
        }
    }

    /// Nur für QA-Builds + Tests. Production-UI ruft das niemals auf.
    func reset() {
        let query: [CFString: CFTypeRef] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service as CFString,
            kSecAttrAccount: account as CFString,
        ]
        SecItemDelete(query as CFDictionary)
    }

    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}

enum FirstLaunchMarkerError: Error, Equatable {
    case encodingFailed
    case keychainStatus(OSStatus)
}

/// In-Memory-Variante. Wird in Tests gegen das Protocol getauscht.
final class InMemoryFirstLaunchMarker: FirstLaunchMarkerStoring {
    private var date: Date?

    init(initialDate: Date? = nil) {
        self.date = initialDate
    }

    func firstLaunchDate() -> Date? {
        date
    }

    func ensureMarker(now: Date) throws {
        if date == nil { date = now }
    }

    func reset() {
        date = nil
    }
}
